/// Enforces the local-only invariant (AGENTS.md prohibition #1): nothing on the translation
/// path may make a network call.
///
/// The translate path is handed a `NetworkGuard`; any attempt to route traffic through it
/// trips the guard. The default is `deny`, and a test asserts the guard is *never* invoked
/// on the translate path. This turns a hoped-for invariant into a checked property, and
/// gives a single choke point if a future engine ever needs a genuinely-local socket.
final class NetworkGuard {
    enum Policy: Sendable, Equatable {
        /// Any network use is a programming error (default; the translation path).
        case deny
    }

    let policy: Policy
    private(set) var wasContacted = false

    init(policy: Policy = .deny) {
        self.policy = policy
    }

    /// Called if any code on the translation path attempts network access. Under `.deny`
    /// this is a fatal invariant violation.
    func attemptNetworkAccess(_ description: String) {
        wasContacted = true
        switch policy {
        case .deny:
            fatalError("local-only invariant violated: network access attempted (\(description))")
        }
    }
}
