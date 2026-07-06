/// Why a residency transition happened. Distinguishes user-driven loads from the several
/// eviction triggers so the `mbt` trace is legible and tests can assert on cause.
enum LifecycleReason: Sendable, Equatable {
    /// A load or inference driven by a translation request (the only cause of a load).
    case userIntent
    /// Eviction because the idle timeout elapsed with no use (ADR 0003).
    case idleTimeout
    /// Eviction because `warn` pressure persisted past the debounce and residency floor.
    case pressureWarn
    /// Immediate eviction under `critical` pressure, bypassing the floor (ADR 0004).
    case pressureCritical
    /// Deferred eviction performed after an in-flight inference finished (ADR 0006).
    case evictAfterUse
}

/// An observable snapshot emitted on every residency transition. `mbt` prints these; tests
/// assert on the sequence. Pure value type so it can cross any boundary.
struct ResidencyEvent: Sendable, Equatable {
    /// The lifecycle event that was applied.
    let event: LifecycleEvent
    /// The lifecycle state *after* applying `event`.
    let state: WeightState
    /// The pressure level in effect at the moment of transition (orthogonal domain).
    let pressure: PressureLevel
    /// Why the transition occurred.
    let reason: LifecycleReason
}
