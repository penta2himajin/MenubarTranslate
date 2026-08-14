import AppKit
import SwiftUI
import Testing
@testable import MenubarTranslateCore
import MenubarTranslateUI

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
        draft: .constant(draft),
        presetKey: .constant("conservative8GB")
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
}
