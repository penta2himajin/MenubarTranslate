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

@Suite("Panel presentation")
@MainActor
struct PanelPresentationTests {

    @Test("translate(draft:) uses the draft, not a stale setInput")
    func translateDraftUsesArgument() async {
        let vm = makeVM()
        vm.setInput("stale")
        await vm.translate(draft: "こんにちは")
        #expect(vm.input == "こんにちは")
        #expect(vm.output == "[ja-en] こんにちは")
        #expect(vm.errorMessage == nil)
        #expect(vm.isBusy == false)
    }

    @Test("canSubmit is false for blank draft or while busy")
    func canSubmitGatesBlankAndBusy() async {
        let vm = makeVM()
        #expect(vm.canSubmit("") == false)
        #expect(vm.canSubmit("  \n") == false)
        #expect(vm.canSubmit("x") == true)

        let engine = ProbeBusyEngine()
        let busyVM = makeVM(engine: engine)
        engine.onTranslate = { #expect(busyVM.canSubmit("x") == false) }
        busyVM.setInput("x")
        await busyVM.translate()
    }

    @Test("labels follow direction and snapshot")
    func labelsFollowState() {
        let vm = makeVM()
        #expect(vm.directionLabel == "JA → EN")
        #expect(vm.statusLine == "unloaded · normal")
        #expect(vm.progressCaption == nil)
        vm.direction = .enToJa
        #expect(vm.directionLabel == "EN → JA")
    }

    @Test("progressCaption is set while translate is in flight")
    func progressCaptionWhileBusy() async {
        let engine = ProbeBusyEngine()
        let vm = makeVM(engine: engine)
        var caption: String?
        engine.onTranslate = { caption = vm.progressCaption }
        vm.setInput("x")
        await vm.translate()
        #expect(caption != nil)
        #expect(vm.progressCaption == nil)
    }

    @Test("translate(draft:) surfaces engine failures on errorMessage")
    func translateDraftSurfacesError() async {
        let vm = makeVM(engine: FailingDraftEngine())
        await vm.translate(draft: "x")
        #expect(vm.output.isEmpty)
        #expect(vm.errorMessage?.contains("boom") == true)
    }
}

/// Fires `onTranslate` on the same call stack as `AppViewModel.translate` (MainActor).
private final class ProbeBusyEngine: TranslationEngine, @unchecked Sendable {
    var onTranslate: (() -> Void)?
    func load() async throws {}
    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        onTranslate?()
        return "[\(pair.token)] \(text)"
    }
    func evict() async {}
}

private final class FailingDraftEngine: TranslationEngine, @unchecked Sendable {
    func load() async throws {}
    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        throw TranslationEngineError.unavailable("boom")
    }
    func evict() async {}
}
