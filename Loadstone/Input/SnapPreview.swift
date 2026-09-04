import AppKit

/// The translucent blue rectangle shown over the tile a drag will snap to.
@MainActor
final class SnapPreview {
    private var window: NSWindow?

    /// Shows the preview over `frame` (Cocoa space), inset a little so it reads as a preview
    /// rather than as the window itself.
    func show(frame: CGRect) {
        let panel = ensureWindow()
        panel.setFrame(frame.insetBy(dx: 6, dy: 6), display: true)
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
        // Borderless, click-through overlay: canJoinAllSpaces + fullScreenAuxiliary so it shows on
        // the current Space and over full-screen apps; .floating keeps it above the dragged
        // window; ignoresMouseEvents so it never captures the drag it is previewing. It is only
        // ever ordered out, never closed, so the default isReleasedWhenClosed is harmless.
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
        // 1pt inside bounds so the 2pt stroke stays fully within the window.
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.systemBlue.withAlphaComponent(0.22).setFill()
        path.fill()
        NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
