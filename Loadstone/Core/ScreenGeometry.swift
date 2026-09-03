import AppKit

enum ScreenGeometry {
    /// Cocoa (bottom-left) ↔ Accessibility (top-left, relative to the main screen).
    static func cocoaRect(fromAX ax: CGRect) -> CGRect {
        let top = primaryMaxY
        return CGRect(x: ax.origin.x, y: top - ax.origin.y - ax.height, width: ax.width, height: ax.height)
    }

    static func axRect(fromCocoa cocoa: CGRect) -> CGRect {
        let top = primaryMaxY
        return CGRect(x: cocoa.origin.x, y: top - cocoa.origin.y - cocoa.height, width: cocoa.width, height: cocoa.height)
    }

    static func axPoint(fromCocoa cocoa: CGPoint) -> CGPoint {
        CGPoint(x: cocoa.x, y: primaryMaxY - cocoa.y)
    }

    static func screen(containingCocoa point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
            ?? NSScreen.screens.first { $0.frame.contains(point) }
            ?? NSScreen.main
    }

    static func screen(containingCocoaRect rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return screen(containingCocoa: center)
    }

    static func neighbor(of screen: NSScreen, delta: Int) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = screens.firstIndex(where: { $0 === screen }) else { return screens.first }
        let next = (index + delta).modulo(screens.count)
        return screens[next]
    }

    private static var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }
}

private extension Int {
    func modulo(_ modulus: Int) -> Int {
        guard modulus > 0 else { return 0 }
        let r = self % modulus
        return r >= 0 ? r : r + modulus
    }
}
