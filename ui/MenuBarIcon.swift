import AppKit

/// Menu-bar template glyph. Source PNGs are 1024px; leaving `NSImage.size`
/// at that value makes the extra huge and macOS often hides it off the bar.
public enum MenuBarIcon {
    public static let pointSize: CGFloat = 18

    public static func prepare(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        image.size = NSSize(width: pointSize, height: pointSize)
        return image
    }

    public static func loadFromBundles(_ bundles: [Bundle]) -> NSImage {
        for bundle in bundles {
            if let url = bundle.url(forResource: "MenuBarIconTemplate", withExtension: "png"),
               let image = NSImage(contentsOf: url)
            {
                return prepare(image)
            }
        }
        let fallback = NSImage(
            systemSymbolName: "character.bubble",
            accessibilityDescription: "MenubarTranslate"
        ) ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        return prepare(fallback)
    }
}
