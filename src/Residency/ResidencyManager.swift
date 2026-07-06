/// The residency policy — the intellectual core of the app (ADR 0003 / 0004 / 0005 / 0006).
///
/// This type is **pure and synchronous**: it owns the weight-lifecycle state (Domain A) and
/// the timing bookkeeping, and it *decides* when to evict. It never performs I/O itself and
/// never awaits — real engine load/evict is executed by the caller (`TranslationService`),
/// which drives the guarded transition methods and wires the `onEvict` effect. Time only
/// advances through the injected `Clock`; pressure only changes through the injected
/// `PressureSource`. That is what makes the thrash tests deterministic.
///
/// Invariants enforced here:
///   * **Loading is user-intent only** (ADR 0004). The *only* method that begins a load is
///     `beginLoad()`, called from the translate path. No pressure/tick path can load.
///   * **Eviction reacts to pressure ∨ idle timeout** (ADR 0003/0004), gated by double
///     hysteresis (residency floor + warn debounce), with `critical` bypassing the floor
///     and deferring to after any in-flight inference (evict-after-use, ADR 0006).
///   * **Pressure is orthogonal** (ADR 0005): it is stored separately and only *modulates*
///     lifecycle transitions; it is never a lifecycle state.
final class ResidencyManager {
    private(set) var config: ResidencyConfig
    private let clock: Clock
    private let pressureSource: PressureSource

    private var lifecycle = WeightLifecycle()

    // Timing bookkeeping.
    private var lastLoadAt: Instant?
    private var lastUseAt: Instant?
    private var warnSince: Instant?

    // Deferred-eviction flag: set when `critical` arrives while not `ready` (loading /
    // inferring), so eviction happens once the weights are free to release.
    private var pendingEvict = false

    /// Current memory-pressure level (Domain B). Read from the source, kept orthogonal.
    private(set) var pressure: PressureLevel

    /// Effect hook: invoked when the policy decides to release weights. The caller performs
    /// the async `engine.evict()` and must call `completeEviction()` when done. In tests a
    /// spy records/decides completion, keeping everything synchronous.
    var onEvict: () -> Void = {}

    /// Observer for the transition trace. `mbt` prints these; tests assert on them.
    var onEvent: ((ResidencyEvent) -> Void)?

    init(
        config: ResidencyConfig,
        clock: Clock,
        pressureSource: PressureSource
    ) {
        self.config = config
        self.clock = clock
        self.pressureSource = pressureSource
        self.pressure = pressureSource.current
        pressureSource.onChange { [weak self] level in
            self?.pressureChanged(level)
        }
    }

    /// The current lifecycle state (Domain A). Read-only to the outside.
    var state: WeightState { lifecycle.state }

    // MARK: - User-intent transitions (the only path that loads)

    /// True if a load must be started for a translation to proceed (i.e. weights are not
    /// resident). The translate path calls this; nothing else does.
    var needsLoad: Bool { lifecycle.state == .unloaded }

    /// Begin a user-intent load. Legal only from `unloaded`. This is the sole loading path
    /// (ADR 0004 asymmetry).
    func beginLoad() throws {
        try emit(.loadRequested, reason: .userIntent)
    }

    /// Report that the load finished; weights are now resident. Starts the residency floor.
    func completeLoad() throws {
        try emit(.loadCompleted, reason: .userIntent)
        lastLoadAt = clock.now
    }

    /// Report that the load failed; return to `unloaded`.
    func failLoad() throws {
        try emit(.loadFailed, reason: .userIntent)
    }

    /// Begin an inference. Legal only from `ready`.
    func beginInference() throws {
        try emit(.inferStarted, reason: .userIntent)
    }

    /// Finish an inference. Records use (resets the idle timer) and, if a `critical`-driven
    /// eviction was deferred, performs it now (evict-after-use, ADR 0006). Otherwise
    /// re-evaluates the standing eviction conditions.
    func endInference() throws {
        try emit(.inferFinished, reason: .userIntent)
        lastUseAt = clock.now
        if pendingEvict {
            pendingEvict = false
            evict(reason: .evictAfterUse)
        } else {
            evaluateEviction()
        }
    }

    // MARK: - Autonomous eviction inputs (never load)

    /// Advance time-based conditions (idle timeout, warn debounce, residency floor). Driven
    /// by a real repeating timer in production; called explicitly after `clock.advance` in
    /// tests. Never loads.
    func tick() {
        evaluateEviction()
    }

    /// Handle a pressure transition. Updates the orthogonal pressure level and its
    /// bookkeeping, may schedule/perform eviction, and **never** loads (ADR 0004).
    private func pressureChanged(_ level: PressureLevel) {
        pressure = level

        switch level {
        case .normal:
            warnSince = nil
        case .warn:
            if warnSince == nil { warnSince = clock.now }
        case .critical:
            warnSince = nil
            // If weights are busy (loading/inferring), defer; the floor is always bypassed
            // for critical, but we cannot release weights mid-flight.
            if lifecycle.state == .loading || lifecycle.state == .inferring {
                pendingEvict = true
            }
        }

        evaluateEviction()
    }

    // MARK: - Eviction decision (priority: critical > warn > idle)

    private func evaluateEviction() {
        // Only `ready` weights can be released. Busy states are handled via `pendingEvict`
        // (set on critical) and revisited at `endInference`.
        guard lifecycle.state == .ready else { return }
        let now = clock.now

        // Critical: evict immediately, bypassing the residency floor (ADR 0003/0004).
        if pressure == .critical {
            evict(reason: .pressureCritical)
            return
        }

        // Warn: double hysteresis — must persist past the debounce AND the residency floor
        // must have elapsed since load (ADR 0004).
        if pressure == .warn,
           let warnSince,
           now.elapsed(since: warnSince) >= config.warnDebounce,
           let lastLoadAt,
           now.elapsed(since: lastLoadAt) >= config.residencyFloor {
            evict(reason: .pressureWarn)
            return
        }

        // Idle: evict after the idle timeout with no activity (ADR 0003). Applies under
        // normal pressure too. "Activity" is the last use, or — for a loaded-but-never-used
        // model — the load itself.
        if let idleReference = lastUseAt ?? lastLoadAt,
           now.elapsed(since: idleReference) >= config.idleTimeout {
            evict(reason: .idleTimeout)
            return
        }
    }

    /// Transition `ready → evicting` and fire the evict effect. The caller performs the
    /// async release and calls `completeEviction()`.
    private func evict(reason: LifecycleReason) {
        do {
            try emit(.evictRequested, reason: reason)
        } catch {
            // `evict` is only ever called from `ready`, so this is unreachable; swallow to
            // keep the autonomous path non-throwing.
            return
        }
        lastEvictReason = reason
        onEvict()
    }

    private var lastEvictReason: LifecycleReason = .idleTimeout

    /// Report that the async eviction finished; weights are released.
    func completeEviction() {
        // Non-throwing convenience: `completeEviction` is only valid from `evicting`.
        _ = try? emit(.evictCompleted, reason: lastEvictReason)
    }

    // MARK: - Transition helper

    @discardableResult
    private func emit(_ event: LifecycleEvent, reason: LifecycleReason) throws -> WeightState {
        let newState = try lifecycle.apply(event)
        onEvent?(ResidencyEvent(event: event, state: newState, pressure: pressure, reason: reason))
        return newState
    }
}
