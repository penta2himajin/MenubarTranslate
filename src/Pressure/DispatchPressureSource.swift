#if canImport(Darwin)
import Dispatch

/// The real memory-pressure source, backed by `DISPATCH_SOURCE_TYPE_MEMORYPRESSURE`
/// (ADR 0003). Darwin-only.
///
/// The flag→level translation is factored out as a pure function so it is unit-testable
/// without a live source (see `pressureLevel(from:)`).
final class DispatchPressureSource: PressureSource {
    private(set) var current: PressureLevel = .normal
    private var handler: ((PressureLevel) -> Void)?
    private let source: DispatchSourceMemoryPressure

    init(queue: DispatchQueue = .main) {
        source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let level = pressureLevel(from: self.source.data)
            self.current = level
            self.handler?(level)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    func onChange(_ handler: @escaping (PressureLevel) -> Void) {
        self.handler = handler
    }
}

/// Pure mapping from a `DispatchSource` memory-pressure event mask to a `PressureLevel`.
/// Highest severity present wins (critical > warning > normal). Extracted so it can be
/// tested without an actual dispatch source.
func pressureLevel(from flags: DispatchSource.MemoryPressureEvent) -> PressureLevel {
    if flags.contains(.critical) { return .critical }
    if flags.contains(.warning) { return .warn }
    return .normal
}
#endif
