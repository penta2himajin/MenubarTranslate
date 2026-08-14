/// M3 Wave C1 — observable view model in the core (pure Swift + Observation).
/// The SwiftUI menu-bar shell (next wave) binds to this; the core stays SwiftUI-free.

import Foundation
import Observation

/// User-facing translation direction. `pair` maps to the engine-seam `LanguagePair`.
public enum TranslationDirection: String, Sendable, CaseIterable, Hashable {
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

public struct TranslationHistoryItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: String
    public let output: String
    public let target: AppLanguage

    public init(id: UUID = UUID(), source: String, output: String, target: AppLanguage) {
        self.id = id
        self.source = source
        self.output = output
        self.target = target
    }
}

/// Observable view model owning an `AppRuntime`; the menu-bar shell binds to it.
/// `@MainActor` because SwiftUI reads this `@Observable` state on the main actor
/// while `translate()` mutates it. As a `nonisolated async` method its body ran on
/// the generic executor (SE-0338), so every write to `isBusy`/`output` landed off
/// the main actor — a real race that an `@unchecked Sendable` conformance in the
/// app target was suppressing. Isolating the class removes both the race and the
/// need for that conformance, since a `@MainActor` class is implicitly `Sendable`.
@Observable
@MainActor
public final class AppViewModel {
    public private(set) var input: String = ""
    public private(set) var output: String = ""
    public private(set) var errorMessage: String?
    public private(set) var isBusy: Bool = false
    public var direction: TranslationDirection = .jaToEn
    public var targetLanguage: AppLanguage = .en
    public private(set) var history: [TranslationHistoryItem] = []
    public private(set) var snapshot: RuntimeSnapshot

    private let runtime: AppRuntime
    private var liveTask: Task<Void, Never>?
    private var applyingHistory = false

    public init(runtime: AppRuntime) {
        self.runtime = runtime
        self.snapshot = runtime.snapshot
        print("status \(statusLine)")
        runtime.onChange = { [weak self] snap in
            guard let self, self.snapshot != snap else { return }
            self.snapshot = snap
            print("status \(self.statusLine)")
        }
        let picker = AppLanguage.pickerLanguages()
        if let first = picker.first(where: { $0 != .ja }) ?? picker.first {
            targetLanguage = first
        }
    }

    public var directionLabel: String {
        direction == .jaToEn ? "JA → EN" : "EN → JA"
    }

    public var statusLine: String {
        "\(snapshot.phase.rawValue) · \(snapshot.pressure.rawValue)"
    }

    /// Shown on the Translate control while a run is in flight. Nil when idle.
    public var progressCaption: String? {
        guard isBusy else { return nil }
        switch snapshot.phase {
        case .loading: return "Loading model…"
        case .inferring: return "Translating…"
        default: return "Working…"
        }
    }

    public func canSubmit(_ draft: String) -> Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func setInput(_ value: String) {
        input = value
    }

    public func translate(draft: String) async {
        setInput(draft)
        await translate()
    }

    /// Live path: detect source from `draft`, translate into `targetLanguage`.
    public func translateLive(draft: String) async {
        setInput(draft)
        guard !isBusy else { return }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let source = AppLanguage.detect(draft) else { return }
        if source == targetLanguage {
            output = draft
            errorMessage = nil
            recordHistory(source: draft, output: draft)
            return
        }
        await translate(pair: LanguagePair.named(source: source, target: targetLanguage))
    }

    public func scheduleLiveTranslate(_ draft: String) {
        if applyingHistory {
            applyingHistory = false
            setInput(draft)
            return
        }
        setInput(draft)
        liveTask?.cancel()
        liveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            await self.translateLive(draft: draft)
        }
    }

    public func applyHistory(_ item: TranslationHistoryItem) {
        liveTask?.cancel()
        applyingHistory = true
        targetLanguage = item.target
        input = item.source
        output = item.output
        errorMessage = nil
    }

    public func translate() async {
        await translate(pair: direction.pair)
    }

    private func translate(pair: LanguagePair) async {
        guard !isBusy else { return }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isBusy = true
        errorMessage = nil
        do {
            let result = try await runtime.translate(input, pair)
            output = result
            recordHistory(source: input, output: result)
        } catch {
            errorMessage = String(describing: error)
        }
        isBusy = false
    }

    private func recordHistory(source: String, output: String) {
        let item = TranslationHistoryItem(source: source, output: output, target: targetLanguage)
        if history.first?.source == source, history.first?.target == targetLanguage {
            history[0] = item
            return
        }
        history.insert(item, at: 0)
        if history.count > 20 { history.removeLast() }
    }

    public func tick() async {
        await runtime.tick()
    }
}
