import Testing
import Dispatch
@testable import MenubarTranslateCore

@Suite("Pressure — Domain B")
struct PressureTests {
    @Test("levels are ordered normal < warn < critical")
    func ordering() {
        #expect(PressureLevel.normal < PressureLevel.warn)
        #expect(PressureLevel.warn < PressureLevel.critical)
        #expect(PressureLevel.normal < PressureLevel.critical)
    }

    @Test("FakePressureSource.emit fires the handler synchronously with the new level")
    func fakeEmitsSynchronously() {
        let source = FakePressureSource()
        var observed: [PressureLevel] = []
        source.onChange { observed.append($0) }
        source.emit(.warn)
        source.emit(.critical)
        source.emit(.normal)
        #expect(observed == [.warn, .critical, .normal])
        #expect(source.current == .normal)
    }

    #if canImport(Darwin)
    @Test("dispatch flag mapping picks the highest severity present")
    func dispatchFlagMapping() {
        #expect(pressureLevel(from: .normal) == .normal)
        #expect(pressureLevel(from: .warning) == .warn)
        #expect(pressureLevel(from: .critical) == .critical)
        #expect(pressureLevel(from: [.warning, .critical]) == .critical)
        #expect(pressureLevel(from: [.normal, .warning]) == .warn)
    }
    #endif
}

@Suite("Clock — monotonic time")
struct ClockTests {
    @Test("ManualClock.advance moves now forward monotonically")
    func advance() {
        let clock = ManualClock()
        let t0 = clock.now
        clock.advance(by: .seconds(5))
        let t1 = clock.now
        clock.advance(by: .milliseconds(500))
        let t2 = clock.now
        #expect(t0 < t1)
        #expect(t1 < t2)
        #expect(t1.elapsed(since: t0) == .seconds(5))
    }

    @Test("elapsed clamps at zero for a later reference")
    func elapsedClamps() {
        let earlier = Instant(nanos: 100)
        let later = Instant(nanos: 50)
        #expect(later.elapsed(since: earlier) == .zero)
    }
}
