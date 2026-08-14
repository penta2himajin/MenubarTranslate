import AppKit

func scrollFraction(clipHeight: CGFloat, documentHeight: CGFloat, originY: CGFloat) -> CGFloat {
    let maxOff = documentHeight - clipHeight
    guard maxOff > 0 else { return 0 }
    return min(1, max(0, originY / maxOff))
}

func scrollOriginY(fraction: CGFloat, clipHeight: CGFloat, documentHeight: CGFloat) -> CGFloat {
    let maxOff = documentHeight - clipHeight
    guard maxOff > 0 else { return 0 }
    return min(1, max(0, fraction)) * maxOff
}

/// Keeps two field scroll views at the same vertical fraction.
@MainActor
final class FieldScrollSync {
    enum Role { case source, output }

    weak var source: NSScrollView?
    weak var output: NSScrollView?
    private var syncing = false

    func register(_ scroll: NSScrollView, role: Role) {
        switch role {
        case .source: source = scroll
        case .output: output = scroll
        }
        scroll.contentView.postsBoundsChangedNotifications = true
    }

    func propagate(from scroll: NSScrollView) {
        guard !syncing else { return }
        let other: NSScrollView?
        if scroll === source { other = output }
        else if scroll === output { other = source }
        else { return }
        guard let other else { return }
        let clip = scroll.contentView.bounds
        let doc = scroll.documentView?.frame.height ?? 0
        let f = scrollFraction(clipHeight: clip.height, documentHeight: doc, originY: clip.origin.y)
        let oClip = other.contentView.bounds
        let oDoc = other.documentView?.frame.height ?? 0
        var origin = oClip.origin
        origin.y = scrollOriginY(fraction: f, clipHeight: oClip.height, documentHeight: oDoc)
        syncing = true
        other.contentView.scroll(to: origin)
        other.reflectScrolledClipView(other.contentView)
        syncing = false
    }
}
