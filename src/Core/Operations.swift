import Foundation

/// Operation: canEvict
/// - post: r.weight = Ready or r.weight = Inferring
func canEvict(_ r: Runtime) -> Bool {
    r.weight == .ready || r.weight == .inferring
}

/// Operation: fallbackAvailable
/// - post: g.apiPresent = Yes and g.jaEnSupported = Yes and g.modelDownloaded = Yes
func fallbackAvailable(_ g: CapabilityGate) -> Bool {
    g.apiPresent == .yes && g.jaEnSupported == .yes && g.modelDownloaded == .yes
}

/// Operation: activeBackend
/// - pre: r.backend
func activeBackend(_ r: Runtime) -> Backend {
    r.backend
}

