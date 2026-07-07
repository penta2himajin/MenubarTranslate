// WRITE-LOCKED — M3 Wave C1: observable AppViewModel tests.
// These tests encode the exact public contract for TranslationDirection + AppViewModel.
// Do NOT delete, skip, weaken assertions, or change expected values.
// Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/AppViewModelTests.swift

import Testing
@testable import MenubarTranslateCore

// MARK: - Doubles

/// Engine that translates fine, then throws once armed. Lets a test drive a success
/// followed by a failure so "previous output preserved" is observable.
private final class ScriptedEngine: TranslationEngine, @unchecked Sendable {
    var shouldThrow = false
    private(set) var loadCount = 0

    func load() async throws { loadCount += 1 }

    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        if shouldThrow { throw TranslationEngineError.unavailable("boom") }
        return "[\(pair.token)] \(text)"
    }

    func evict() async {}
}

/// Engine that fires a hook the instant it runs `translate`, so a test can sample the
/// view model's `isBusy` mid-flight without spawning a Task (same call stack, no Sendable
/// boundary crossing).
private final class ProbeEngine: TranslationEngine {
    var onTranslate: (() -> Void)?

    func load() async throws {}

    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        onTranslate?()
        return "[\(pair.token)] \(text)"
    }

    func evict() async {}
}

// MARK: - Fixture

private struct Fixture {
    let clock = ManualClock()
    let pressure = FakePressureSource()
    let engine = FakeEngine()
    let vm: AppViewModel

    init() {
        let runtime = AppRuntime(
            engine: engine,
            preset: .conservative8GB,
            fallback: nil,
            fallbackAvailable: nil,
            clock: clock,
            pressureSource: pressure
        )
        vm = AppViewModel(runtime: runtime)
    }
}

private func makeVM(engine: any TranslationEngine) -> AppViewModel {
    let runtime = AppRuntime(
        engine: engine,
        preset: .conservative8GB,
        fallback: nil,
        fallbackAvailable: nil,
        clock: ManualClock(),
        pressureSource: FakePressureSource()
    )
    return AppViewModel(runtime: runtime)
}

// MARK: - Suite

@Suite("AppViewModel — M3 Wave C1 observable view model")
struct AppViewModelTests {

    // ── (a) happy path ─────────────────────────────────────────────────────────

    @Test("translate() sets output to the engine result and clears errorMessage")
    func translateHappyPath() async {
        let f = Fixture()
        f.vm.setInput("こんにちは")
        await f.vm.translate()
        #expect(f.vm.output == "[ja-en] こんにちは")
        #expect(f.vm.errorMessage == nil)
    }

    // ── (b) direction routing ──────────────────────────────────────────────────

    @Test("direction .enToJa routes the en-ja pair")
    func directionRoutesEnToJa() async {
        let f = Fixture()
        f.vm.direction = .enToJa
        f.vm.setInput("hello")
        await f.vm.translate()
        #expect(f.vm.output == "[en-ja] hello")
    }

    // ── (c) empty / whitespace guard ───────────────────────────────────────────

    @Test("empty and whitespace-only input are a no-op; runtime never invoked")
    func emptyInputIsNoOp() async {
        let f = Fixture()
        f.vm.setInput("")
        await f.vm.translate()
        #expect(f.vm.output == "")

        f.vm.setInput("   \n\t ")
        await f.vm.translate()
        #expect(f.vm.output == "")

        #expect(f.engine.calls.isEmpty, "runtime/engine must not be called for blank input")
    }

    // ── (d) failure preserves prior output ─────────────────────────────────────

    @Test("a failing engine sets errorMessage and preserves the previous output")
    func failurePreservesOutput() async {
        let engine = ScriptedEngine()
        let vm = makeVM(engine: engine)

        vm.setInput("x")
        await vm.translate()
        #expect(vm.output == "[ja-en] x")
        #expect(vm.errorMessage == nil)

        engine.shouldThrow = true
        vm.setInput("y")
        await vm.translate()
        #expect(vm.errorMessage != nil, "engine failure must surface an errorMessage")
        #expect(vm.output == "[ja-en] x", "previous output must be preserved on failure")
    }

    // ── (e) isBusy toggles around the call ─────────────────────────────────────

    @Test("isBusy is true while translate is in flight and false afterwards")
    func isBusyTogglesAroundCall() async {
        let engine = ProbeEngine()
        let vm = makeVM(engine: engine)
        var busyDuringCall = false
        engine.onTranslate = { busyDuringCall = vm.isBusy }

        vm.setInput("x")
        #expect(vm.isBusy == false)
        await vm.translate()
        #expect(busyDuringCall == true, "isBusy must be true while the engine runs")
        #expect(vm.isBusy == false, "isBusy must be false after translate completes")
    }

    // ── (f) snapshot mirrors the runtime ───────────────────────────────────────

    @Test("snapshot starts unloaded+normal and reflects a critical pressure emission")
    func snapshotMirrorsRuntime() {
        let f = Fixture()
        #expect(f.vm.snapshot == RuntimeSnapshot(phase: .unloaded, pressure: .normal))
        f.pressure.emit(.critical)
        #expect(f.vm.snapshot.pressure == .critical)
    }

    // ── (g) direction toggle + pair codes ──────────────────────────────────────

    @Test("TranslationDirection.toggle flips ja-en <-> en-ja and .pair carries the codes")
    func directionToggleAndPair() {
        var d = TranslationDirection.jaToEn
        d.toggle()
        #expect(d == .enToJa)
        d.toggle()
        #expect(d == .jaToEn)

        #expect(TranslationDirection.jaToEn.pair == .jaToEn)
        #expect(TranslationDirection.enToJa.pair == .enToJa)
        #expect(TranslationDirection.jaToEn.pair.token == "ja-en")
        #expect(TranslationDirection.enToJa.pair.token == "en-ja")
    }
}
