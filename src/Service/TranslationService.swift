/// The outcome of a translation: the output plus the residency transition trace produced
/// while serving it (so `mbt -v` and tests can observe the lifecycle). Named to avoid
/// colliding with the model-generated `TranslationResult` (request/output/backend).
struct TranslationOutcome: Sendable, Equatable {
    let text: String
    let trace: [ResidencyEvent]
}

/// Orchestrates an async `TranslationEngine` against the synchronous `ResidencyManager`.
///
/// A `translate(_:_:)` call **is** the user intent (ADR 0004): it is the only thing that
/// drives a load. The service performs the async engine effects and reports each step back
/// to the policy core, then drains any eviction the policy requested (evict-after-use under
/// `critical`, ADR 0006; or a standing idle/pressure eviction). Warm reuse within the floor
/// finds the weights `ready` and skips the load.
///
/// Note: this coordinator is confined to a single execution context (its caller). The real
/// menu-bar runtime wires the timer `tick()` and the dispatch pressure callback onto that
/// same context; that adapter ships with the engine/UI milestone.
final class TranslationService {
    private let engine: TranslationEngine
    private let residency: ResidencyManager
    private let networkGuard: NetworkGuard

    /// Set by the policy core when it decides to release weights; drained asynchronously.
    private var evictionPending = false
    /// Append-only transition log; a per-call slice becomes `TranslationOutcome.trace`.
    private var events: [ResidencyEvent] = []

    init(
        engine: TranslationEngine,
        residency: ResidencyManager,
        networkGuard: NetworkGuard = NetworkGuard()
    ) {
        self.engine = engine
        self.residency = residency
        self.networkGuard = networkGuard
        residency.onEvent = { [weak self] event in self?.events.append(event) }
        residency.onEvict = { [weak self] in self?.evictionPending = true }
    }

    /// Translate `text` in `direction`. Loads on demand (user intent), infers, records use,
    /// and drains any policy-requested eviction before returning. Never touches the network.
    func translate(_ text: String, _ direction: Direction) async throws -> TranslationOutcome {
        let start = events.count

        if residency.needsLoad {
            try residency.beginLoad()
            do {
                try await engine.load()
            } catch {
                try? residency.failLoad()
                throw error
            }
            try residency.completeLoad()
        }

        try residency.beginInference()
        let output = try await engine.translate(text, direction)
        try residency.endInference()

        await drainEviction()

        return TranslationOutcome(text: output, trace: Array(events[start...]))
    }

    /// Advance time-based residency conditions and perform any resulting eviction. The
    /// real runtime calls this from a repeating timer; never loads.
    func tick() async {
        residency.tick()
        await drainEviction()
    }

    /// Perform every eviction the policy has requested. Each drains `ready`→`evicting`→
    /// `unloaded`, releasing weights via the engine while keeping runtime init alive.
    private func drainEviction() async {
        while evictionPending {
            evictionPending = false
            await engine.evict()
            residency.completeEviction()
        }
    }
}
