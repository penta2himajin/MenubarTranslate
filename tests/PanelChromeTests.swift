import AppKit
import SwiftUI
import Testing
@testable import MenubarTranslateCore
@testable import MenubarTranslateUI

@MainActor
private func makeVM() -> AppViewModel {
    AppViewModel(
        runtime: AppRuntime(
            engine: FakeEngine(),
            preset: .conservative8GB,
            fallback: nil,
            fallbackAvailable: nil,
            clock: ManualClock(),
            pressureSource: FakePressureSource()
        )
    )
}

@MainActor
private func host(_ vm: AppViewModel, draft: String = "") -> NSHostingView<PanelChrome> {
    let view = PanelChrome(
        vm: vm,
        draft: .constant(draft)
    )
    let host = NSHostingView(rootView: view)
    host.frame = NSRect(x: 0, y: 0, width: 380, height: 640)
    host.layoutSubtreeIfNeeded()
    return host
}

@MainActor
private func strings(in view: NSView) -> [String] {
    var out: [String] = []
    func walk(_ v: NSView) {
        if let tf = v as? NSTextField, !tf.stringValue.isEmpty { out.append(tf.stringValue) }
        if let tv = v as? NSTextView, !tv.string.isEmpty { out.append(tv.string) }
        if let text = v as? NSText, !text.string.isEmpty { out.append(text.string) }
        let id = v.accessibilityIdentifier()
        if !id.isEmpty { out.append("id:\(id)") }
        if let val = v.accessibilityValue() as? String, !val.isEmpty { out.append(val) }
        v.subviews.forEach(walk)
    }
    walk(view)
    return out
}

@Suite("PanelChrome hosting")
@MainActor
struct PanelChromeTests {

    @Test("empty panel reserves the output slot")
    func emptyPanelReservesOutputSlot() {
        let found = strings(in: host(makeVM()))
        #expect(found.contains(where: { $0.contains("Translation appears here") }))
        #expect(!found.contains("Source"))
        #expect(!found.contains("Translation"))
    }

    @Test("runtime status is not shown on the panel")
    func statusHiddenFromPanel() {
        let found = strings(in: host(makeVM()))
        #expect(!found.contains(where: { $0.contains("unloaded") }))
        #expect(!found.contains("id:status-line"))
    }

    @Test("settings gear is on the panel")
    func settingsGearOnPanel() {
        let found = strings(in: host(makeVM()))
        #expect(found.contains("id:settings-menu"))
    }

    @Test("target language shows as text with the picker identifier")
    func targetPickerShowsMenuLabel() {
        let vm = makeVM()
        vm.targetLanguage = .ja
        let window = host(vm)
        let found = strings(in: window)
        #expect(found.contains(where: { $0.contains("日本語") }))
    }

    @Test("output text is in the hosted view after translate")
    func hostedViewShowsEngineOutput() async {
        let vm = makeVM()
        let window = host(vm)
        await vm.translate(draft: "こんにちは")
        window.layoutSubtreeIfNeeded()
        await Task.yield()
        let found = strings(in: window)
        #expect(
            found.contains(where: { $0.contains("[ja-en] こんにちは") }),
            "hosted panel must show the engine result, got \(found)"
        )
    }

    @Test("glyphs sit 6pt from chrome; scroller sits 1pt off the trailing edge")
    func fieldTrailingChrome() async {
        let long = String(repeating: "あいうえお漢字English mix\n", count: 24)
        let vm = makeVM()
        let window = host(vm, draft: long)
        await vm.translate(draft: long)
        window.layoutSubtreeIfNeeded()
        for editable in [true, false] {
            let dump = trailingDump(in: window, editable: editable)
            #expect(dump != nil, "missing NSScrollView editable=\(editable), hierarchy: \(viewDump(window))")
            guard let dump else { continue }
            #expect(
                abs(dump.scrollToChrome) < 1,
                "scroll view should fill the field, scroll-to-chrome \(dump.scrollToChrome); \(dump)"
            )
            #expect(
                abs(dump.scrollerToChrome - fieldScrollerEdge) < 1.5,
                "scroller-to-chrome \(dump.scrollerToChrome) expected \(fieldScrollerEdge); editable=\(editable) \(dump)"
            )
            #expect(
                abs(dump.glyphToChrome - fieldGlyphTrailing) < 2,
                "glyph-to-chrome \(dump.glyphToChrome) expected \(fieldGlyphTrailing); editable=\(editable) \(dump)"
            )
        }
    }
}

private struct TrailingDump: CustomStringConvertible {
    var scrollWidth: CGFloat
    var scrollerWidth: CGFloat
    var scrollerToChrome: CGFloat
    var glyphToScroller: CGFloat
    var glyphToChrome: CGFloat
    var scrollToChrome: CGFloat
    var containerWidth: CGFloat
    var textViewWidth: CGFloat
    var chromeWidth: CGFloat
    var ancestors: String

    var description: String {
        "chromeW=\(chromeWidth) scrollW=\(scrollWidth) tvW=\(textViewWidth) containerW=\(containerWidth) scrollerW=\(scrollerWidth) scrollToChrome=\(scrollToChrome) scrollerToChrome=\(scrollerToChrome) glyphToScroller=\(glyphToScroller) glyphToChrome=\(glyphToChrome)"
    }
}

@MainActor
private func trailingDump(in root: NSView, editable: Bool) -> TrailingDump? {
    guard let scroll = firstScroll(in: root, editable: editable),
          let tv = scroll.documentView as? NSTextView
    else { return nil }

    let chrome = scroll
    let chromeFrame = chrome.convert(chrome.bounds, to: root)
    let scrollFrame = scroll.convert(scroll.bounds, to: root)
    let tvFrame = tv.convert(tv.bounds, to: root)
    let leading = (tv as? SourceTextView)?.leadingGutter ?? fieldTextInset
    let containerW = tv.textContainer?.containerSize.width ?? tvFrame.width
    let glyphMaxX = tvFrame.minX + leading + containerW
    let scroller = scroll.verticalScroller
    let scrollerFrame: NSRect = {
        if let s = scroller, s.bounds.width > 0 {
            return s.convert(s.bounds, to: root)
        }
        let w = NSScroller.scrollerWidth(for: .mini, scrollerStyle: .overlay)
        return NSRect(x: scrollFrame.maxX - w, y: scrollFrame.minY, width: w, height: scrollFrame.height)
    }()

    var ancestorBits: [String] = []
    var p: NSView? = scroll
    while let v = p {
        let f = v.convert(v.bounds, to: root)
        ancestorBits.append("\(type(of: v)) w=\(f.width) maxX=\(f.maxX)")
        p = v.superview
        if v === root { break }
    }

    return TrailingDump(
        scrollWidth: scrollFrame.width,
        scrollerWidth: scrollerFrame.width,
        scrollerToChrome: chromeFrame.maxX - scrollerFrame.maxX,
        glyphToScroller: scrollerFrame.minX - glyphMaxX,
        glyphToChrome: chromeFrame.maxX - glyphMaxX,
        scrollToChrome: chromeFrame.maxX - scrollFrame.maxX,
        containerWidth: containerW,
        textViewWidth: tvFrame.width,
        chromeWidth: chromeFrame.width,
        ancestors: ancestorBits.joined(separator: " → ")
    )
}

@MainActor
private func firstScroll(in root: NSView, editable: Bool) -> NSScrollView? {
    var found: NSScrollView?
    func walk(_ v: NSView) {
        if found != nil { return }
        if let s = v as? NSScrollView, let tv = s.documentView as? NSTextView, tv.isEditable == editable {
            found = s
            return
        }
        v.subviews.forEach(walk)
    }
    walk(root)
    return found
}

@MainActor
private func viewDump(_ root: NSView) -> String {
    var lines: [String] = []
    func walk(_ v: NSView, depth: Int) {
        let pad = String(repeating: "  ", count: depth)
        let id = v.accessibilityIdentifier()
        lines.append("\(pad)\(type(of: v)) \(v.frame) id=\(id)")
        v.subviews.forEach { walk($0, depth: depth + 1) }
    }
    walk(root, depth: 0)
    return lines.joined(separator: "\n")
}
