import Testing
@testable import MenubarTranslateCore

/// Engine that parks inside `translate` until `release()` is called, so a test can
/// issue a second `AppViewModel.translate()` while the first is still in flight.
private final class GateEngine: TranslationEngine, @unchecked Sendable {
    private(set) var texts: [String] = []
    private var waiter: CheckedContinuation<Void, Never>?
    private var parked = false
    private var parkWaiter: CheckedContinuation<Void, Never>?

    func load() async throws {}

    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        texts.append(text)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            waiter = cont
            parked = true
            parkWaiter?.resume()
            parkWaiter = nil
        }
        return "[\(pair.token)] \(text)"
    }

    func evict() async {}

    func waitUntilParked() async {
        if parked { return }
        await withCheckedContinuation { parkWaiter = $0 }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}

@Suite("AppViewModel — in-flight guards")
@MainActor
struct AppViewModelGuardTests {

    @Test("a second translate() while busy is ignored")
    func overlappingTranslateIgnored() async {
        let engine = GateEngine()
        let runtime = AppRuntime(
            engine: engine,
            preset: .conservative8GB,
            fallback: nil,
            fallbackAvailable: nil,
            clock: ManualClock(),
            pressureSource: FakePressureSource()
        )
        let vm = AppViewModel(runtime: runtime)
        vm.setInput("first")

        let pending = Task { @MainActor in await vm.translate() }
        await engine.waitUntilParked()

        vm.setInput("second")
        await vm.translate()
        engine.release()
        await pending.value

        #expect(engine.texts == ["first"])
        #expect(vm.output == "[ja-en] first")
    }
}
