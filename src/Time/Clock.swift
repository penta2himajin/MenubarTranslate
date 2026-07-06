import Dispatch

/// A monotonic instant, measured in nanoseconds from an arbitrary origin. Comparable and
/// subtractable so residency math (idle timeout, residency floor, warn debounce) is total
/// and unaffected by wall-clock jumps.
struct Instant: Sendable, Comparable, Hashable {
    let nanos: UInt64

    init(nanos: UInt64) {
        self.nanos = nanos
    }

    static func < (lhs: Instant, rhs: Instant) -> Bool {
        lhs.nanos < rhs.nanos
    }

    /// Non-negative elapsed duration since an earlier instant. Clamps at zero if `earlier`
    /// is actually later (monotonic sources should never regress, but be total anyway).
    func elapsed(since earlier: Instant) -> Duration {
        guard nanos >= earlier.nanos else { return .zero }
        return .nanoseconds(Int64(nanos - earlier.nanos))
    }
}

/// An injectable time source. Production uses `SystemClock` (monotonic uptime); tests use
/// `ManualClock` so time only advances when the test says so.
protocol Clock: AnyObject {
    var now: Instant { get }
}

/// Monotonic clock backed by `DispatchTime.uptimeNanoseconds` — deliberately *not*
/// wall-clock `Date`, so NTP steps cannot corrupt residency timing.
final class SystemClock: Clock {
    init() {}

    var now: Instant {
        Instant(nanos: DispatchTime.now().uptimeNanoseconds)
    }
}

/// Deterministic clock for tests. Time is frozen until `advance(by:)` is called.
final class ManualClock: Clock {
    private(set) var now: Instant

    init(start: Instant = Instant(nanos: 0)) {
        self.now = start
    }

    /// Advance the clock by a non-negative duration.
    func advance(by duration: Duration) {
        let ns = duration.wholeNanoseconds
        precondition(ns >= 0, "ManualClock cannot move backwards")
        now = Instant(nanos: now.nanos &+ UInt64(ns))
    }
}

extension Duration {
    /// The whole-nanosecond magnitude of this duration.
    var wholeNanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }
}
