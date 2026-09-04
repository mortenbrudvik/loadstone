import AppKit

/// Converts between AppKit screen coordinates (origin at the bottom-left of the *primary*
/// display, `NSScreen.screens[0]`, y up) and Accessibility / CoreGraphics coordinates
/// (origin at the top-left of that same display, y down). Both share the x axis and the
/// primary display's height, so the flip `y' = primaryMaxY - y - height` is its own inverse,
/// which is why `cocoaRect(fromAX:)` and `axRect(fromCocoa:)` are the same formula.
///
/// "Primary" is NOT `NSScreen.main` (the screen holding the key window). Using `.main` here
/// would corrupt every conversion whenever the key window sits on a secondary display.
///
/// Every function takes its inputs explicitly so it is pure and testable; the live values come
/// from `primaryMaxY` and `Display.all`.
enum ScreenGeometry {
    /// The primary display's height, which is also the Cocoa y of its top edge. Nil when no
    /// display is attached, in which case no coordinate conversion is meaningful.
    static var primaryMaxY: CGFloat? {
        NSScreen.screens.first?.frame.maxY
    }

    static func cocoaRect(fromAX ax: CGRect, primaryMaxY: CGFloat) -> CGRect {
        flipped(ax, primaryMaxY: primaryMaxY)
    }

    static func axRect(fromCocoa cocoa: CGRect, primaryMaxY: CGFloat) -> CGRect {
        flipped(cocoa, primaryMaxY: primaryMaxY)
    }

    static func axPoint(fromCocoa cocoa: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: cocoa.x, y: primaryMaxY - cocoa.y)
    }

    /// The display whose frame contains `point`. Exact containment wins, so a point on the
    /// edge shared by two displays goes to the one whose frame includes it. A 1pt tolerance
    /// then catches the pointer resting exactly on the top or right edge of the outermost
    /// display, which `CGRect.contains` excludes. Nil when the point is on no display.
    static func display(containing point: CGPoint, in displays: [Display] = Display.all) -> Display? {
        displays.first { $0.frame.contains(point) }
            ?? displays.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    /// The display under the centre of `rect`. A window straddling two displays belongs to
    /// the one holding more than half of it.
    static func display(containing rect: CGRect, in displays: [Display] = Display.all) -> Display? {
        display(containing: CGPoint(x: rect.midX, y: rect.midY), in: displays)
    }

    /// The display `delta` steps away in reading order (left to right by x origin; displays
    /// stacked at the same x go top to bottom), wrapping at both ends. Not AppKit's order,
    /// which puts the primary first and the rest in connection order, so with three or more
    /// screens Next Display would otherwise jump around the desk. With one display this is the
    /// display itself, so Next/Previous Display becomes a no-op. Nil if `display` is not in the
    /// list (unplugged between lookup and use).
    static func neighbor(of display: Display, delta: Int, in displays: [Display] = Display.all) -> Display? {
        let ordered = displays.sorted(by: readingOrder)
        guard let index = ordered.firstIndex(of: display) else { return nil }
        return ordered[(index + delta).modulo(ordered.count)]
    }

    private static func readingOrder(_ a: Display, _ b: Display) -> Bool {
        if a.frame.minX != b.frame.minX { return a.frame.minX < b.frame.minX }
        return a.frame.maxY > b.frame.maxY
    }

    private static func flipped(_ rect: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryMaxY - rect.minY - rect.height, width: rect.width, height: rect.height)
    }
}

private extension Int {
    /// Euclidean modulo: always in `0..<modulus`, unlike `%`, which keeps the sign of `self`.
    func modulo(_ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let r = self % modulus
        return r >= 0 ? r : r + modulus
    }
}
