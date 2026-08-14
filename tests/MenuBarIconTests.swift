import AppKit
import Testing
import MenubarTranslateUI

@Suite("MenuBarIcon")
struct MenuBarIconTests {
    @Test("template icons are sized for the menu bar, not the source pixel grid")
    func preparesPointSizeForStatusItem() {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        let prepared = MenuBarIcon.prepare(image)
        #expect(prepared.size == NSSize(width: 18, height: 18))
        #expect(prepared.isTemplate)
    }
}
