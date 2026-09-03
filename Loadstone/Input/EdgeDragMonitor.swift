import AppKit

@MainActor
final class EdgeDragMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var dragStart: CGPoint?
    private var draggedWindow: AXWindow?
    private var activeTile: Tile?
    private var activeScreen: NSScreen?
    private var preview = SnapPreview()
    private let dragThreshold: CGFloat = 8

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.enqueue(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.enqueue(event)
            return event
        }
    }

    /// Capture the pointer location immediately; hop to the main actor with that point.
    private nonisolated func enqueue(_ event: NSEvent) {
        let type = event.type
        let point = NSEvent.mouseLocation
        DispatchQueue.main.async { [weak self] in
            self?.handle(type: type, at: point)
        }
    }

    private func handle(type: NSEvent.EventType, at point: CGPoint) {
        guard AppSettings.shared.dragSnappingEnabled else {
            reset()
            return
        }

        switch type {
        case .leftMouseDown:
            dragStart = point
            draggedWindow = AXWindow.atCocoaPoint(point) ?? AXWindow.focused()
            activeTile = nil
            activeScreen = nil
        case .leftMouseDragged:
            considerSnap(at: point)
        case .leftMouseUp:
            commit()
        default:
            break
        }
    }

    private func considerSnap(at point: CGPoint) {
        guard let dragStart, hypot(point.x - dragStart.x, point.y - dragStart.y) >= dragThreshold else { return }
        guard let screen = ScreenGeometry.screen(containingCocoa: point) else {
            preview.hide()
            activeTile = nil
            activeScreen = nil
            return
        }
        let tile = SnapZones.tile(at: point, screenFrame: screen.frame)
        activeTile = tile
        activeScreen = screen
        if let tile {
            preview.show(tile, on: screen)
        } else {
            preview.hide()
        }
    }

    private func commit() {
        defer { reset() }
        guard let tile = activeTile else { return }
        let window = draggedWindow ?? AXWindow.focused()
        guard let window else { return }
        WindowDirector.shared.snap(tile, window: window)
    }

    private func reset() {
        dragStart = nil
        draggedWindow = nil
        activeTile = nil
        activeScreen = nil
        preview.hide()
    }
}
