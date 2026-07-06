import Foundation
import MenubarTranslateCore

/// llama.cpp / Metal inference backend. Wave 0 stub — real weights and inference land in Wave 1.
///
/// Implements the public `TranslationEngine` seam so the engine target compiles and tests can
/// assert on the intended load/evict/translate contract without a live model.
///
/// STUB — implementation pending (Wave 1):
///   load()      → always throws .unavailable (path-check differentiates "not found" vs "not implemented")
///   translate() → always throws .unavailable (STUB — must be .notLoaded once real state tracked)
///   evict()     → no-op
public final class LlamaEngine: TranslationEngine {
    private let modelPath: String
    private var isLoaded = false

    public init(modelPath: String) {
        self.modelPath = modelPath
    }

    public func load() async throws {
        // Wave 0 stub: differentiate "file missing" from "not yet implemented" so callers
        // see a useful message. Real load (Wave 1) initialises llama_context.
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw TranslationEngineError.unavailable("model file not found at \(modelPath)")
        }
        throw TranslationEngineError.unavailable("LlamaEngine not implemented yet (Wave 1)")
    }

    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        // Wave 0 stub: load() always throws, so isLoaded never becomes true. Real translate
        // (Wave 1) guards residency the same way.
        guard isLoaded else { throw TranslationEngineError.notLoaded }
        throw TranslationEngineError.unavailable("LlamaEngine not implemented yet (Wave 1)")
    }

    public func evict() async {
        // STUB — no-op; real evict frees llama_context weights while keeping the runtime alive.
    }
}
