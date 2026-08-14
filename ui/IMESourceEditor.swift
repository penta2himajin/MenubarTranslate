import AppKit
import SwiftUI

/// NSTextView wrapper that does not publish while IME composition is marked,
/// so live-translate does not fire on half-composed Japanese.
struct IMESourceEditor: NSViewRepresentable {
    @Binding var text: String
    var onStableChange: (String) -> Void
    var sync: FieldScrollSync

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = makeFieldScroll(editable: true, delegate: context.coordinator)
        context.coordinator.textView = scroll.documentView as? NSTextView
        context.coordinator.scroll = scroll
        context.coordinator.bind()
        sync.register(scroll, role: .source)
        if let tv = scroll.documentView as? NSTextView { tv.string = text }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        sync.register(scroll, role: .source)
        guard let tv = scroll.documentView as? SourceTextView else { return }
        tv.trailingGutter = fieldScrollerGutter()
        if !tv.hasMarkedText(), tv.string != text {
            tv.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESourceEditor
        weak var textView: NSTextView?
        weak var scroll: NSScrollView?

        init(_ parent: IMESourceEditor) { self.parent = parent }

        deinit { NotificationCenter.default.removeObserver(self) }

        func bind() {
            guard let clip = scroll?.contentView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
        }

        @objc func boundsChanged(_ notification: Notification) {
            guard let scroll else { return }
            parent.sync.propagate(from: scroll)
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, !tv.hasMarkedText() else { return }
            parent.text = tv.string
            parent.onStableChange(tv.string)
        }
    }
}

/// Read-only counterpart of `IMESourceEditor`, same gutter and scroll metrics.
struct TranslationOutputEditor: NSViewRepresentable {
    var text: String
    var sync: FieldScrollSync

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = makeFieldScroll(editable: false, delegate: nil)
        context.coordinator.scroll = scroll
        context.coordinator.bind()
        sync.register(scroll, role: .output)
        apply(text, to: scroll)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        sync.register(scroll, role: .output)
        if let tv = scroll.documentView as? SourceTextView {
            tv.trailingGutter = fieldScrollerGutter()
        }
        apply(text, to: scroll)
    }

    private func apply(_ text: String, to scroll: NSScrollView) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let empty = text.isEmpty
        let display = empty ? "Translation appears here" : text
        tv.textColor = empty ? .tertiaryLabelColor : .labelColor
        if tv.string != display { tv.string = display }
        tv.setAccessibilityIdentifier("translation-output")
        tv.setAccessibilityValue(text)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: TranslationOutputEditor
        weak var scroll: NSScrollView?

        init(_ parent: TranslationOutputEditor) { self.parent = parent }

        deinit { NotificationCenter.default.removeObserver(self) }

        func bind() {
            guard let clip = scroll?.contentView else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsChanged),
                name: NSView.boundsDidChangeNotification,
                object: clip
            )
        }

        @objc func boundsChanged(_ notification: Notification) {
            guard let scroll else { return }
            parent.sync.propagate(from: scroll)
        }
    }
}

/// Right-side gap so overlay scrollers do not sit on glyphs.
@MainActor
func fieldScrollerGutter() -> CGFloat {
    NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle) + 4
}

@MainActor
private func makeFieldScroll(editable: Bool, delegate: NSTextViewDelegate?) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    scroll.drawsBackground = false
    let tv = SourceTextView()
    tv.delegate = delegate
    tv.isEditable = editable
    tv.isSelectable = true
    tv.isRichText = false
    tv.font = .systemFont(ofSize: NSFont.systemFontSize)
    tv.backgroundColor = .clear
    tv.textContainerInset = .zero
    tv.textContainer?.lineFragmentPadding = 0
    tv.isVerticallyResizable = true
    tv.isHorizontallyResizable = false
    tv.textContainer?.widthTracksTextView = false
    tv.trailingGutter = fieldScrollerGutter()
    tv.minSize = NSSize(width: 0, height: 0)
    tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    tv.autoresizingMask = [.width]
    scroll.documentView = tv
    return scroll
}

final class SourceTextView: NSTextView {
    var trailingGutter: CGFloat = 0 {
        didSet { if oldValue != trailingGutter { invalidateTextContainerWidth() } }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateTextContainerWidth()
    }

    private func invalidateTextContainerWidth() {
        textContainer?.containerSize = NSSize(
            width: max(1, frame.width - trailingGutter),
            height: .greatestFiniteMagnitude
        )
    }
}
