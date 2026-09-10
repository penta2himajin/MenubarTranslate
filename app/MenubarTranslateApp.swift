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
    private let runtime: AppRuntime
    private var httpServer: LoopbackHTTPServer?

    /// Mirrors mbt/main.swift engine-factory logic exactly (env vars, default paths).
    init() {
        let box = SessionBox()
        let cap = CapabilityHolder()
        self.sessionBox = box
        self.capHolder = cap

        // Resolve the model path from environment; mirrors mbt/main.swift.
        let llamaPath = ModelPath.llamaGGUF()
        AppLog.info(.model, "resolved", ["path": llamaPath])

        // One model, one runtime (ADR 0009). MLX is a development path, not a
        // shipping one — mmap-backed reload, not "cannot load on MLX" (see the
        // ADR 0009 amendment). `mbt --engine mlx` still exists for experiments.
        let engine: any TranslationEngine = LlamaEngine(modelPath: llamaPath)

        let preset = MemoryPreset.forPhysicalMemory(ProcessInfo.processInfo.physicalMemory)
        AppLog.info(.app, "boot", [
            "preset": preset == .conservative8GB ? "conservative8GB" : "permissive16GB",
            "log_level": AppLog.minimumLevel.label,
            "log_dir": CrashLog.logsDirectory().path,
        ])

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
        self.runtime = runtime
        if LoopbackPreference.isEnabled() {
            startHTTPLoopback()
        }
    }

    func setHTTPLoopbackEnabled(_ on: Bool) {
        LoopbackPreference.setEnabled(on)
        AppLog.info(.http, on ? "loopback_on" : "loopback_off", [
            "port": "\(ImmersiveTranslate.port())",
        ])
        if on {
            startHTTPLoopback()
        } else {
            httpServer?.stop()
            httpServer = nil
        }
    }

    private func startHTTPLoopback() {
        guard httpServer == nil else { return }
        do {
            let runtime = runtime
            httpServer = try LoopbackHTTPServer(port: ImmersiveTranslate.port()) { items in
                try await runtime.translateMany(items)
            }
        } catch {
            AppLog.error(.http, "loopback_start_failed", ["error": String(describing: error)])
        }
    }
}

// MARK: - App delegate

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon; menu bar only
        installStatusItem()
        FileHandle.standardError.write(Data("menu bar ready pid=\(getpid())\n".utf8))
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        FileHandle.standardError.write(
            Data("reopen hasVisibleWindows=\(flag)\n".utf8)
        )
        showPanel()
        return true
    }

    private func installStatusItem() {
        let image = MenuBarIcon.loadFromBundles([Bundle.module, Bundle.main])
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "MenubarTranslate"
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        let host = NSHostingController(
            rootView: ContentView(
                vm: appState.vm,
                box: appState.sessionBox,
                cap: appState.capHolder,
                onToggleHTTPLoopback: { [appState] on in
                    appState.setHTTPLoopbackEnabled(on)
                }
            )
        )
        host.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = host
        self.popover = popover

        FileHandle.standardError.write(
            Data("status item \(Int(image.size.width))x\(Int(image.size.height)) template=\(image.isTemplate)\n".utf8)
        )
    }

    @objc private func togglePanel() {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button, let popover else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

// MARK: - App root

// Note: @main cannot appear in main.swift (Swift constraint). Entry point is
// app/main.swift, which calls MenubarTranslateApp.main() directly.
struct MenubarTranslateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Status item is installed in AppDelegate. Settings is the required Scene
        // without putting a second (1024pt) glyph on the menu bar via MenuBarExtra.
        Settings { EmptyView() }
    }
}

// MARK: - Content view

struct ContentView: View {
    @Bindable var vm: AppViewModel
    let box: SessionBox
    let cap: CapabilityHolder
    var onToggleHTTPLoopback: (Bool) -> Void
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
        PanelChrome(
            vm: vm,
            draft: $draft,
            onQuit: quitProcess,
            onToggleHTTPLoopback: onToggleHTTPLoopback
        )
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
