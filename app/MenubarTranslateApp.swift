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
import MTEngineMLX

// MARK: - Known gap: AppViewModel isolation

// AppViewModel is @Observable and read by SwiftUI on the main actor, but its
// `translate()`/`tick()` are nonisolated async, so they mutate `output`/`isBusy`/
// `snapshot` off the main actor. That is a real race, and this conformance is what
// silences it — it is a suppression, not a proof of safety.
//
// The fix is @MainActor on AppViewModel itself (in the core), which also forces
// AppRuntime.onChange to hop actors. That changes snapshot propagation from
// synchronous to async and breaks the write-locked
// tests/AppViewModelTests.swift:snapshotMirrorsRuntime, so it needs its own change
// with the test contract renegotiated — not a drive-by edit here.
// ponytail: known-unsafe, scoped and documented; see the note above for the real fix.
extension AppViewModel: @unchecked Sendable {}

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
    init(engineKey: String, presetKey: String) {
        let box = SessionBox()
        let cap = CapabilityHolder()
        self.sessionBox = box
        self.capHolder = cap

        // Resolve model paths from environment; mirrors mbt/main.swift.
        let llamaPath = ProcessInfo.processInfo.environment["MBT_LLAMA_GGUF"]
            ?? "models/weights/translategemma-4b-it-Q4_K_M.gguf"
        let mlxDir = ProcessInfo.processInfo.environment["MBT_MLX_DIR"]
            ?? "models/weights/translategemma-mlx"

        // Default: GGUF/llama.cpp (amended ADR 0008 — EN→JA artifact root-caused, fixed).
        let engine: any TranslationEngine = engineKey == "mlx"
            ? MLXEngine(modelDirectory: mlxDir)
            : LlamaEngine(modelPath: llamaPath)

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

    // Engine and preset survive restarts. Hot-swap is intentionally out of scope
    // (ADR 0008); a restart is required after changing either setting.
    @AppStorage("engine") private var engineKey: String = "llama"
    @AppStorage("preset") private var presetKey: String = "conservative8GB"

    @State private var appState: AppState

    init() {
        // @AppStorage properties are not accessible before init completes, so read
        // the same UserDefaults store directly to build the initial stack.
        let engKey = UserDefaults.standard.string(forKey: "engine") ?? "llama"
        let pstKey = UserDefaults.standard.string(forKey: "preset") ?? "conservative8GB"
        _appState = State(wrappedValue: AppState(engineKey: engKey, presetKey: pstKey))
    }

    var body: some Scene {
        MenuBarExtra("MenubarTranslate", systemImage: "character.bubble") {
            ContentView(
                vm: appState.vm,
                box: appState.sessionBox,
                cap: appState.capHolder,
                engineKey: $engineKey,
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
    @Binding var engineKey: String
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

                // Engine / preset settings — changes take effect after restart.
                Menu {
                    Picker("Engine", selection: $engineKey) {
                        Text("llama.cpp GGUF (default)").tag("llama")
                        Text("MLX 4-bit").tag("mlx")
                    }
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
                .help("Engine/preset changes require a restart")

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
        // Also re-probes Translation-framework capability on each tick (cheap).
        .task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await vm.tick()
                await probeCapability()
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
