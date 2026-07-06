/// A deterministic in-memory engine for tests and the default `mbt --engine fake` path.
///
/// It performs no I/O and no real inference, so it fully exercises the residency state
/// machine and the CLI without any model, GPU, or network. It records call order and
/// enforces the load-before-translate contract.
final class FakeEngine: TranslationEngine {
    /// One recorded interaction, in order.
    enum Call: Equatable {
        case load
        case translate(String, Direction)
        case evict
    }

    private(set) var calls: [Call] = []
    private(set) var isLoaded = false

    /// Produces the translated string. Default echoes the direction and input so output is
    /// observable and deterministic; override to script specific outputs in a test.
    private let transform: (String, Direction) -> String

    init(transform: @escaping (String, Direction) -> String = FakeEngine.echo) {
        self.transform = transform
    }

    /// Default deterministic transform: `"[ja-en] こんにちは"`.
    static func echo(_ text: String, _ direction: Direction) -> String {
        "[\(direction.token)] \(text)"
    }

    func load() async throws {
        calls.append(.load)
        isLoaded = true
    }

    func translate(_ text: String, _ direction: Direction) async throws -> String {
        guard isLoaded else { throw TranslationEngineError.notLoaded }
        calls.append(.translate(text, direction))
        return transform(text, direction)
    }

    func evict() async {
        calls.append(.evict)
        isLoaded = false
    }
}
