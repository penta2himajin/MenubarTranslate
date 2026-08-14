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
        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.font = .systemFont(ofSize: NSFont.systemFontSize)
        tv.backgroundColor = .clear
        tv.textContainerInset = NSSize(width: 4, height: 4)
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.string = text
        scroll.documentView = tv
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
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
