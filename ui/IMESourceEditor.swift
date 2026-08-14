import AppKit
import SwiftUI

/// NSTextView wrapper that does not publish while IME composition is marked,
/// so live-translate does not fire on half-composed Japanese.
struct IMESourceEditor: NSViewRepresentable {
    @Binding var text: String
    var onStableChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let tv = SourceTextView()
        tv.delegate = context.coordinator
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
        tv.string = text
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? SourceTextView else { return }
        tv.trailingGutter = fieldScrollerGutter()
        if !tv.hasMarkedText(), tv.string != text {
            tv.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESourceEditor
        weak var textView: NSTextView?

        init(_ parent: IMESourceEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, !tv.hasMarkedText() else { return }
            parent.text = tv.string
            parent.onStableChange(tv.string)
        }
    }
}

/// Right-side gap so overlay scrollers do not sit on glyphs.
func fieldScrollerGutter() -> CGFloat {
    NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle) + 4
}

private final class SourceTextView: NSTextView {
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
