import Foundation

/// The drag-to-snap state machine, kept pure so it can be tested. `EdgeDragMonitor` feeds it
/// mouse events plus the answers to the two questions it cannot answer itself (which window is
/// under the pointer, and where that window is now) and gets back what to preview and what to
/// commit.
///
/// Any left-button drag is a candidate (text selection, sliders, scrollbars, resizes), so the
/// tracker only arms once the window under the pointer has actually moved, which only a
/// title-bar drag does. To keep Accessibility traffic low it resolves the window once, when the
/// pointer has travelled past `threshold`, and re-reads the window's origin only while the
/// pointer is inside a snap zone, the drag is not yet armed, and `originPollInterval` has
/// elapsed since the last read.
struct DragSnapTracker<Window> {
    struct Target: Equatable {
        let tile: Tile
        let display: Display
    }

    /// Pointer travel before a press counts as a drag rather than a click.
    var threshold: CGFloat = 8

    /// Shortest gap between two reads of the dragged window's origin. Every read is a
    /// synchronous AX round trip on the main thread that can block for the AX messaging
    /// timeout, so polling once per event — 120 Hz on a ProMotion trackpad — is what makes a
    /// drag stutter against a slow app. At 20 Hz the drag still arms within a frame or two of
    /// the window actually moving, which is below the threshold of noticing.
    var originPollInterval: TimeInterval = 0.05

    private enum Phase {
        case idle
        case pressed(start: CGPoint)
        /// Past the threshold with a window under the pointer; waiting to see that window move.
        /// `lastPoll` is the event time of the most recent origin read, starting with the
        /// baseline one taken when the threshold was crossed.
        case tracking(window: Window, origin: CGPoint, lastPoll: TimeInterval)
        /// The window moved, so this is a window drag. `target` is the zone under the pointer.
        case armed(window: Window, target: Target?)
    }

    private var phase: Phase = .idle

    mutating func mouseDown(at point: CGPoint) {
        phase = .pressed(start: point)
    }

    /// Feeds a drag event. Returns the tile and display to preview, or nil to hide the preview.
    mutating func mouseDragged(
        to point: CGPoint,
        at time: TimeInterval,
        displays: [Display],
        windowUnderPointer: () -> Window?,
        originOf: (Window) -> CGPoint?
    ) -> Target? {
        switch phase {
        case .idle:
            return nil

        case .pressed(let start):
            guard hypot(point.x - start.x, point.y - start.y) >= threshold else { return nil }
            // The pointer is on the dragged window's title bar, so resolve it here rather than
            // at mouse-down, where every click system-wide would cost an AX round trip.
            guard let window = windowUnderPointer(), let origin = originOf(window) else {
                phase = .idle
                return nil
            }
            phase = .tracking(window: window, origin: origin, lastPoll: time)
            return nil

        case .tracking(let window, let origin, let lastPoll):
            guard let target = Self.target(at: point, in: displays) else { return nil }
            guard time - lastPoll >= originPollInterval else { return nil }
            phase = .tracking(window: window, origin: origin, lastPoll: time)
            guard let now = originOf(window), now != origin else { return nil }
            phase = .armed(window: window, target: target)
            return target

        case .armed(let window, _):
            let target = Self.target(at: point, in: displays)
            phase = .armed(window: window, target: target)
            return target
        }
    }

    /// The window and target to commit when the drag ended inside a zone. Always resets.
    mutating func mouseUp() -> (window: Window, target: Target)? {
        defer { phase = .idle }
        guard case .armed(let window, let target?) = phase else { return nil }
        return (window, target)
    }

    mutating func reset() {
        phase = .idle
    }

    private static func target(at point: CGPoint, in displays: [Display]) -> Target? {
        guard let display = ScreenGeometry.display(containing: point, in: displays),
              let tile = SnapZones.tile(at: point, screenFrame: display.frame) else { return nil }
        return Target(tile: tile, display: display)
    }
}
