/// The public language-pair type used across the engine seam. Keeps the generated
/// `Direction` enum internal; callers in separate targets reference only `LanguagePair`.
public struct LanguagePair: Sendable, Equatable {
    public let sourceCode: String   // e.g. "ja"
    public let sourceName: String   // e.g. "Japanese"
    public let targetCode: String   // e.g. "en"
    public let targetName: String   // e.g. "English"

    /// The canonical CLI/token string, e.g. "ja-en".
    public var token: String { "\(sourceCode)-\(targetCode)" }

    public init(
        sourceCode: String, sourceName: String,
        targetCode: String, targetName: String
    ) {
        self.sourceCode = sourceCode; self.sourceName = sourceName
        self.targetCode = targetCode; self.targetName = targetName
    }

    public static let jaToEn = LanguagePair(
        sourceCode: "ja", sourceName: "Japanese",
        targetCode: "en", targetName: "English"
    )
    public static let enToJa = LanguagePair(
        sourceCode: "en", sourceName: "English",
        targetCode: "ja", targetName: "Japanese"
    )
}

/// The seam between the residency policy and an actual inference backend.
///
/// Weight-level residency (ADR 0002): `load()` and `evict()` move only the model weights;
/// the process and any runtime/Metal/MLX initialisation stay alive across the cycle so a
/// reload is cheap. Concrete engines (`LlamaEngine`, `MLXEngine`) live in their own targets
/// and are added in the engine PR; the core depends only on this protocol.
public protocol TranslationEngine: AnyObject {
    /// Make the weights resident. Cheap to repeat after an `evict()` because runtime init is
    /// retained (ADR 0002 — target ≈0.5 s cold reload).
    func load() async throws

    /// Translate `text` for the given language pair. Must be called only while loaded.
    func translate(_ text: String, _ pair: LanguagePair) async throws -> String

    /// Release the weights (but not the runtime). Idempotent.
    func evict() async
}

/// Errors an engine may raise on the translation path.
public enum TranslationEngineError: Error, Equatable {
    /// `translate` was called before `load`.
    case notLoaded
    /// The engine is not available in this build/configuration (e.g. the native engine
    /// targets are excluded, or required weights are missing).
    case unavailable(String)
}
