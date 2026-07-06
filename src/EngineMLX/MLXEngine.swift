import Foundation
import MenubarTranslateCore

/// MLX / Apple-Silicon inference backend. Wave 0 stub — real weights and inference land in Wave 1.
///
/// Implements the public `TranslationEngine` seam so the engine target compiles and tests can
/// assert on the intended load/evict/translate contract without a live model.
///
/// STUB — implementation pending (Wave 1):
///   load()      → always throws .unavailable (path-check differentiates "not found" vs "not implemented")
///   translate() → always throws .unavailable (STUB — must be .notLoaded once real state tracked)
///   evict()     → no-op
public final class MLXEngine: TranslationEngine {
    private let modelDirectory: String
    private var isLoaded = false

    public init(modelDirectory: String) {
        self.modelDirectory = modelDirectory
    }

    public func load() async throws {
        // Wave 0 stub: differentiate "directory missing" from "not yet implemented" so callers
        // see a useful message. Real load (Wave 1) initialises MLX arrays on Metal.
        guard FileManager.default.fileExists(atPath: modelDirectory) else {
            throw TranslationEngineError.unavailable("model directory not found at \(modelDirectory)")
        }
        throw TranslationEngineError.unavailable("MLXEngine not implemented yet (Wave 1)")
    }

    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        // Wave 0 stub: load() always throws, so isLoaded never becomes true. Real translate
        // (Wave 1) guards residency the same way.
        guard isLoaded else { throw TranslationEngineError.notLoaded }
        throw TranslationEngineError.unavailable("MLXEngine not implemented yet (Wave 1)")
    }

    public func evict() async {
        // STUB — no-op; real evict releases the MLX array buffers while keeping the runtime alive.
    }
}
