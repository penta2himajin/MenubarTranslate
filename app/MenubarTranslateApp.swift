// app/MenubarTranslateApp.swift
// M3 Wave C2 — SwiftUI menu-bar app shell.
//
// SwiftUI and Translation-framework code lives here; src/ stays SwiftUI-free per the
// ADR 0006 seam: the core exposes OSTranslationEngine with closure slots, and this
// file owns the OS APIs and fills them.

import AppKit
import Darwin
import Synchronization
import SwiftUI
import Translation
import MenubarTranslateCore
import MenubarTranslateUI
import MTEngineLlama

// MARK: - Shared state crossing the OSTranslationEngine seam

/// Mutable capability state feeding the ADR 0006 gate.
///
/// This genuinely crosses isolation: it is written on the main actor (`probeCapability`)
/// and read from `OSTranslationEngine`'s `availability` closure, which is a *synchronous*
/// `@Sendable` closure invoked from `load()`/`translate()` — both non-isolated `async`,
/// so they run on the cooperative pool, not the main actor. A synchronous closure cannot
/// hop actors, so the state needs real mutual exclusion rather than an assumption.
final class CapabilityHolder: Sendable {
    private struct State {
        var capability = FallbackCapability(
            apiPresent: false, pairSupported: false, modelDownloaded: false
        )
        /// Guards the one-shot prepareTranslation() call from the translationTask closure.
        var didPrepare = false
    }

    private let state = Mutex(State())

    var value: FallbackCapability {
        get { state.withLock { $0.capability } }
        set { state.withLock { $0.capability = newValue } }
    }

    /// Claim the one-shot prepare slot. Returns true exactly once per launch.
    func claimPrepare() -> Bool {
        state.withLock {
            if $0.didPrepare { return false }
            $0.didPrepare = true
            return true
        }
    }
}

/// Directional Translation-framework sessions, valid only while the respective
/// `.translationTask` closure is alive.
///
/// `@MainActor` (hence implicitly Sendable): `TranslationSession` is not Sendable and
/// Apple does not document it as safe off the main actor, so sessions never leave it —
/// the translator closure hops here via `translateOnMainActor` instead of carrying the
/// session across. This is what removes the `@retroactive Sendable` conformance that
/// previously papered over the same crossing.
@MainActor
final class SessionBox {
    var jaEnSession: TranslationSession?
    var enJaSession: TranslationSession?
}

/// `TranslationSession` is non-Sendable, yet its `translate`/`prepareTranslation` are
/// nonisolated `async` — so the framework itself requires the session to leave the
/// caller's actor, and there is no Sendable-clean way to call it.
///
/// This box is the one place that crossing is admitted. It replaces a blanket
/// `extension TranslationSession: @unchecked @retroactive Sendable`, which blessed
/// *every* use of the SDK type and would hard-break the build if Apple ever added its
/// own conformance. Scoping it to a wrapper keeps the unsafety visible and local.
///
/// ponytail: `@unchecked` forced by the SDK's API shape; delete it if `TranslationSession`
/// ever becomes Sendable.
private struct SendableSession: @unchecked Sendable {
    let session: TranslationSession
}

/// Look the session up on the main actor (where it is stored), then call it.
@MainActor
private func translateOnMainActor(
    _ text: String, _ pair: LanguagePair, box: SessionBox
) async throws -> String {
    let stored = pair.sourceCode == "ja" ? box.jaEnSession : box.enJaSession
    guard let stored else {
        throw TranslationEngineError.unavailable(
            "OS Translation session not ready (pair: \(pair.token))")
    }
    return try await SendableSession(session: stored).session.translate(text).targetText
}

// MARK: - App state (translation stack)

/// Owns the entire translation stack so it survives App struct rebuilds via @State.
/// `@MainActor` — it holds `AppViewModel` (non-Sendable, UI-bound) and `SessionBox`.
@MainActor
final class AppState {
    let vm: AppViewModel
    let sessionBox: SessionBox
    let capHolder: CapabilityHolder

    /// Mirrors mbt/main.swift engine-factory logic exactly (env vars, default paths).
    init() {
        let box = SessionBox()
        let cap = CapabilityHolder()
        self.sessionBox = box
        self.capHolder = cap

        // Resolve the model path from environment; mirrors mbt/main.swift.
        let llamaPath = ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"]
            ?? "models/weights/gemma-4-E2B_q4_0-it.gguf"

        // One model, one runtime (ADR 0009). MLX is a development path, not a
        // shipping one — mmap-backed reload, not "cannot load on MLX" (see the
        // ADR 0009 amendment). `mbt --engine mlx` still exists for experiments.
        let engine: any TranslationEngine = LlamaEngine(modelPath: llamaPath)

        let preset = MemoryPreset.forPhysicalMemory(ProcessInfo.processInfo.physicalMemory)

        // OS fallback (ADR 0006): translator reads the live session box; throws
        // unavailable when the session is absent or the pair token doesn't match
        // the configured direction. fallbackAvailable feeds AppRuntime's gate.
        let osEngine = OSTranslationEngine(
            availability: { cap.value },
            translator: { text, pair in
                try await translateOnMainActor(text, pair, box: box)
            }
        )

        let runtime = AppRuntime(
            engine: engine,
            preset: preset,
            fallback: osEngine,
            fallbackAvailable: { cap.value.isAvailable }
        )
        self.vm = AppViewModel(runtime: runtime)
    }
}

// MARK: - App delegate

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon; menu bar only
    }
}

// MARK: - App root

// Note: @main cannot appear in main.swift (Swift constraint). Entry point is
// app/main.swift, which calls MenubarTranslateApp.main() directly.
struct MenubarTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("MenubarTranslate", systemImage: "character.bubble") {
            ContentView(
                vm: appState.vm,
                box: appState.sessionBox,
                cap: appState.capHolder
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Content view

struct ContentView: View {
    @Bindable var vm: AppViewModel
    let box: SessionBox
    let cap: CapabilityHolder
    /// Local so IME composition is not reset when `@Observable` snapshot/isBusy ticks.
    @State private var draft = ""

    private let jaEnConfig = TranslationSession.Configuration(
        source: Locale.Language(identifier: "ja"),
        target: Locale.Language(identifier: "en")
    )
    private let enJaConfig = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ja")
    )

    var body: some View {
        PanelChrome(vm: vm, draft: $draft, onQuit: quitProcess)
        .task { @MainActor in
            var ticksSinceProbe = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await vm.tick()
                ticksSinceProbe += 1
                if ticksSinceProbe >= 30 {
                    ticksSinceProbe = 0
                    await probeCapability()
                }
            }
        }
        .translationTask(jaEnConfig) { session in
            box.jaEnSession = session
            await probeCapability()
            if cap.value.pairSupported, !cap.value.modelDownloaded,
               vm.snapshot.pressure == .normal, cap.claimPrepare() {
                try? await SendableSession(session: session).session.prepareTranslation()
            }
            try? await Task.sleep(nanoseconds: .max)
            box.jaEnSession = nil
        }
        .translationTask(enJaConfig) { session in
            box.enJaSession = session
            try? await Task.sleep(nanoseconds: .max)
            box.enJaSession = nil
        }
    }

    @MainActor
    private func probeCapability() async {
        let status = await LanguageAvailability().status(
            from: Locale.Language(identifier: "ja"),
            to: Locale.Language(identifier: "en")
        )
        cap.value = FallbackCapability(
            apiPresent: true,
            pairSupported: status == .installed || status == .supported,
            modelDownloaded: status == .installed
        )
    }
}

/// llama.cpp b9878 aborts in a ggml-metal static destructor at normal teardown.
private func quitProcess() { _exit(0) }
