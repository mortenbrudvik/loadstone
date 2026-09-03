import AppKit

@MainActor
final class SnapPreview {
    private var window: NSWindow?

    func show(_ tile: Tile, on screen: NSScreen) {
        let frame = tile.frame(in: screen.visibleFrame).insetBy(dx: 6, dy: 6)
        let panel = ensureWindow()
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func ensureWindow() -> NSWindow {
        if let window { return window }
        let panel = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = PreviewFillView()
        window = panel
        return panel
    }
}

private final class PreviewFillView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
