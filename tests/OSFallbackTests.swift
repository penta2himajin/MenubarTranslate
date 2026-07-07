// WRITE-LOCKED — M3 Wave B: OS-translation fallback seam tests.
// These tests encode the exact public contract for FallbackCapability + OSTranslationEngine.
// Do NOT delete, skip, weaken assertions, or change expected values.
// Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/OSFallbackTests.swift

import Testing
@testable import MenubarTranslateCore

// MARK: - Helpers

/// A reference-typed capability holder so a test can flip the gate after `load()`.
/// `@unchecked Sendable`: single-threaded test usage, no real concurrency.
private final class MutableAvailability: @unchecked Sendable {
    var capability: FallbackCapability
    init(_ capability: FallbackCapability) { self.capability = capability }
}

/// Records the arguments the translator closure received.
private final class Recorder: @unchecked Sendable {
    var text: String?
    var pair: LanguagePair?
}

private func allTrue() -> FallbackCapability {
    FallbackCapability(apiPresent: true, pairSupported: true, modelDownloaded: true)
}

/// Assert an async op throws `TranslationEngineError.unavailable` specifically.
private func expectUnavailable(_ op: () async throws -> Void) async {
    do {
        try await op()
        Issue.record("expected TranslationEngineError.unavailable, but nothing was thrown")
    } catch let error as TranslationEngineError {
        guard case .unavailable = error else {
            Issue.record("expected .unavailable, got \(error)")
            return
        }
    } catch {
        Issue.record("expected TranslationEngineError, got \(error)")
    }
}

// MARK: - Suite

@Suite("OSFallback — M3 Wave B: capability gate + OS engine adapter")
struct OSFallbackTests {

    // ── (a) three-layer gate, all 8 combinations ──────────────────────────────

    @Test("isAvailable is true only when all three flags are true (8-row truth table)")
    func gateTruthTable() {
        for apiPresent in [false, true] {
            for pairSupported in [false, true] {
                for modelDownloaded in [false, true] {
                    let cap = FallbackCapability(
                        apiPresent: apiPresent,
                        pairSupported: pairSupported,
                        modelDownloaded: modelDownloaded
                    )
                    #expect(
                        cap.isAvailable == (apiPresent && pairSupported && modelDownloaded),
                        "gate open iff all three layers hold: \(cap)"
                    )
                }
            }
        }
    }

    // ── (b) load reflects the gate ─────────────────────────────────────────────

    @Test("load succeeds when all flags true")
    func loadSucceedsWhenAvailable() async throws {
        let engine = OSTranslationEngine(availability: allTrue, translator: { text, _ in text })
        try await engine.load() // must not throw
    }

    @Test("load throws .unavailable when any flag is false")
    func loadThrowsWhenAnyFlagFalse() async {
        let closed: [FallbackCapability] = [
            FallbackCapability(apiPresent: false, pairSupported: true, modelDownloaded: true),
            FallbackCapability(apiPresent: true, pairSupported: false, modelDownloaded: true),
            FallbackCapability(apiPresent: true, pairSupported: true, modelDownloaded: false),
            FallbackCapability(apiPresent: false, pairSupported: false, modelDownloaded: false),
        ]
        for cap in closed {
            let engine = OSTranslationEngine(availability: { cap }, translator: { text, _ in text })
            await expectUnavailable { try await engine.load() }
        }
    }

    // ── (c) translate returns closure output and receives exact text + pair ────

    @Test("translate returns the translator output and passes the exact text + pair through")
    func translateForwardsArgumentsAndReturnsOutput() async throws {
        let recorder = Recorder()
        let engine = OSTranslationEngine(
            availability: allTrue,
            translator: { text, pair in
                recorder.text = text
                recorder.pair = pair
                return "OUT:\(text)"
            }
        )
        try await engine.load()
        let output = try await engine.translate("こんにちは", .jaToEn)
        #expect(output == "OUT:こんにちは")
        #expect(recorder.text == "こんにちは")
        #expect(recorder.pair == .jaToEn)
    }

    // ── (d) translate re-checks availability ───────────────────────────────────

    @Test("translate throws .unavailable when the gate closes after load")
    func translateThrowsWhenAvailabilityFlipsFalse() async throws {
        let avail = MutableAvailability(allTrue())
        let engine = OSTranslationEngine(
            availability: { avail.capability },
            translator: { text, _ in text }
        )
        try await engine.load()
        avail.capability = FallbackCapability(
            apiPresent: true, pairSupported: true, modelDownloaded: false
        )
        await expectUnavailable { _ = try await engine.translate("hi", .jaToEn) }
    }

    // ── (e) evict has no residency semantics ───────────────────────────────────

    @Test("evict then translate still works (fallback has no residency)")
    func evictThenTranslateStillWorks() async throws {
        let engine = OSTranslationEngine(
            availability: allTrue,
            translator: { text, _ in "OK:\(text)" }
        )
        try await engine.load()
        await engine.evict()
        let output = try await engine.translate("z", .enToJa)
        #expect(output == "OK:z")
    }

    // ── (f) plugs into AppRuntime as the fallback under critical ───────────────

    @Test("OSTranslationEngine routes as AppRuntime fallback under critical + gate open")
    func plugsIntoAppRuntimeFallback() async throws {
        let clock = ManualClock()
        let pressure = FakePressureSource()
        let primary = FakeEngine()
        let cap = allTrue()
        let os = OSTranslationEngine(
            availability: { cap },
            translator: { text, _ in "[os] \(text)" }
        )
        let runtime = AppRuntime(
            engine: primary,
            preset: .conservative8GB,
            fallback: os,
            fallbackAvailable: { cap.isAvailable },
            clock: clock,
            pressureSource: pressure
        )
        pressure.emit(.critical)
        let result = try await runtime.translate("hello", .jaToEn)
        #expect(result == "[os] hello")
        #expect(
            primary.calls.filter { $0 == .load }.count == 0,
            "primary weights must never load when the OS fallback path is taken"
        )
    }
}
