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
import MTEngineLlama

// MARK: - Known gap: AppViewModel isolation


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
    init(presetKey: String) {
        let box = SessionBox()
        let cap = CapabilityHolder()
        self.sessionBox = box
        self.capHolder = cap

        // Resolve the model path from environment; mirrors mbt/main.swift.
        let llamaPath = ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"]
            ?? "models/weights/gemma-4-E2B_q4_0-it.gguf"

        // One model, one runtime (ADR 0009). MLX is a development path, not a
        // shipping one — and it cannot load Gemma 4 E2B at all — so the app target
        // no longer links it. `mbt --engine mlx` still exists for experiments.
        let engine: any TranslationEngine = LlamaEngine(modelPath: llamaPath)

        let preset: MemoryPreset = presetKey == "permissive16GB"
            ? .permissive16GB : .conservative8GB

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

    // The preset survives restarts. Hot-swap is intentionally out of scope
    // (ADR 0009); a restart is required after changing it.
    @AppStorage("preset") private var presetKey: String = "conservative8GB"

    @State private var appState: AppState

    init() {
        // @AppStorage properties are not accessible before init completes, so read
        // the same UserDefaults store directly to build the initial stack.
        let pstKey = UserDefaults.standard.string(forKey: "preset") ?? "conservative8GB"
        _appState = State(wrappedValue: AppState(presetKey: pstKey))
    }

    var body: some Scene {
        MenuBarExtra("MenubarTranslate", systemImage: "character.bubble") {
            ContentView(
                vm: appState.vm,
                box: appState.sessionBox,
                cap: appState.capHolder,
                presetKey: $presetKey
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Content view

struct ContentView: View {
    // @Observable vm — SwiftUI tracks property accesses and re-renders on change.
    let vm: AppViewModel
    let box: SessionBox
    let cap: CapabilityHolder
    @Binding var presetKey: String

    // Directional Translation session configurations — fixed for the app lifetime.
    // Two configurations keep both directional sessions alive simultaneously so the
    // OSTranslationEngine translator closure can serve either pair (ADR 0006).
    private let jaEnConfig = TranslationSession.Configuration(
        source: Locale.Language(identifier: "ja"),
        target: Locale.Language(identifier: "en")
    )
    private let enJaConfig = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ja")
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Direction toggle
            HStack {
                Text(vm.direction == .jaToEn ? "JA → EN" : "EN → JA")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    vm.direction.toggle()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .buttonStyle(.borderless)
                .help("Flip translation direction")
            }

            // Input
            TextEditor(text: Binding(
                get: { vm.input },
                set: { vm.setInput($0) }
            ))
            .frame(minHeight: 60, maxHeight: 120)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

            // Translate (⌘↩ shortcut)
            Button("Translate") {
                Task { @MainActor in await vm.translate() }
            }
            .disabled(vm.isBusy || vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)

            // Output (selectable)
            if !vm.output.isEmpty {
                ScrollView {
                    Text(vm.output)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(4)
            }

            // Error message
            if let err = vm.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }

            Divider()

            // Bottom bar: status · settings gear · quit
            HStack {
                // Snapshot: weight-lifecycle phase and memory-pressure band.
                Text("\(vm.snapshot.phase.rawValue) · \(vm.snapshot.pressure.rawValue)")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()

                Spacer()

                // Preset setting — changes take effect after restart. There is no
                // engine picker: ADR 0009 ships one model on one runtime, and the
                // alternative would have silently loaded a different model.
                Menu {
                    Picker("Memory", selection: $presetKey) {
                        Text("8 GB / conservative").tag("conservative8GB")
                        Text("16 GB / permissive").tag("permissive16GB")
                    }
                    Divider()
                    // Convenience: restart after changing settings.
                    // _exit, not exit: see Quit button comment below.
                    Button("Restart to apply changes") { _exit(0) }
                } label: {
                    Image(systemName: "gearshape").imageScale(.small)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
                .help("Memory-preset changes require a restart")

                // _exit not exit: llama.cpp b9878 aborts in a ggml-metal static
                // destructor at normal teardown (upstream GGML_ASSERT in
                // ggml-metal-device.m:622), corrupting the exit code to 134.
                // All output uses unbuffered FileHandle; skipping atexit is safe.
                Button("Quit") { _exit(0) }.buttonStyle(.borderless).font(.caption)
            }
        }
        .padding(12)
        .frame(width: 320)

        // Tick loop: advances idle-timeout and warn-debounce in ResidencyManager.
        // The 1 s cadence is set by the residency timers, not by the capability gate:
        // capability only changes when the user installs or removes an OS language
        // model, so re-probing it every second is ~30x wasted work. The first probe
        // happens at session creation in .translationTask below.
        // ponytail: fixed 30 s cadence; make it event-driven if the framework ever
        // exposes an availability-changed notification.
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

        // OS Translation sessions — action closures sleep forever so each session stays
        // valid for the app's lifetime. Sessions are written to the box here and consumed
        // by OSTranslationEngine's translator closure (ADR 0006).
        //
        // ja→en: ahead-of-time prepareTranslation() — while pressure is Normal and the
        // model is .supported (not .installed), request a prepare once per launch so the
        // fallback is ready before Critical arrives (ADR 0006). Probe here rather than
        // reading cap.value: this closure runs once at session creation, before the
        // first tick has populated the shared capability snapshot.
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

    // MARK: Capability probe

    /// Update the shared capability snapshot from the live Translation-framework status.
    /// Called once per tick; the call is cheap (a local system query, no network).
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
