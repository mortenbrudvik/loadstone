import AppKit

/// A snapshot of one attached screen in Cocoa coordinates: the full frame, and the frame
/// minus menu bar and dock. A plain value so layout and multi-display logic can be exercised
/// in tests without an `NSScreen`, which cannot be fabricated.
struct Display: Equatable, Sendable {
    let frame: CGRect
    let visibleFrame: CGRect

    init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    init(_ screen: NSScreen) {
        self.init(frame: screen.frame, visibleFrame: screen.visibleFrame)
    }

    /// Every attached display, primary first, in the order AppKit reports them.
    /// Empty while all displays are asleep or unplugged.
    static var all: [Display] {
        NSScreen.screens.map(Display.init)
    }
}
