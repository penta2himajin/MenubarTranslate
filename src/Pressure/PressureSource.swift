/// Domain B — memory pressure (ADR 0005). `PressureLevel` is generated from the model;
/// this file adds ordering and the injectable source seam.

// Ordered severity: normal < warn < critical.
extension PressureLevel: Comparable {
    private var rank: Int {
        switch self {
        case .normal: return 0
        case .warn: return 1
        case .critical: return 2
        }
    }

    static func < (lhs: PressureLevel, rhs: PressureLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// A source of memory-pressure transitions.
///
/// The residency policy depends only on this protocol, never on `DispatchSource`
/// directly, so tests drive pressure deterministically via `FakePressureSource`.
protocol PressureSource: AnyObject {
    /// The most recently observed pressure level.
    var current: PressureLevel { get }

    /// Register a handler invoked on every pressure change. Called synchronously by the
    /// fake; on the real source it is delivered on the source's dispatch queue.
    func onChange(_ handler: @escaping (PressureLevel) -> Void)
}

/// Test double: a pressure source whose level is driven explicitly by `emit(_:)`,
/// invoking the registered handler synchronously so state-machine tests are deterministic.
final class FakePressureSource: PressureSource {
    private(set) var current: PressureLevel
    private var handler: ((PressureLevel) -> Void)?

    init(initial: PressureLevel = .normal) {
        self.current = initial
    }

    func onChange(_ handler: @escaping (PressureLevel) -> Void) {
        self.handler = handler
    }

    /// Drive a pressure transition. The handler fires synchronously with the new level.
    func emit(_ level: PressureLevel) {
        current = level
        handler?(level)
    }
}
