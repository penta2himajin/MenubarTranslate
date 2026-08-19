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

    @Test("live prefixes of the same draft coalesce into one history row")
    func livePrefixesCoalesce() async {
        let vm = makeVM()
        vm.targetLanguage = .en
        await vm.translateLive(draft: "こ")
        await vm.translateLive(draft: "こん")
        await vm.translateLive(draft: "こんにちは")
        #expect(vm.history.count == 1)
        #expect(vm.history[0].source == "こんにちは")
        #expect(vm.history[0].output == "[ja-en] こんにちは")
    }

    @Test("live backspace still updates the same history row")
    func liveBackspaceCoalesces() async {
        let vm = makeVM()
        vm.targetLanguage = .en
        await vm.translateLive(draft: "こんにちは")
        let id = vm.history[0].id
        await vm.translateLive(draft: "こんに")
        #expect(vm.history.count == 1)
        #expect(vm.history[0].id == id)
        #expect(vm.history[0].source == "こんに")
    }

    @Test("IME conversion within a burst replaces the romaji row")
    func liveIMEConversionCoalesces() async {
        let vm = makeVM()
        vm.targetLanguage = .en
        await vm.translateLive(draft: "konnichiha")
        await vm.translateLive(draft: "こんにちは")
        #expect(vm.history.count == 1)
        #expect(vm.history[0].source == "こんにちは")
    }

    @Test("clearing the field starts a new history row")
    func liveClearStartsNewRow() async {
        let vm = makeVM()
        vm.targetLanguage = .en
        await vm.translateLive(draft: "こんにちは")
        await vm.translateLive(draft: "  ")
        await vm.translateLive(draft: "今日は雨")
        #expect(vm.history.count == 2)
        #expect(vm.history[0].source == "今日は雨")
        #expect(vm.history[1].source == "こんにちは")
    }
}
