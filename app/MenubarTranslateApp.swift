// app/MenubarTranslateApp.swift
// M3 Wave C2 — SwiftUI menu-bar app shell.
//
// SwiftUI and Translation-framework code lives here; src/ stays SwiftUI-free per the
// ADR 0006 seam: the core exposes OSTranslationEngine with closure slots, and this
// file owns the OS APIs and fills them.

import AppKit
import Darwin
import SwiftUI
import Translation
import MenubarTranslateCore
import MTEngineLlama
import MTEngineMLX

// MARK: - Swift 6 concurrency shims

// AppViewModel is @Observable and effectively main-actor–only in the app layer.
// @unchecked Sendable suppresses Swift 6 region-isolation diagnostics for calls
// from @MainActor tasks; caller guarantees main-actor access throughout.
// ponytail: @unchecked — main-actor invariant enforced by all call sites in this file
extension AppViewModel: @unchecked Sendable {}

// TranslationSession is received from a .translationTask closure that is implicitly
// @MainActor; calling its async methods triggers region-isolation errors without this.
// ponytail: @unchecked — session is used only within the main-actor translationTask closure
extension TranslationSession: @unchecked @retroactive Sendable {}

// MARK: - Shared reference boxes

/// Mutable capability state — written on the main actor, read from @Sendable closures.
/// @unchecked Sendable: all callers enforce main-actor access; nonisolated(unsafe)
/// silences the static checker where main-actor use is obvious.
final class CapabilityHolder: @unchecked Sendable {
    // ponytail: nonisolated(unsafe) — main-actor-only access enforced by callers
    nonisolated(unsafe) var value = FallbackCapability(
        apiPresent: false, pairSupported: false, modelDownloaded: false
    )
    // Guards the one-shot prepareTranslation() call from the translationTask closure.
    nonisolated(unsafe) var didPrepare = false
}

/// Directional Translation-framework sessions.
/// Valid only while the respective .translationTask closure is alive.
/// @unchecked Sendable: main-actor-only access enforced by callers.
final class SessionBox: @unchecked Sendable {
    // ponytail: nonisolated(unsafe) — main-actor-only access enforced by callers
    nonisolated(unsafe) var jaEnSession: TranslationSession?
    nonisolated(unsafe) var enJaSession: TranslationSession?
}

// MARK: - App state (translation stack)

/// Owns the entire translation stack so it survives App struct rebuilds via @State.
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
                let session = pair.sourceCode == "ja" ? box.jaEnSession : box.enJaSession
                guard let session else {
                    throw TranslationEngineError.unavailable(
                        "OS Translation session not ready (pair: \(pair.token))")
                }
                let result = try await session.translate(text)
                return result.targetText
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
            if !cap.didPrepare && cap.value.pairSupported && !cap.value.modelDownloaded
                    && vm.snapshot.pressure == .normal {
                cap.didPrepare = true
                try? await session.prepareTranslation()
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
