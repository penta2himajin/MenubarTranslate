import AppKit
import ServiceManagement
import SwiftUI

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("login item: \(error)")
        }
    }
}

struct SettingsMenu: NSViewRepresentable {
    var onQuit: () -> Void

    func makeNSView(context: Context) -> SettingsMenuNSView {
        let view = SettingsMenuNSView()
        view.onQuit = onQuit
        return view
    }

    func updateNSView(_ view: SettingsMenuNSView, context: Context) {
        view.onQuit = onQuit
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SettingsMenuNSView, context: Context)
        -> CGSize?
    {
        nsView.intrinsicContentSize
    }
}

final class SettingsMenuNSView: NSView {
    var onQuit: () -> Void = {}

    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .labelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
        ])
        setAccessibilityIdentifier("settings-menu")
        setAccessibilityRole(.button)
        setAccessibilityLabel("Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let login = NSMenuItem(
            title: "Open at Login",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: bounds.maxX - menu.size.width, y: bounds.maxY + 4),
            in: self
        )
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
    }

    @objc private func quit() {
        onQuit()
    }
}
