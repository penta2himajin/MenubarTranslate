import Testing
@testable import MenubarTranslateCore

@Suite("FakeEngine")
struct FakeEngineTests {
    @Test("records load → translate → evict in order")
    func callOrder() async throws {
        let engine = FakeEngine()
        try await engine.load()
        _ = try await engine.translate("こんにちは", .jaToEn)
        await engine.evict()
        #expect(engine.calls == [.load, .translate("こんにちは", .jaToEn), .evict])
    }

    @Test("returns the configured output for a direction")
    func output() async throws {
        let engine = FakeEngine()
        try await engine.load()
        #expect(try await engine.translate("hello", .enToJa) == "[en-ja] hello")
        #expect(try await engine.translate("こんにちは", .jaToEn) == "[ja-en] こんにちは")
    }

    @Test("custom transform is honored")
    func customTransform() async throws {
        let engine = FakeEngine { text, _ in text.uppercased() }
        try await engine.load()
        #expect(try await engine.translate("hello", .enToJa) == "HELLO")
    }

    @Test("translate before load throws notLoaded")
    func translateBeforeLoadThrows() async {
        let engine = FakeEngine()
        await #expect(throws: TranslationEngineError.notLoaded) {
            _ = try await engine.translate("hello", .enToJa)
        }
    }
}
