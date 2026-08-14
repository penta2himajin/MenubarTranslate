import Testing
@testable import MenubarTranslateUI

@Suite("FieldScroll")
struct FieldScrollTests {

    @Test("fraction is 0 at top and 1 at bottom")
    func fractionEnds() {
        #expect(scrollFraction(clipHeight: 100, documentHeight: 500, originY: 0) == 0)
        #expect(scrollFraction(clipHeight: 100, documentHeight: 500, originY: 400) == 1)
        #expect(scrollFraction(clipHeight: 100, documentHeight: 500, originY: 200) == 0.5)
    }

    @Test("no document overflow stays at 0")
    func shortDocument() {
        #expect(scrollFraction(clipHeight: 100, documentHeight: 80, originY: 0) == 0)
        #expect(scrollOriginY(fraction: 1, clipHeight: 100, documentHeight: 80) == 0)
    }

    @Test("origin maps a fraction back onto the overflow")
    func originFromFraction() {
        #expect(scrollOriginY(fraction: 0, clipHeight: 100, documentHeight: 500) == 0)
        #expect(scrollOriginY(fraction: 1, clipHeight: 100, documentHeight: 500) == 400)
        #expect(scrollOriginY(fraction: 0.5, clipHeight: 100, documentHeight: 500) == 200)
    }

    @Test("trailing gutter is 6pt overlay inset, not scroller width")
    func trailingGutterIgnoresScrollerWidth() {
        #expect(fieldTrailingGutter(scrollerWidth: 10) == fieldGlyphTrailing)
        #expect(fieldTrailingGutter(scrollerWidth: 99) == fieldGlyphTrailing)
    }
}
