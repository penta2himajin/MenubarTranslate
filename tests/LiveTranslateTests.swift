import Testing
@testable import MenubarTranslateCore

@MainActor
private func makeVM(engine: any TranslationEngine = FakeEngine()) -> AppViewModel {
    AppViewModel(
        runtime: AppRuntime(
            engine: engine,
            preset: .conservative8GB,
            fallback: nil,
            fallbackAvailable: nil,
            clock: ManualClock(),
            pressureSource: FakePressureSource()
        )
    )
}

@Suite("Live translate and history")
@MainActor
struct LiveTranslateTests {

    @Test("translateLive detects Japanese and uses targetLanguage")
    func liveDetectsSource() async {
        let vm = makeVM()
        vm.targetLanguage = .en
        await vm.translateLive(draft: "こんにちは")
        #expect(vm.output == "[ja-en] こんにちは")
    }

    @Test("same-language live translate copies without calling the engine")
    func sameLanguageCopies() async {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        vm.targetLanguage = .ja
        await vm.translateLive(draft: "こんにちは")
        #expect(vm.output == "こんにちは")
        #expect(engine.calls.isEmpty)
    }

    @Test("history records and applyHistory restores source, output, and target")
    func historyRoundTrip() async {
        let vm = makeVM()
        vm.targetLanguage = .en
        await vm.translateLive(draft: "こんにちは")
        #expect(vm.history.count == 1)

        vm.targetLanguage = .zh
        vm.setInput("changed")
        vm.applyHistory(vm.history[0])
        #expect(vm.input == "こんにちは")
        #expect(vm.output == "[ja-en] こんにちは")
        #expect(vm.targetLanguage == .en)
    }
}
