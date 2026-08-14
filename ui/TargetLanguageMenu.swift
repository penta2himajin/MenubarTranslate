import AppKit
import SwiftUI
import MenubarTranslateCore

/// Width of the NSMenu checkmark column. The popup is shifted left by this
/// so item titles line up with the on-screen language label.
let languageMenuCheckGutter: CGFloat = 21

struct TargetLanguageMenu: NSViewRepresentable {
    @Binding var selection: AppLanguage
    var languages: [AppLanguage]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LanguageMenuNSView {
        let view = LanguageMenuNSView()
        context.coordinator.bind(view, selection: $selection)
        return view
    }

    func updateNSView(_ view: LanguageMenuNSView, context: Context) {
        context.coordinator.bind(view, selection: $selection)
        view.languages = languages
        view.selection = selection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LanguageMenuNSView, context: Context)
        -> CGSize?
    {
        nsView.intrinsicContentSize
    }

    @MainActor
    final class Coordinator {
        var binding: Binding<AppLanguage>?

        func bind(_ view: LanguageMenuNSView, selection: Binding<AppLanguage>) {
            binding = selection
            view.onSelect = { [weak self] lang in
                self?.binding?.wrappedValue = lang
            }
        }
    }
}

final class LanguageMenuNSView: NSView {
    var languages: [AppLanguage] = []
    var selection: AppLanguage = .en {
        didSet { title.stringValue = selection.menuLabel }
    }
    var onSelect: ((AppLanguage) -> Void)?

    private let title = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: NSFont.systemFontSize)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .semibold)
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        chevron.contentTintColor = .secondaryLabelColor
        chevron.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 3),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
            chevron.heightAnchor.constraint(equalToConstant: 8),
        ])
        setAccessibilityIdentifier("target-picker")
        setAccessibilityRole(.popUpButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let t = title.intrinsicContentSize
        return NSSize(width: t.width + 3 + 8, height: max(t.height, 16))
    }

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for lang in languages {
            let item = NSMenuItem(title: lang.menuLabel, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang.rawValue
            item.state = lang == selection ? .on : .off
            menu.addItem(item)
        }
        // Flipped: origin is top-left. Menu's top-left sits at this point, so
        // y = bounds.maxY opens it just below the label, x shifted by the check column.
        menu.popUp(positioning: nil, at: NSPoint(x: -languageMenuCheckGutter - 2, y: bounds.maxY + 6), in: self)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw)
        else { return }
        selection = lang
        onSelect?(lang)
    }
}
