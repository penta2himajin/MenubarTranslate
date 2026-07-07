// WRITE-LOCKED — Wave 0 engine-seam tests.
// These tests encode the exact public contract. Do NOT delete, skip, weaken assertions,
// or change expected values. Compile-level fixes (renames, import changes) must be reported.
// Lock copy: .devloop/locks/EngineSeamTests.swift

import Testing
import Foundation
@testable import MenubarTranslateCore
import MTEngineLlama
import MTEngineMLX

// MARK: - Test-local helper

/// An engine whose `load()` always throws `.unavailable(message)`.
/// Used to exercise the CLI factory-injection path without a real engine binary.
private final class AlwaysUnavailableEngine: TranslationEngine {
    let message: String
    init(message: String) { self.message = message }
    func load() async throws { throw TranslationEngineError.unavailable(message) }
    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        throw TranslationEngineError.notLoaded
    }
    func evict() async {}
}

// MARK: - Suite

@Suite("Engine seam — Wave 0 locked")
struct EngineSeamTests {

    // ── (1) LanguagePair static properties and token ──────────────────────────

    @Test("LanguagePair.jaToEn carries correct codes, names, and token")
    func languagePairJaToEnProperties() {
        let p = LanguagePair.jaToEn
        #expect(p.sourceCode == "ja")
        #expect(p.sourceName == "Japanese")
        #expect(p.targetCode == "en")
        #expect(p.targetName == "English")
        #expect(p.token == "ja-en")
    }

    @Test("LanguagePair.enToJa carries correct codes, names, and token")
    func languagePairEnToJaProperties() {
        let p = LanguagePair.enToJa
        #expect(p.sourceCode == "en")
        #expect(p.sourceName == "English")
        #expect(p.targetCode == "ja")
        #expect(p.targetName == "Japanese")
        #expect(p.token == "en-ja")
    }

    /// M-invariance: the two static pairs must be distinct (token collision would silently
    /// mis-route translations).
    @Test("LanguagePair.jaToEn and .enToJa have distinct tokens")
    func languagePairTokensAreDistinct() {
        #expect(LanguagePair.jaToEn.token != LanguagePair.enToJa.token)
        #expect(LanguagePair.jaToEn != LanguagePair.enToJa)
    }

    // ── (2) Direction.pair boundary mapping ───────────────────────────────────

    @Test("Direction.jaToEn.pair maps to LanguagePair.jaToEn")
    func directionJaToEnPair() {
        #expect(Direction.jaToEn.pair == LanguagePair.jaToEn)
    }

    @Test("Direction.enToJa.pair maps to LanguagePair.enToJa")
    func directionEnToJaPair() {
        #expect(Direction.enToJa.pair == LanguagePair.enToJa)
    }

    // ── (3) FakeEngine via the new LanguagePair seam ──────────────────────────

    @Test("FakeEngine echoes [ja-en] <text> when called via the public LanguagePair seam")
    func fakeEngineEchoesViaLanguagePair() async throws {
        let engine = FakeEngine()
        try await engine.load()
        let result = try await engine.translate("こんにちは", .jaToEn)
        #expect(result == "[ja-en] こんにちは")
    }

    // ── (4) Stub engine load errors include the model path ────────────────────
    // RED: stubs throw .unavailable("STUB — implementation pending"); message does not
    // contain the path. Implementer must differentiate "not found at <path>" vs "not
    // implemented yet".

    @Test("MLXEngine.load on nonexistent modelDirectory throws .unavailable with path in message")
    func mlxLoadNonexistentDirMessageContainsPath() async {
        let path = "/nonexistent-mlx-\(UUID())"
        let engine = MLXEngine(modelDirectory: path)
        do {
            try await engine.load()
            Issue.record("expected TranslationEngineError.unavailable to be thrown")
        } catch TranslationEngineError.unavailable(let msg) {
            #expect(msg.contains(path), "error message must mention the model directory path")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("LlamaEngine.load on nonexistent modelPath throws .unavailable with path in message")
    func llamaLoadNonexistentPathMessageContainsPath() async {
        let path = "/nonexistent-llama-\(UUID()).gguf"
        let engine = LlamaEngine(modelPath: path)
        do {
            try await engine.load()
            Issue.record("expected TranslationEngineError.unavailable to be thrown")
        } catch TranslationEngineError.unavailable(let msg) {
            #expect(msg.contains(path), "error message must mention the model file path")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    // ── (5) translate before load throws .notLoaded on stub engines ───────────
    // RED: stubs throw .unavailable for everything; implementer must track load state and
    // throw .notLoaded when translate() is called before load() succeeds.

    @Test("MLXEngine.translate before load throws .notLoaded")
    func mlxTranslateBeforeLoadThrowsNotLoaded() async {
        let engine = MLXEngine(modelDirectory: "/nonexistent")
        await #expect(throws: TranslationEngineError.notLoaded) {
            _ = try await engine.translate("hi", .jaToEn)
        }
    }

    @Test("LlamaEngine.translate before load throws .notLoaded")
    func llamaTranslateBeforeLoadThrowsNotLoaded() async {
        let engine = LlamaEngine(modelPath: "/nonexistent.gguf")
        await #expect(throws: TranslationEngineError.notLoaded) {
            _ = try await engine.translate("hi", .jaToEn)
        }
    }

    // ── (6) CLI factory injection: .unavailable from factory → exit 3 + message ─
    // RED: stub `run(_:stdin:out:err:engineFactories:)` ignores the factory dict and
    // delegates to the base run, producing a different error message. Implementer must
    // wire the factory into engine selection and propagate the .unavailable message.

    @Test("--engine llama with factory returning .unavailable exits 3 with the engine message on stderr")
    func cliLlamaUnavailableViaFactoryExits3() async {
        let out = StringSink()
        let err = StringSink()
        let unavailableMsg = "model not found at /models/weights/file.gguf"
        let code = await CommandLineDriver().run(
            ["--dir", "ja-en", "--engine", "llama", "hi"],
            stdin: nil,
            out: out,
            err: err,
            engineFactories: [
                "llama": { _ in AlwaysUnavailableEngine(message: unavailableMsg) }
            ]
        )
        #expect(code == 3)
        #expect(err.buffer.contains(unavailableMsg),
                "stderr must contain the engine's .unavailable message")
    }

    // ── (7) Existing fake-engine path is unaffected by the seam refactor ──────

    @Test("--engine fake (default) still translates and exits 0 after seam refactor")
    func cliFakeEngineDefaultBehaviourUnchanged() async {
        let out = StringSink()
        let err = StringSink()
        let code = await CommandLineDriver().run(
            ["--dir", "ja-en", "--engine", "fake", "こんにちは"],
            stdin: nil,
            out: out,
            err: err
        )
        #expect(code == 0)
        #expect(out.buffer == "[ja-en] こんにちは\n")
    }
}
