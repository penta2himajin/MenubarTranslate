/// A deterministic in-memory engine for tests and the default `mbt --engine fake` path.
///
/// It performs no I/O and no real inference, so it fully exercises the residency state
/// machine and the CLI without any model, GPU, or network. It records call order and
/// enforces the load-before-translate contract.
// ponytail: `@unchecked` because the recorded `calls`/`isLoaded` are mutable. The
// fake is only ever driven serially — by one test, or by the CLI's single request —
// so the storage is unshared in practice; making it an actor would force `await` on
// the assertions that read `calls` and buy nothing.
final class FakeEngine: TranslationEngine, @unchecked Sendable {
    /// One recorded interaction, in order.
    enum Call: Equatable {
        case load
        case translate(String, LanguagePair)
        case evict
    }

    private(set) var calls: [Call] = []
    private(set) var isLoaded = false

    /// Produces the translated string. Default echoes the pair token and input so output is
    /// observable and deterministic; override to script specific outputs in a test.
    private let transform: (String, LanguagePair) -> String

    init(transform: @escaping (String, LanguagePair) -> String = FakeEngine.echo) {
        self.transform = transform
    }

    /// Default deterministic transform: `"[ja-en] こんにちは"`.
    static func echo(_ text: String, _ pair: LanguagePair) -> String {
        "[\(pair.token)] \(text)"
    }

    func load() async throws {
        calls.append(.load)
        isLoaded = true
    }

    func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        guard isLoaded else { throw TranslationEngineError.notLoaded }
        calls.append(.translate(text, pair))
        return transform(text, pair)
    }

    func evict() async {
        calls.append(.evict)
        isLoaded = false
    }
}
