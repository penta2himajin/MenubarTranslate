import AppKit

/// Accessory apps (LSUIElement) have no Dock icon. Clicking the .app in Finder
/// while a copy is already running looks like a failed launch unless we hand off
/// to the existing process instead of starting a second Metal/llama runtime.
enum LaunchGuard {
    static func claimOrHandoff() {
        guard let id = Bundle.main.bundleIdentifier, !id.isEmpty else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != getpid() }
        guard let other = others.first else { return }
        FileHandle.standardError.write(
            Data("already running pid=\(other.processIdentifier); activating and exiting\n".utf8)
        )
        other.activate()
        exit(0)
    }
}
