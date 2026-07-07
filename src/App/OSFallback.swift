/// OS Translation-framework fallback seam (ADR 0006), pure Swift.
///
/// This file carries NO `import Translation`: the actual OS APIs are driven from the
/// SwiftUI app layer via `.translationTask` and injected here as closures, so the core
/// stays platform-agnostic and testable. The three-layer capability gate is the single
/// source of truth in `models/core.als`; `FallbackCapability.isAvailable` delegates to
/// the generated `fallbackAvailable(CapabilityGate)` rather than reimplementing the AND.

/// The three-layer availability gate for the OS Translation-framework fallback (ADR 0006):
/// API present ∧ ja↔en pair supported ∧ OS model already downloaded.
public struct FallbackCapability: Sendable, Equatable {
    public let apiPresent: Bool
    public let pairSupported: Bool
    public let modelDownloaded: Bool

    public init(apiPresent: Bool, pairSupported: Bool, modelDownloaded: Bool) {
        self.apiPresent = apiPresent
        self.pairSupported = pairSupported
        self.modelDownloaded = modelDownloaded
    }

    /// True only when all three layers hold. Delegates to the generated core operation.
    public var isAvailable: Bool {
        // ponytail: construct CapabilityGate (jaEnSupported maps from pairSupported) and
        // delegate — do not reimplement the && chain (source of truth is models/core.als).
        fallbackAvailable(CapabilityGate(
            apiPresent: apiPresent ? .yes : .no,
            jaEnSupported: pairSupported ? .yes : .no,
            modelDownloaded: modelDownloaded ? .yes : .no
        ))
    }
}

/// Adapter so the OS Translation framework can plug into `AppRuntime`'s fallback slot.
/// It owns no weights and no residency (ADR 0006 fallback has none).
public final class OSTranslationEngine: TranslationEngine {
    private let availability: @Sendable () -> FallbackCapability
    private let translator: @Sendable (String, LanguagePair) async throws -> String

    public init(
        availability: @escaping @Sendable () -> FallbackCapability,
        translator: @escaping @Sendable (String, LanguagePair) async throws -> String
    ) {
        self.availability = availability
        self.translator = translator
    }

    public func load() async throws {
        guard availability().isAvailable else {
            throw TranslationEngineError.unavailable("OS Translation framework unavailable: capability gate closed")
        }
    }

    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        guard availability().isAvailable else {
            throw TranslationEngineError.unavailable("OS Translation framework unavailable: capability gate closed")
        }
        return try await translator(text, pair)
    }

    public func evict() async {} // no-op — no residency
}
