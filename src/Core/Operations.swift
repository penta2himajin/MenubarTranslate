import Foundation

/// Operation: canEvict
/// - post: r.weight = Ready or r.weight = Inferring
func canEvict(_ r: Runtime) {
    fatalError("oxidtr: implement canEvict")
}

/// Operation: fallbackAvailable
/// - post: g.apiPresent = Yes and g.jaEnSupported = Yes and g.modelDownloaded = Yes
func fallbackAvailable(_ g: CapabilityGate) {
    fatalError("oxidtr: implement fallbackAvailable")
}

/// Operation: activeBackend
/// - pre: r.backend
func activeBackend(_ r: Runtime) -> Backend {
    fatalError("oxidtr: implement activeBackend")
}

