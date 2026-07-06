/// Tunables for the residency policy (ADR 0003 / 0004).
///
/// RAM tier (`RamTier`, generated) is only an *initial preset* for these values
/// (ADR 0003); it is not itself an eviction trigger. The two hysteresis knobs —
/// `residencyFloor` and `warnDebounce` — are what make evict↔load oscillation
/// impossible together with the trigger asymmetry.
struct ResidencyConfig: Sendable, Equatable {
    /// Evict weights after this much time with no translation use (ADR 0003).
    var idleTimeout: Duration

    /// Minimum time weights stay resident after a load. A `warn` burst inside this window
    /// cannot evict (ADR 0004). `critical` bypasses this floor.
    var residencyFloor: Duration

    /// A `warn` level must persist at least this long before it can evict; transient
    /// `warn` blips are debounced away (ADR 0004).
    var warnDebounce: Duration

    init(
        idleTimeout: Duration,
        residencyFloor: Duration,
        warnDebounce: Duration
    ) {
        self.idleTimeout = idleTimeout
        self.residencyFloor = residencyFloor
        self.warnDebounce = warnDebounce
    }

    /// Initial preset for a RAM tier (ADR 0003: tier only picks the starting values).
    static func preset(for tier: RamTier) -> ResidencyConfig {
        switch tier {
        case .ram8GB: return .eightGigabyteDefault
        case .ram16GB: return .sixteenGigabytePermissive
        }
    }

    /// The 8 GB default preset: eviction-eager (ADR 0003 — 8 GB evicts by default).
    /// Values are placeholders pending the on-hardware measurements in `docs/validation.md`.
    static let eightGigabyteDefault = ResidencyConfig(
        idleTimeout: .seconds(30),
        residencyFloor: .seconds(5),
        warnDebounce: .seconds(2)
    )

    /// The 16 GB+ opt-in preset: a long but finite idle timeout (ADR 0003 discourages `∞`).
    static let sixteenGigabytePermissive = ResidencyConfig(
        idleTimeout: .seconds(600),
        residencyFloor: .seconds(30),
        warnDebounce: .seconds(3)
    )
}
