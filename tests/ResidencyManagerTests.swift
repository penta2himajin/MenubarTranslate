import Testing
@testable import MenubarTranslateCore

/// Records the transition trace and eviction decisions for assertions.
private final class Recorder {
    var events: [ResidencyEvent] = []
    var evictions = 0
    var loadRequests: Int { events.filter { $0.event == .loadRequested }.count }
    func lastEvictReason() -> LifecycleReason? {
        events.last { $0.event == .evictRequested }?.reason
    }
}

private extension ResidencyConfig {
    /// Deterministic tunables: 30 s idle, 5 s floor, 2 s warn debounce.
    static let test = ResidencyConfig(
        idleTimeout: .seconds(30),
        residencyFloor: .seconds(5),
        warnDebounce: .seconds(2)
    )
}

/// Builds a manager with trace capture and an `onEvict` spy that completes eviction
/// synchronously (simulating an instantaneous release), so decisions land in one step.
private func harness(
    config: ResidencyConfig = .test
) -> (ResidencyManager, ManualClock, FakePressureSource, Recorder) {
    let clock = ManualClock()
    let pressure = FakePressureSource()
    let manager = ResidencyManager(config: config, clock: clock, pressureSource: pressure)
    let rec = Recorder()
    manager.onEvent = { rec.events.append($0) }
    manager.onEvict = { [weak manager] in
        rec.evictions += 1
        manager?.completeEviction()
    }
    return (manager, clock, pressure, rec)
}

private func loadReady(_ m: ResidencyManager) throws {
    try m.beginLoad()
    try m.completeLoad()
}

private func useOnce(_ m: ResidencyManager) throws {
    try m.beginInference()
    try m.endInference()
}

@Suite("ResidencyManager — thrash-avoidance policy (ADR 0003/0004/0006)")
struct ResidencyManagerTests {
    @Test("user-intent path loads then infers")
    func userIntentPath() throws {
        let (m, _, _, rec) = harness()
        try loadReady(m)
        try useOnce(m)
        #expect(m.state == .ready)
        #expect(rec.loadRequests == 1)
    }

    @Test("loading is never triggered by a pressure event")
    func pressureNeverLoads() {
        let (m, _, pressure, rec) = harness()
        pressure.emit(.warn)
        pressure.emit(.critical)
        #expect(rec.loadRequests == 0)
        #expect(m.state == .unloaded)
    }

    @Test("warn right after load does not evict (residency floor)")
    func warnWithinFloorDoesNotEvict() throws {
        let (m, clock, pressure, rec) = harness()
        try loadReady(m)                 // t = 0
        pressure.emit(.warn)             // warnSince = 0
        clock.advance(by: .seconds(2))   // debounce satisfied, floor (5 s) not
        m.tick()
        #expect(m.state == .ready)
        #expect(rec.evictions == 0)
    }

    @Test("warn evicts once both debounce and floor have elapsed")
    func warnAfterFloorEvicts() throws {
        let (m, clock, pressure, rec) = harness()
        try loadReady(m)                 // t = 0
        pressure.emit(.warn)
        clock.advance(by: .seconds(5))   // floor + debounce both satisfied
        m.tick()
        #expect(m.state == .unloaded)
        #expect(rec.evictions == 1)
        #expect(rec.lastEvictReason() == .pressureWarn)
    }

    @Test("transient warn blip is debounced away")
    func warnBlipDebounced() throws {
        let (m, clock, pressure, rec) = harness()
        try loadReady(m)
        pressure.emit(.warn)
        clock.advance(by: .seconds(1))   // inside the 2 s debounce
        pressure.emit(.normal)           // blip cleared
        clock.advance(by: .seconds(10))
        m.tick()
        #expect(m.state == .ready)
        #expect(rec.evictions == 0)
    }

    @Test("critical evicts immediately, bypassing the floor")
    func criticalBypassesFloor() throws {
        let (m, _, pressure, rec) = harness()
        try loadReady(m)                 // t = 0, well inside the floor
        pressure.emit(.critical)
        #expect(m.state == .unloaded)
        #expect(rec.evictions == 1)
        #expect(rec.lastEvictReason() == .pressureCritical)
    }

    @Test("critical during inference defers eviction until after use")
    func criticalDuringInferenceEvictsAfterUse() throws {
        let (m, _, pressure, rec) = harness()
        try loadReady(m)
        try m.beginInference()           // inferring
        pressure.emit(.critical)         // must NOT release weights mid-flight
        #expect(m.state == .inferring)
        #expect(rec.evictions == 0)
        try m.endInference()             // now evict-after-use
        #expect(m.state == .unloaded)
        #expect(rec.evictions == 1)
        #expect(rec.lastEvictReason() == .evictAfterUse)
    }

    @Test("idle timeout evicts")
    func idleTimeoutEvicts() throws {
        let (m, clock, _, rec) = harness()
        try loadReady(m)
        try useOnce(m)                   // lastUse = 0
        clock.advance(by: .seconds(30))
        m.tick()
        #expect(m.state == .unloaded)
        #expect(rec.evictions == 1)
        #expect(rec.lastEvictReason() == .idleTimeout)
    }

    @Test("idle timeout not yet reached does not evict")
    func idleNotReached() throws {
        let (m, clock, _, rec) = harness()
        try loadReady(m)
        try useOnce(m)
        clock.advance(by: .seconds(29))
        m.tick()
        #expect(m.state == .ready)
        #expect(rec.evictions == 0)
    }

    @Test("a translation resets the idle timer")
    func useResetsIdleTimer() throws {
        let (m, clock, _, rec) = harness()
        try loadReady(m)
        try useOnce(m)                   // lastUse = 0
        clock.advance(by: .seconds(20))
        try useOnce(m)                   // lastUse = 20 (resets)
        clock.advance(by: .seconds(20))  // t = 40, but only 20 s since last use
        m.tick()
        #expect(m.state == .ready)
        #expect(rec.evictions == 0)
    }

    @Test("sustained warn evicts exactly once — no evict↔load oscillation")
    func noOscillationUnderSustainedWarn() throws {
        let (m, clock, pressure, rec) = harness()
        try loadReady(m)
        pressure.emit(.warn)
        clock.advance(by: .seconds(5))
        m.tick()                         // evicts once
        #expect(m.state == .unloaded)
        #expect(rec.evictions == 1)

        for _ in 0..<10 {                // pressure stays warn
            clock.advance(by: .seconds(5))
            m.tick()
        }
        #expect(m.state == .unloaded)    // never reloads
        #expect(rec.evictions == 1)
        #expect(rec.loadRequests == 1)   // the one original user-intent load
    }

    @Test("warn/critical while unloaded is a no-op")
    func pressureWhileUnloadedIsNoop() {
        let (m, _, pressure, rec) = harness()
        pressure.emit(.warn)
        pressure.emit(.critical)
        #expect(m.state == .unloaded)
        #expect(rec.evictions == 0)
        #expect(rec.loadRequests == 0)
    }

    @Test("benign pressure while ready under normal never mutates the lifecycle")
    func benignPressureNoLifecycleChange() throws {
        let (m, _, pressure, rec) = harness()
        try loadReady(m)
        pressure.emit(.normal)
        #expect(m.state == .ready)
        #expect(rec.evictions == 0)
    }
}
