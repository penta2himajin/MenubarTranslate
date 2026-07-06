/// The seam between the residency policy and an actual inference backend.
///
/// Weight-level residency (ADR 0002): `load()` and `evict()` move only the model weights;
/// the process and any runtime/Metal/MLX initialisation stay alive across the cycle so a
/// reload is cheap. Concrete engines (`LlamaEngine`, `MLXEngine`) live in their own targets
/// and are added in the engine PR; the core depends only on this protocol.
protocol TranslationEngine: AnyObject {
    /// Make the weights resident. Cheap to repeat after an `evict()` because runtime init is
    /// retained (ADR 0002 — target ≈0.5 s cold reload).
    func load() async throws

    /// Translate `text` in `direction`. Must be called only while loaded.
    func translate(_ text: String, _ direction: Direction) async throws -> String

    /// Release the weights (but not the runtime). Idempotent.
    func evict() async
}

/// Errors an engine may raise on the translation path.
enum TranslationEngineError: Error, Equatable {
    /// `translate` was called before `load`.
    case notLoaded
    /// The engine is not available in this build/configuration (e.g. the native engine
    /// targets are excluded, or required weights are missing).
    case unavailable(String)
}
