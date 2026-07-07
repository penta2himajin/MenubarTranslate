// WRITE-LOCKED — Wave 3 (M3-A) AppRuntime facade tests.
// These tests encode the exact public contract for AppRuntime.
// Do NOT delete, skip, weaken assertions, or change expected values.
// Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/AppRuntimeTests.swift

import Testing
@testable import MenubarTranslateCore

// MARK: - Fixture

private struct Fixture {
    let clock = ManualClock()
    let pressure = FakePressureSource()
    let engine = FakeEngine()
    let runtime: AppRuntime

    init(
        preset: MemoryPreset = .conservative8GB,
        fallback: (any TranslationEngine)? = nil,
        fallbackAvailable: (() -> Bool)? = nil
    ) {
        runtime = AppRuntime(
            engine: engine,
            preset: preset,
            fallback: fallback,
            fallbackAvailable: fallbackAvailable,
            clock: clock,
            pressureSource: pressure
        )
    }
}

// MARK: - Suite

@Suite("AppRuntime — M3 Wave A facade")
struct AppRuntimeTests {

    // ── (1) cold start ────────────────────────────────────────────────────────

    @Test("cold start: first translate loads engine and returns FakeEngine output")
    func coldStartLoadsAndReturns() async throws {
        let f = Fixture()
        let result = try await f.runtime.translate("こんにちは", .jaToEn)
        #expect(result == "[ja-en] こんにちは")
        #expect(f.engine.calls.filter { $0 == .load }.count == 1)
    }

    // ── (2) warm reuse ────────────────────────────────────────────────────────

    @Test("warm reuse: second translate does not reload (load count stays 1)")
    func warmReuseDoesNotReload() async throws {
        let f = Fixture()
        _ = try await f.runtime.translate("a", .jaToEn)
        _ = try await f.runtime.translate("b", .jaToEn)
        #expect(f.engine.calls.filter { $0 == .load }.count == 1)
    }

    // ── (3) idle timeout ──────────────────────────────────────────────────────

    @Test("idle timeout: clock advance past timeout + tick evicts weights")
    func idleTimeoutEvicts() async throws {
        let f = Fixture() // conservative8GB: idleTimeout = 30 s
        _ = try await f.runtime.translate("x", .jaToEn)
        f.clock.advance(by: .seconds(31))
        await f.runtime.tick()
        #expect(f.runtime.snapshot.phase == .unloaded)
    }

    // ── (4) preset comparison ─────────────────────────────────────────────────

    @Test("conservative8GB evicts after 60 s idle but permissive16GB does not")
    func presetIdleTimeoutDiffers() async throws {
        let f8  = Fixture(preset: .conservative8GB)
        let f16 = Fixture(preset: .permissive16GB)
        _ = try await f8.runtime.translate("a", .jaToEn)
        _ = try await f16.runtime.translate("a", .jaToEn)
        f8.clock.advance(by: .seconds(60))
        f16.clock.advance(by: .seconds(60))
        await f8.runtime.tick()
        await f16.runtime.tick()
        #expect(f8.runtime.snapshot.phase == .unloaded)
        #expect(f16.runtime.snapshot.phase == .ready)
    }

    // ── (5) critical evict-after-use ──────────────────────────────────────────

    @Test("critical pressure: translate completes then weights evicted after use")
    func criticalPressureEvictsAfterUse() async throws {
        let f = Fixture()
        f.pressure.emit(.critical)
        _ = try await f.runtime.translate("x", .jaToEn)
        #expect(f.runtime.snapshot.phase == .unloaded)
    }

    // ── (6) fallback routing ──────────────────────────────────────────────────

    @Test("fallback routing: critical + fallbackAvailable=true uses fallback, primary never loaded")
    func fallbackRoutingUnderCritical() async throws {
        let fallback = FakeEngine(transform: { text, _ in "[fallback] \(text)" })
        let f = Fixture(fallback: fallback, fallbackAvailable: { true })
        f.pressure.emit(.critical)
        let result = try await f.runtime.translate("hello", .jaToEn)
        #expect(result == "[fallback] hello")
        #expect(
            f.engine.calls.filter { $0 == .load }.count == 0,
            "primary engine must not be loaded when fallback path is taken"
        )
    }

    // ── (7) gate closed ───────────────────────────────────────────────────────

    @Test("gate closed: critical + fallbackAvailable=false uses primary engine")
    func gateClosedUsesPrimary() async throws {
        let fallback = FakeEngine()
        let f = Fixture(fallback: fallback, fallbackAvailable: { false })
        f.pressure.emit(.critical)
        _ = try await f.runtime.translate("x", .jaToEn)
        #expect(f.engine.calls.filter { $0 == .load }.count == 1)
        #expect(fallback.calls.filter { $0 == .load }.count == 0)
    }

    // ── (8) normal pressure ignores fallback ──────────────────────────────────

    @Test("normal pressure + fallbackAvailable=true: primary path used (fallback only under critical)")
    func normalPressureIgnoresFallback() async throws {
        let fallback = FakeEngine()
        let f = Fixture(fallback: fallback, fallbackAvailable: { true })
        // pressure stays .normal — no emit
        _ = try await f.runtime.translate("x", .jaToEn)
        #expect(f.engine.calls.filter { $0 == .load }.count == 1)
        #expect(fallback.calls.filter { $0 == .load }.count == 0)
    }

    // ── (9) onChange observation ──────────────────────────────────────────────

    @Test("onChange fires loading and inferring transitions; final snapshot phase is .ready")
    func onChangeObservation() async throws {
        let f = Fixture()
        var snapshots: [RuntimeSnapshot] = []
        f.runtime.onChange = { snapshots.append($0) }
        _ = try await f.runtime.translate("hi", .jaToEn)
        let phases = snapshots.map(\.phase)
        #expect(phases.contains(.loading),   "onChange must fire during loading")
        #expect(phases.contains(.inferring), "onChange must fire during inference")
        #expect(snapshots.last?.phase == .ready, "final onChange snapshot must be .ready")
    }

    // ── (10) initial snapshot — M-invariance ──────────────────────────────────

    @Test("initial snapshot is unloaded + normal (M-invariance)")
    func initialSnapshotIsUnloadedNormal() {
        let f = Fixture()
        #expect(f.runtime.snapshot == RuntimeSnapshot(phase: .unloaded, pressure: .normal))
    }

    // ── (11) unsupported pair — adversarial ───────────────────────────────────

    @Test("unsupported LanguagePair throws (adversarial: fr→de is not supported)")
    func unsupportedPairThrows() async {
        let f = Fixture()
        let frDe = LanguagePair(
            sourceCode: "fr", sourceName: "French",
            targetCode: "de", targetName: "German"
        )
        await #expect(throws: (any Error).self) {
            _ = try await f.runtime.translate("bonjour", frDe)
        }
    }

    // ── (12) tick without idle does not evict ─────────────────────────────────

    @Test("tick with no elapsed idle time does not evict (phase stays .ready)")
    func tickWithoutIdleDoesNotEvict() async throws {
        let f = Fixture()
        _ = try await f.runtime.translate("x", .jaToEn)
        // No clock advance — idle timeout not reached
        await f.runtime.tick()
        #expect(f.runtime.snapshot.phase == .ready)
    }
}
