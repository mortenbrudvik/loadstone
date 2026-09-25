import AppKit

/// What became of a command, so callers can log it and give the user a cue.
enum CommandOutcome: Equatable {
    case moved
    /// The window's frame could not be read, so nothing was attempted.
    case frameUnreadable
    /// No display is attached.
    case noDisplay
    /// Next/Previous Display with only one display attached.
    case noOtherDisplay
    /// Restore was asked for a window Loadstone has not moved (or has already restored).
    case nothingToRestore
    /// The app refused the frame (fixed-size window, hung app, Accessibility disabled).
    case rejected(AXError)
}

@MainActor
final class WindowDirector {
    static let shared = WindowDirector()

    /// Pre-Loadstone frame per window. Recorded on the first command of any kind (tile, center,
    /// display move), never overwritten, removed by `.restore`, so Restore returns the window
    /// to where it was before Loadstone first touched it, not to the previous tile. Entries are
    /// dropped when their process quits (`forgetWindows(ofProcess:)`) because macOS reuses
    /// window ids and a new window could otherwise inherit a stale memory.
    private var originals: [WindowIdentity: CGRect] = [:]
    /// The tile frame Loadstone last sent each window to, and where the window reported itself
    /// once there, which differs when its app rounds or caps the size. That is how a second Left
    /// or Right Half knows the window is still in that half when it never fills the tile exactly.
    /// It also decides which display a window still sitting where it landed is on. The next tile
    /// replaces the entry; Restore, Center and a display move drop it, and so does the window's
    /// process quitting, along with `originals`.
    private var placements: [WindowIdentity: Placement] = [:]
    private let displays: () -> [Display]

    private struct Placement {
        let target: CGRect
        let landed: CGRect
    }

    init(displays: @escaping () -> [Display] = { Display.all }) {
        self.displays = displays
    }

    /// Runs `command` on the frontmost app's focused window and tells the user when it can't.
    func perform(_ command: WindowCommand) {
        switch AXWindow.focusedWindow() {
        case .success(let window):
            let outcome = perform(command, on: window)
            report(outcome, for: command, pid: window.pid)
        case .failure(.axError(.apiDisabled)):
            // The real call is the authority. AXIsProcessTrusted can say yes while every call
            // still fails until the app relaunches, which is exactly the state the relaunch
            // alert exists for.
            Log.ax.notice("\(command.id, privacy: .public): Accessibility API disabled")
            AccessibilityAuth.requestIfNeeded()
        case .failure(let reason):
            Log.ax.notice("\(command.id, privacy: .public) skipped: \(String(describing: reason), privacy: .public)")
            NSSound.beep()
            if !AccessibilityAuth.isTrusted {
                AccessibilityAuth.requestIfNeeded()
            }
        }
    }

    /// Runs `command` on `window`, on the display it is on: the one Loadstone last put it on while
    /// it is still where it landed, otherwise the one under its centre. Left or Right Half on a
    /// window already in that half carries it on to the display beside it.
    @discardableResult
    func perform(_ command: WindowCommand, on window: some MovableWindow) -> CommandOutcome {
        guard let current = window.cocoaFrame else { return .frameUnreadable }
        // Read once and passed down: on an AXWindow it is computed through AX calls, with a
        // title read as well when the window id is unavailable.
        let key = window.identity
        let displays = self.displays()

        switch command {
        case .tile(let tile):
            guard let display = display(for: current, key: key, in: displays) else { return .noDisplay }
            let target = tile.frame(in: display.visibleFrame)
            // Left or Right Half again on a window already in that half carries it on into the
            // opposite half of the display beside it. With nothing beside it, it stays put.
            if let continuation = tile.continuation,
               isPlaced(current, in: target, key: key),
               let beside = ScreenGeometry.adjacent(to: display, toward: continuation.toward, in: displays) {
                return place(window, key: key, at: continuation.landing.frame(in: beside.visibleFrame), remembering: current)
            }
            return place(window, key: key, at: target, remembering: current)
        case .center:
            guard let display = display(for: current, key: key, in: displays) else { return .noDisplay }
            return relocate(window, key: key, to: Layout.centered(current, in: display.visibleFrame), remembering: current)
        case .restore:
            // Restore must not record: it would store the current frame and then "restore" to it.
            // The memory is dropped only once the window has actually accepted the old frame, so
            // an app that refuses the write can still be restored on a later attempt.
            guard let key, let original = originals[key] else {
                return .nothingToRestore
            }
            let outcome = relocate(window, key: key, to: original, remembering: nil)
            if outcome == .moved { originals.removeValue(forKey: key) }
            return outcome
        case .nextDisplay:
            return move(window, key: key, current: current, delta: 1, in: displays)
        case .previousDisplay:
            return move(window, key: key, current: current, delta: -1, in: displays)
        }
    }

    /// Snaps `window` into `tile` on `display`: the display the drag gesture ended on, which is
    /// not necessarily the one under the window's centre when a wide window straddles two.
    @discardableResult
    func snap(_ tile: Tile, window: some MovableWindow, on display: Display) -> CommandOutcome {
        guard let current = window.cocoaFrame else { return .frameUnreadable }
        return place(window, key: window.identity, at: tile.frame(in: display.visibleFrame), remembering: current)
    }

    /// Drops everything remembered about the windows of a process that has quit.
    func forgetWindows(ofProcess pid: pid_t) {
        originals = originals.filter { $0.key.pid != pid }
        placements = placements.filter { $0.key.pid != pid }
    }

    private func move(_ window: some MovableWindow, key: WindowIdentity?, current: CGRect, delta: Int, in displays: [Display]) -> CommandOutcome {
        guard let display = display(for: current, key: key, in: displays),
              let neighbor = ScreenGeometry.neighbor(of: display, delta: delta, in: displays) else { return .noDisplay }
        guard neighbor != display else { return .noOtherDisplay }
        let mapped = Layout.mapped(current, from: display.visibleFrame, to: neighbor.visibleFrame)
        return relocate(window, key: key, to: mapped, remembering: current)
    }

    /// Writes a frame that is not a tile (Center, Restore, a display move) and, once the window
    /// accepts it, drops the window's placement. The placement says where a tile put the window;
    /// once Loadstone has moved it anywhere else it can only mislead, most of all when it holds
    /// a stale read-back that the window can later be put back on.
    private func relocate(_ window: some MovableWindow, key: WindowIdentity?, to frame: CGRect, remembering previous: CGRect?) -> CommandOutcome {
        let outcome = apply(frame, to: window, key: key, remembering: previous)
        if outcome == .moved, let key { placements.removeValue(forKey: key) }
        return outcome
    }

    /// Sends the window to `target`, a tile's frame, then records where it actually ended up, so
    /// that pressing the same tile again can tell the window has not moved since. Recorded only
    /// once the window's top-left corner is where it was sent: an app that rounds or caps a size
    /// keeps that corner, while one still reporting its old frame has not moved yet.
    ///
    /// An app that applies the frame late, and whose old frame already shared the target's
    /// top-left, reads back that old frame and has it recorded. Once Loadstone moves the window
    /// again the entry goes; but returned to exactly that frame by anything else (a title-bar
    /// double-click, a drag), the window is carried on at the next press. Closing that would
    /// take watching the window, with an AXObserver dropping the entry when it moves anywhere
    /// but its landing.
    private func place(_ window: some MovableWindow, key: WindowIdentity?, at target: CGRect, remembering previous: CGRect) -> CommandOutcome {
        let outcome = apply(target, to: window, key: key, remembering: previous)
        guard outcome == .moved, let key else { return outcome }
        if let landed = window.cocoaFrame, landed.sharesTopLeft(with: target) {
            placements[key] = Placement(target: target, landed: landed)
        } else {
            placements.removeValue(forKey: key)
        }
        return outcome
    }

    /// Whether a window at `current` is already in the tile whose frame is `target`: it fills the
    /// tile, or it is where it landed the last time Loadstone sent it to this same frame. The
    /// second covers apps that never fill a tile exactly, rounding to a character grid (Terminal,
    /// iTerm2) or holding a minimum or fixed width. A display change (a new resolution, the Dock
    /// moving) changes the tile's frame, so the window is refitted before it is carried on.
    private func isPlaced(_ current: CGRect, in target: CGRect, key: WindowIdentity?) -> Bool {
        if current.isWithinAPoint(of: target) { return true }
        guard let key, let last = placements[key] else { return false }
        return last.target.isWithinAPoint(of: target) && current.isWithinAPoint(of: last.landed)
    }

    /// Writes `frame`, then records `previous` as the frame Restore should return to — but only
    /// once the window has accepted the write. Recording afterwards rather than before is what
    /// keeps a refused frame, or a command that never ran at all, from leaving behind a restore
    /// entry that a later Restore would act on.
    private func apply(_ frame: CGRect, to window: some MovableWindow, key: WindowIdentity?, remembering previous: CGRect?) -> CommandOutcome {
        let error = window.setCocoaFrame(frame)
        guard error == .success else { return .rejected(error) }
        if let previous { rememberIfNeeded(previous, for: key) }
        return .moved
    }

    private func rememberIfNeeded(_ frame: CGRect, for key: WindowIdentity?) {
        guard let key, originals[key] == nil else { return }
        originals[key] = frame
    }

    /// The display a window at `frame` is on. While it is still where Loadstone last put it, that
    /// is the display holding the frame it was sent to: a window held wider than that display
    /// spills onto the next, and its centre can land there, which would send the next command
    /// from the wrong display. Otherwise the display under the window's centre, or the primary
    /// display when the window is off every display (after a disconnect) so it can still be
    /// brought back.
    private func display(for frame: CGRect, key: WindowIdentity?, in displays: [Display]) -> Display? {
        if let key, let last = placements[key], frame.isWithinAPoint(of: last.landed),
           let placedOn = ScreenGeometry.display(containing: last.target, in: displays) {
            return placedOn
        }
        return ScreenGeometry.display(containing: frame, in: displays) ?? displays.first
    }

    private func report(_ outcome: CommandOutcome, for command: WindowCommand, pid: pid_t?) {
        let pid = pid ?? 0
        switch outcome {
        case .moved:
            break
        case .rejected(let error):
            Log.ax.error("\(command.id, privacy: .public): window of pid \(pid) rejected the frame (AXError \(error.rawValue))")
            NSSound.beep()
        case .frameUnreadable:
            Log.ax.error("\(command.id, privacy: .public): could not read the frame of a window of pid \(pid)")
            NSSound.beep()
        case .noDisplay:
            Log.ax.error("\(command.id, privacy: .public): no display attached")
            NSSound.beep()
        case .noOtherDisplay:
            Log.ax.notice("\(command.id, privacy: .public): only one display attached")
            NSSound.beep()
        case .nothingToRestore:
            Log.ax.notice("\(command.id, privacy: .public): nothing remembered for a window of pid \(pid)")
            NSSound.beep()
        }
    }
}

private extension CGRect {
    /// Every edge within a point of `other`'s. Next Display maps a window proportionally, so a
    /// half carried onto a width that does not divide by 2 lands a fraction of a point off.
    func isWithinAPoint(of other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1 && abs(maxX - other.maxX) <= 1
            && abs(minY - other.minY) <= 1 && abs(maxY - other.maxY) <= 1
    }

    /// Top-left corners within a point of each other. Cocoa space, so the top is `maxY`.
    func sharesTopLeft(with other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1 && abs(maxY - other.maxY) <= 1
    }
}
