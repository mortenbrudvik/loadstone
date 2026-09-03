import AppKit

@MainActor
final class WindowDirector {
    static let shared = WindowDirector()

    private var originals: [MemoryKey: CGRect] = [:]

    func perform(_ command: WindowCommand) {
        if let window = AXWindow.focused(), let current = window.cocoaFrame {
            apply(command, to: window, current: current)
            return
        }
        if !AccessibilityAuth.isTrusted {
            AccessibilityAuth.requestIfNeeded()
        }
    }

    func snap(_ tile: Tile, window: AXWindow) {
        guard let current = window.cocoaFrame else { return }
        apply(.tile(tile), to: window, current: current)
    }

    private func apply(_ command: WindowCommand, to window: AXWindow, current: CGRect) {
        rememberIfNeeded(window, current: current)

        switch command {
        case .tile(let tile):
            guard let screen = ScreenGeometry.screen(containingCocoaRect: current) else { return }
            window.cocoaFrame = tile.frame(in: screen.visibleFrame)
        case .center:
            guard let screen = ScreenGeometry.screen(containingCocoaRect: current) else { return }
            window.cocoaFrame = Layout.centered(current, in: screen.visibleFrame)
        case .restore:
            if let key = memoryKey(for: window), let original = originals.removeValue(forKey: key) {
                window.cocoaFrame = original
            }
        case .nextDisplay:
            move(window, current: current, delta: 1)
        case .previousDisplay:
            move(window, current: current, delta: -1)
        }
    }

    private func move(_ window: AXWindow, current: CGRect, delta: Int) {
        guard let screen = ScreenGeometry.screen(containingCocoaRect: current),
              let neighbor = ScreenGeometry.neighbor(of: screen, delta: delta) else { return }
        window.cocoaFrame = Layout.mapped(current, from: screen.visibleFrame, to: neighbor.visibleFrame)
    }

    private func rememberIfNeeded(_ window: AXWindow, current: CGRect) {
        guard let key = memoryKey(for: window) else { return }
        if originals[key] == nil {
            originals[key] = current
        }
    }

    private func memoryKey(for window: AXWindow) -> MemoryKey? {
        if let id = window.cgWindowID {
            return .cgWindow(id)
        }
        return .fallback(pid: window.pid, title: window.title)
    }
}

private enum MemoryKey: Hashable {
    case cgWindow(CGWindowID)
    case fallback(pid: pid_t, title: String)
}
