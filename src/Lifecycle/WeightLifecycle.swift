/// Domain A — the weight-lifecycle state machine (ADR 0005).
///
/// `WeightState` and `LifecycleEvent` are generated from `models/core.als` (src/Core);
/// this file adds the executable transition guard. The legal-transition table below
/// mirrors the `LegalTransitions` fact in the model — the model is the source of truth.
/// This domain is deliberately **free of any memory-pressure concept** (ADR 0005).

/// Thrown when an event is applied in a state that has no legal transition for it.
struct IllegalTransition: Error, Equatable, CustomStringConvertible {
    let from: WeightState
    let event: LifecycleEvent

    var description: String {
        "IllegalTransition(from: \(from), event: \(event))"
    }
}

/// The weight-lifecycle state machine. A small, pure value type; the only mutation is
/// `apply(_:)`, which either advances the state or throws `IllegalTransition`.
struct WeightLifecycle: Sendable, Equatable {
    private(set) var state: WeightState

    init(state: WeightState = .unloaded) {
        self.state = state
    }

    /// The legal transition table (mirrors the model's `LegalTransitions` fact).
    ///
    /// Note there is no `inferring → evicting` edge: "evict-after-use" under Critical is
    /// modelled by the *policy* deferring `evictRequested` until after `inferFinished`
    /// returns the machine to `ready`, not by a mid-inference edge.
    private static func next(
        from state: WeightState,
        on event: LifecycleEvent
    ) -> WeightState? {
        switch (state, event) {
        case (.unloaded, .loadRequested): return .loading
        case (.loading, .loadCompleted): return .ready
        case (.loading, .loadFailed): return .unloaded
        case (.ready, .inferStarted): return .inferring
        case (.inferring, .inferFinished): return .ready
        case (.ready, .evictRequested): return .evicting
        case (.evicting, .evictCompleted): return .unloaded
        default: return nil
        }
    }

    /// Whether `event` is legal in the current state.
    func canApply(_ event: LifecycleEvent) -> Bool {
        Self.next(from: state, on: event) != nil
    }

    /// Apply `event`, advancing the state. Throws `IllegalTransition` if the event has no
    /// legal transition from the current state.
    @discardableResult
    mutating func apply(_ event: LifecycleEvent) throws -> WeightState {
        guard let next = Self.next(from: state, on: event) else {
            throw IllegalTransition(from: state, event: event)
        }
        state = next
        return state
    }
}
