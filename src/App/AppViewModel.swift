/// M3 Wave C1 — observable view model in the core (pure Swift + Observation).
/// The SwiftUI menu-bar shell (next wave) binds to this; the core stays SwiftUI-free.

import Observation

/// User-facing translation direction. `pair` maps to the engine-seam `LanguagePair`.
public enum TranslationDirection: String, Sendable, CaseIterable {
    case jaToEn = "ja-en"
    case enToJa = "en-ja"

    /// The `LanguagePair` this direction selects (ja↔en).
    public var pair: LanguagePair {
        switch self {
        case .jaToEn: return .jaToEn
        case .enToJa: return .enToJa
        }
    }

    /// Flip ja→en ↔ en→ja in place.
    public mutating func toggle() {
        self = self == .jaToEn ? .enToJa : .jaToEn
    }
}

/// Observable view model owning an `AppRuntime`; the menu-bar shell binds to it.
@Observable
public final class AppViewModel {
    public private(set) var input: String = ""
    public private(set) var output: String = ""
    public private(set) var errorMessage: String?
    public private(set) var isBusy: Bool = false
    public var direction: TranslationDirection = .jaToEn
    public private(set) var snapshot: RuntimeSnapshot

    private let runtime: AppRuntime

    public init(runtime: AppRuntime) {
        self.runtime = runtime
        self.snapshot = runtime.snapshot
        runtime.onChange = { [weak self] snap in
            self?.snapshot = snap
        }
    }

    public func setInput(_ value: String) {
        input = value
    }

    public func translate() async {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isBusy = true
        do {
            let result = try await runtime.translate(input, direction.pair)
            output = result
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
        isBusy = false
    }

    public func tick() async {
        await runtime.tick()
    }
}
