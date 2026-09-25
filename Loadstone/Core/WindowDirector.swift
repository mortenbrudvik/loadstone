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
    /// It also decides which display a window still sitting where it landed is on. Every frame
    /// the window accepts from Loadstone drops the entry, and a tile then records a new one; the
    /// window's process quitting drops it too, along with `originals`.
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
            // opposite half of the display beside it. With nothing beside it, the half is applied
            // again, which leaves the window where it is, with no beep.
            if let continuation = tile.continuation, isPlaced(current, in: target, key: key, for: command) {
                if let beside = ScreenGeometry.adjacent(to: display, toward: continuation.toward, in: displays) {
                    Log.ax.info("\(command.id, privacy: .public): carrying on to the display at \(String(describing: beside.frame), privacy: .public)")
                    let landing = continuation.landing.frame(in: beside.visibleFrame)
                    return place(window, key: key, at: landing, from: current, for: command)
                }
                Log.ax.info("\(command.id, privacy: .public): in the half, with no display to the \(String(describing: continuation.toward), privacy: .public) of \(String(describing: display.frame), privacy: .public)")
            }
            return place(window, key: key, at: target, from: current, for: command)
        case .center:
            guard let display = display(for: current, key: key, in: displays) else { return .noDisplay }
            return apply(Layout.centered(current, in: display.visibleFrame), to: window, key: key, from: current, remembering: current)
        case .restore:
            // Restore must not record: it would store the current frame and then "restore" to it.
            // The memory is dropped only once the window has actually accepted the old frame, so
            // an app that refuses the write can still be restored on a later attempt.
            guard let key, let original = originals[key] else {
                return .nothingToRestore
            }
            let outcome = apply(original, to: window, key: key, from: current, remembering: nil)
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
        return place(window, key: window.identity, at: tile.frame(in: display.visibleFrame), from: current, for: .tile(tile))
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
        return apply(mapped, to: window, key: key, from: current, remembering: current)
    }

    /// Sends the window to `target`, a tile's frame, then records where it actually ended up, so
    /// that pressing the same tile again can tell the window has not moved since. Recorded only
    /// once the window's top-left corner is where it was sent: an app that rounds or caps a size
    /// normally keeps that corner, while one still reporting its old frame has not moved yet, so
    /// a read-back that misses the corner leaves the window with no entry.
    ///
    /// An app that applies the frame late, and whose old frame already shared the target's
    /// top-left, reads back that old frame and has it recorded. Once Loadstone moves the window
    /// again the entry goes; but returned to exactly that frame by anything else (a title-bar
    /// double-click, a drag), the window is carried on at the next press. Closing that would
    /// take watching the window, with an AXObserver dropping the entry when it moves anywhere
    /// but its landing.
    private func place(_ window: some MovableWindow, key: WindowIdentity?, at target: CGRect, from current: CGRect, for command: WindowCommand) -> CommandOutcome {
        let outcome = apply(target, to: window, key: key, from: current, remembering: current)
        guard outcome == .moved, let key else { return outcome }
        let readBack = window.cocoaFrame
        if let readBack, readBack.sharesTopLeft(with: target) {
            placements[key] = Placement(target: target, landed: readBack)
        } else {
            Log.ax.info("\(command.id, privacy: .public): read back \(readBack.map(String.init(describing:)) ?? "no frame", privacy: .public), off the top-left of \(String(describing: target), privacy: .public), so the placement is not recorded")
        }
        return outcome
    }

    /// Whether a window at `current` is already in the tile whose frame is `target`: it fills the
    /// tile, or it is where it landed the last time Loadstone sent it to this same frame. The
    /// second covers apps that never fill a tile exactly: rounding to a character grid (Terminal,
    /// iTerm2), holding a minimum width, or accepting a size write and ignoring it. A display
    /// change (a new resolution, the Dock moving) changes the tile's frame, so the window is
    /// refitted before it is carried on.
    private func isPlaced(_ current: CGRect, in target: CGRect, key: WindowIdentity?, for command: WindowCommand) -> Bool {
        if current.isWithinAPoint(of: target) { return true }
        if standingPlacement(for: key, at: current)?.target.isWithinAPoint(of: target) == true { return true }
        guard let key, let last = placements[key] else { return false }
        Log.ax.info("\(command.id, privacy: .public): last placement does not match: the window is at \(String(describing: current), privacy: .public), was sent to \(String(describing: last.target), privacy: .public) and landed at \(String(describing: last.landed), privacy: .public); the tile is now \(String(describing: target), privacy: .public)")
        return false
    }

    /// Writes `frame` to the window at `current`, then records `previous` as the frame Restore
    /// should return to and drops the window's placement — but only once the window has accepted
    /// the write. Recording afterwards rather than before is what keeps a refused frame, or a
    /// command that never ran at all, from leaving behind a restore entry that a later Restore
    /// would act on.
    ///
    /// The placement said where a tile left the window, which has now been sent somewhere else;
    /// for a tile, `place` records a fresh one. After any other write, a step-sized or
    /// minimum-width window brought back to where it landed (a Next then Previous Display round
    /// trip, say) takes one refit press before it carries on. That is the price of never
    /// carrying a window on from a stale record, such as the old frame an app that applies
    /// frames late reads back, which Restore returns the window to.
    ///
    /// A refused write keeps the placement while the window is still at `current`. Part of the
    /// write can take before the refusal, though: AXWindow sets the size before the position, so
    /// an app that takes the size and then refuses the position, or times out on it, leaves the
    /// window resized at its old top-left, which can be exactly a stale frame recorded as where
    /// it landed. So a refusal reads the frame again and drops the placement unless the window is
    /// still within a point of `current`.
    private func apply(_ frame: CGRect, to window: some MovableWindow, key: WindowIdentity?, from current: CGRect, remembering previous: CGRect?) -> CommandOutcome {
        let error = window.setCocoaFrame(frame)
        guard error == .success else {
            if let key, placements[key] != nil, window.cocoaFrame?.isWithinAPoint(of: current) != true {
                placements.removeValue(forKey: key)
            }
            return .rejected(error)
        }
        if let key { placements.removeValue(forKey: key) }
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
        if let placement = standingPlacement(for: key, at: frame),
           let placedOn = ScreenGeometry.display(containing: placement.target, in: displays) {
            return placedOn
        }
        return ScreenGeometry.display(containing: frame, in: displays) ?? displays.first
    }

    /// The window's placement while the window at `frame` is still where it landed, to within a
    /// point; nil once something has moved or resized it since.
    private func standingPlacement(for key: WindowIdentity?, at frame: CGRect) -> Placement? {
        guard let key, let placement = placements[key], frame.isWithinAPoint(of: placement.landed) else { return nil }
        return placement
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
    /// half it carries to another display misses that display's half where a width is odd: by
    /// half a point from an even width onto an odd one, and from an odd width W1 by
    /// W2 / (2 * W1) onto an even W2 (over a point once W2 > 2 * W1) and by
    /// |W2 / (2 * W1) - 1/2| onto an odd W2 (over a point once W2 > 3 * W1). Over a point, the
    /// next press refits the window instead of carrying it on.
    func isWithinAPoint(of other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1 && abs(maxX - other.maxX) <= 1
            && abs(minY - other.minY) <= 1 && abs(maxY - other.maxY) <= 1
    }

    /// Top-left corners within a point of each other. Cocoa space, so the top is `maxY`.
    func sharesTopLeft(with other: CGRect) -> Bool {
        abs(minX - other.minX) <= 1 && abs(maxY - other.maxY) <= 1
    }
}
