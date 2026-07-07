/// Public facade that the future menu-bar app target uses to drive the residency /
/// translation stack. Internal types (ResidencyManager, TranslationService, Direction,
/// WeightState, PressureLevel, ResidencyConfig) stay internal; only the types below
/// cross the boundary.
///
/// **Caller contract**: AppRuntime is not Sendable. Confine it to one execution context
/// (the same actor or serial queue). The same contract ResidencyManager documents.
/// Do not annotate with @MainActor — the caller owns the context.

// MARK: - Public types

/// Selects the initial residency-timing preset (ADR 0003).
/// Maps to `ResidencyConfig.preset(for:)` internally.
public enum MemoryPreset: Sendable, Equatable {
    /// Eviction-eager preset for 8 GB unified memory (idleTimeout = 30 s).
    case conservative8GB
    /// Permissive preset for 16 GB+ (idleTimeout = 600 s, larger residency floor).
    case permissive16GB
}

/// A point-in-time view of the runtime state exposed to the app layer.
/// Mirrors the internal `WeightState` and `PressureLevel` enums at the public boundary.
public struct RuntimeSnapshot: Sendable, Equatable {
    /// Weight-lifecycle phase mirroring the internal `WeightState`.
    public enum Phase: String, Sendable {
        case unloaded, loading, ready, inferring, evicting
    }
    /// Memory-pressure band mirroring the internal `PressureLevel`.
    public enum Band: String, Sendable {
        case normal, warn, critical
    }

    public let phase: Phase
    public let pressure: Band

    public init(phase: Phase, pressure: Band) {
        self.phase = phase
        self.pressure = pressure
    }
}

// MARK: - Private: RuntimeSnapshot.Phase / Band mapping from internal types

private extension RuntimeSnapshot.Phase {
    init(_ state: WeightState) {
        switch state {
        case .unloaded: self = .unloaded
        case .loading: self = .loading
        case .ready: self = .ready
        case .inferring: self = .inferring
        case .evicting: self = .evicting
        }
    }
}

private extension RuntimeSnapshot.Band {
    init(_ level: PressureLevel) {
        switch level {
        case .normal: self = .normal
        case .warn: self = .warn
        case .critical: self = .critical
        }
    }
}

// MARK: - Private: pressure multiplexer

/// ponytail: PressureSource allows only one handler slot; this wrapper fans out to N so
/// both ResidencyManager and AppRuntime can observe changes without racing.
private final class PressureMultiplexer: PressureSource {
    private let base: any PressureSource
    private var handlers: [(PressureLevel) -> Void] = []

    var current: PressureLevel { base.current }

    init(_ base: any PressureSource) {
        self.base = base
        base.onChange { [weak self] level in
            self?.handlers.forEach { $0(level) }
        }
    }

    func onChange(_ handler: @escaping (PressureLevel) -> Void) {
        handlers.append(handler)
    }
}

// MARK: - AppRuntime

/// Public facade for the residency + translation stack.
///
/// Production wiring uses `SystemClock` + `DispatchPressureSource`.
/// Tests inject `ManualClock` + `FakePressureSource` via the internal seam init.
public final class AppRuntime {

    // MARK: Public interface

    /// Fired on every residency-state or pressure-level change.
    /// The closure receives the snapshot *after* the transition.
    public var onChange: ((RuntimeSnapshot) -> Void)?

    /// Current weight-lifecycle phase and pressure band.
    public var snapshot: RuntimeSnapshot {
        RuntimeSnapshot(
            phase: .init(residency.state),
            pressure: .init(pressureMultiplexer.current)
        )
    }

    // MARK: Private storage

    private let residency: ResidencyManager
    private let service: TranslationService
    private let pressureMultiplexer: PressureMultiplexer
    private let fallback: (any TranslationEngine)?
    private let fallbackAvailable: (() -> Bool)?

    // MARK: Production init

    /// Production wiring: SystemClock + DispatchPressureSource + full residency stack.
    public convenience init(
        engine: any TranslationEngine,
        preset: MemoryPreset,
        fallback: (any TranslationEngine)? = nil,
        fallbackAvailable: (() -> Bool)? = nil
    ) {
        self.init(
            engine: engine,
            preset: preset,
            fallback: fallback,
            fallbackAvailable: fallbackAvailable,
            clock: SystemClock(),
            pressureSource: DispatchPressureSource()
        )
    }

    // MARK: Test-seam init (internal)

    internal init(
        engine: any TranslationEngine,
        preset: MemoryPreset,
        fallback: (any TranslationEngine)? = nil,
        fallbackAvailable: (() -> Bool)? = nil,
        clock: Clock,
        pressureSource: PressureSource
    ) {
        let config = ResidencyConfig.preset(for: preset == .conservative8GB ? .ram8GB : .ram16GB)
        let multi = PressureMultiplexer(pressureSource)
        let mgr = ResidencyManager(config: config, clock: clock, pressureSource: multi)
        let svc = TranslationService(engine: engine, residency: mgr)

        self.residency = mgr
        self.service = svc
        self.pressureMultiplexer = multi
        self.fallback = fallback
        self.fallbackAvailable = fallbackAvailable

        // Chain residency.onEvent: service's handler (set by TranslationService.init) runs
        // first to keep internal accounting intact, then AppRuntime notifies onChange.
        let serviceHandler = mgr.onEvent
        mgr.onEvent = { [weak self] event in
            serviceHandler?(event)
            guard let self else { return }
            self.onChange?(self.snapshot)
        }

        // Wire pressure-level changes to onChange so band updates propagate.
        multi.onChange { [weak self] _ in
            guard let self else { return }
            self.onChange?(self.snapshot)
        }
    }

    // MARK: Public API

    /// Translate `text` for the given language pair.
    ///
    /// Routing (ADR 0006):
    /// - Critical pressure + fallbackAvailable?() == true + fallback != nil →
    ///   fallback path (OS Translation framework proxy); primary weights never loaded.
    /// - All other cases → `TranslationService` path with residency management.
    ///
    /// Supported pairs: "ja-en", "en-ja". Any other `pair.token` throws
    /// `TranslationEngineError.unavailable`.
    public func translate(_ text: String, _ pair: LanguagePair) async throws -> String {
        let direction: Direction
        switch pair.token {
        case "ja-en": direction = .jaToEn
        case "en-ja": direction = .enToJa
        default:
            throw TranslationEngineError.unavailable("unsupported language pair: \(pair.token)")
        }

        // ADR 0006 fallback routing: critical + gate open → bypass primary weights.
        if pressureMultiplexer.current == .critical,
           let check = fallbackAvailable, check(),
           let fb = fallback {
            try await fb.load() // idempotent; engines guard against double-load
            return try await fb.translate(text, pair)
        }

        return try await service.translate(text, direction).text
    }

    /// Advance time-based residency conditions (idle timeout, warn debounce) and drain
    /// any resulting eviction. The UI layer owns the repeating timer; this is the tick
    /// target. Never loads weights.
    public func tick() async {
        await service.tick()
    }
}
