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
    /// to where it was before Loadstone first touched it, not to the previous tile. A window
    /// known by a title that a write changes takes its entry along to the new title. Entries are
    /// dropped when their process quits (`forgetWindows(ofProcess:)`) because macOS reuses
    /// window ids and a new window could otherwise inherit a stale memory.
    private var originals: [WindowIdentity: CGRect] = [:]
    /// The tile Loadstone last put each window in, the frame it sent the window to, and where
    /// the window reported itself once there (where it landed), which differs when its app rounds
    /// or caps the size. That is how a second Left or Right Half knows the window is still in
    /// that half when it never fills the tile exactly, and which display a tile or Center works
    /// on while the window is still where it landed. Every frame the window accepts from
    /// Loadstone drops the entry, and a tile then records a new one; a refused frame drops it if
    /// the window moved anyway or its frame can no longer be read, and so does the window's
    /// process quitting, along with `originals`.
    private var placements: [WindowIdentity: Placement] = [:]
    private let displays: () -> [Display]
    /// Takes the info-level lines that say why a half press did or did not carry a window on,
    /// and why a placement went unrecorded.
    private let diagnose: (String) -> Void

    private struct Placement {
        /// The tile that sent the window there: for a continuation, the half it moved into rather
        /// than the one pressed.
        let tile: Tile
        let target: CGRect
        let landed: CGRect
    }

    init(
        displays: @escaping () -> [Display] = { Display.all },
        diagnose: @escaping (String) -> Void = { Log.ax.info("\($0, privacy: .public)") }
    ) {
        self.displays = displays
        self.diagnose = diagnose
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

    /// Runs `command` on `window`. A tile or Center works on the display Loadstone last put the
    /// window on while it is still where it landed, otherwise the one under its centre; Next and
    /// Previous Display move it on from the one under its centre. Left or Right Half on a window
    /// already in that half carries it on to the display beside it.
    @discardableResult
    func perform(_ command: WindowCommand, on window: some MovableWindow) -> CommandOutcome {
        guard let current = window.cocoaFrame else { return .frameUnreadable }
        // Read once for every lookup and passed down: on an AXWindow it is computed through AX
        // calls, with a title read as well when the window id is unavailable. `apply` reads a
        // title-based one again after a write, to record under.
        let key = window.identity
        let displays = self.displays()

        switch command {
        case .tile(let tile):
            guard let display = display(for: current, key: key, in: displays) else { return .noDisplay }
            let target = tile.frame(in: display.visibleFrame)
            // Left or Right Half again on a window already in that half carries it on into the
            // opposite half of the display beside it. With nothing beside it, the half is applied
            // again, which leaves the window where it is, with no beep. A window not in the half
            // is fitted into it, with a line in the log where the press alone does not say why.
            if let continuation = tile.continuation {
                if isPlaced(current, in: target, key: key) {
                    if let beside = ScreenGeometry.adjacent(to: display, toward: continuation.toward, in: displays) {
                        diagnose("\(command.id): carrying on to the display at \(beside.frame)")
                        let onward = continuation.landing.frame(in: beside.visibleFrame)
                        return place(window, key: key, at: onward, by: continuation.landing, from: current).outcome
                    }
                    diagnose("\(command.id): in the half, with no display to the \(continuation.toward) of \(display.frame)")
                } else {
                    return fit(window, key: key, into: tile, at: target, from: current)
                }
            }
            return place(window, key: key, at: target, by: tile, from: current).outcome
        case .center:
            guard let display = display(for: current, key: key, in: displays) else { return .noDisplay }
            return apply(Layout.centered(current, in: display.visibleFrame), to: window, key: key, from: current, remembering: current).outcome
        case .restore:
            // Restore must not record: it would store the current frame and then "restore" to it.
            // The memory is dropped only once the window has actually accepted the old frame, so
            // an app that refuses the write can still be restored on a later attempt.
            guard let key, let original = originals[key] else {
                return .nothingToRestore
            }
            let outcome = apply(original, to: window, key: key, from: current, remembering: nil).outcome
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
        return place(window, key: window.identity, at: tile.frame(in: display.visibleFrame), by: tile, from: current).outcome
    }

    /// Drops everything remembered about the windows of a process that has quit.
    func forgetWindows(ofProcess pid: pid_t) {
        originals = originals.filter { $0.key.pid != pid }
        placements = placements.filter { $0.key.pid != pid }
    }

    /// Moves the window `delta` displays along from the one under its centre, mapping its frame
    /// proportionally. The display Loadstone put it on differs from that one only for a window
    /// held wider or taller than its tile and mostly past that display's edge. Mapped from there,
    /// the window would keep that overhang in proportion: one wider than that display would come
    /// out wider than the display it goes to, which can leave most of it off the desk.
    private func move(_ window: some MovableWindow, key: WindowIdentity?, current: CGRect, delta: Int, in displays: [Display]) -> CommandOutcome {
        guard let display = display(under: current, in: displays),
              let neighbor = ScreenGeometry.neighbor(of: display, delta: delta, in: displays) else { return .noDisplay }
        guard neighbor != display else { return .noOtherDisplay }
        let mapped = Layout.mapped(current, from: display.visibleFrame, to: neighbor.visibleFrame)
        return apply(mapped, to: window, key: key, from: current, remembering: current).outcome
    }

    /// Sends the window to `target`, the frame of `tile`, then records where it actually ended
    /// up, so that pressing the same tile again can tell the window has not moved since. Recorded
    /// only once the window's top-left corner is where it was sent: an app that rounds or caps a
    /// size normally keeps that corner, while one still reporting its old frame has not moved
    /// yet, so a read-back that misses the corner leaves the window with no entry.
    ///
    /// That read-back is the one look this takes, which leaves two cases open, both from an app
    /// that applies the frame late. If the window's old frame already shared the target's
    /// top-left, that old frame is recorded as where it landed. Once Loadstone writes the window
    /// again the entry goes, but put back on exactly that frame by anything else (a title-bar
    /// double-click, a drag), the window is carried on at the next press. A window known by a
    /// title that follows its size is carried on even when a Loadstone tile put it back: the
    /// title read after the write is stale as well, so the entry sits under the old title, which
    /// the next write, looked up by the new one, does not drop. And a window carried on to
    /// another display reads back its old frame, off the target's top-left, so the move goes
    /// unrecorded. A window held wider than its tile keeps its top-left and sticks out to the
    /// right, so one carried left onto a display narrower than itself reaches back over the
    /// display it came from, with its centre there; its next Left Half goes by that display, and
    /// it bounces between the two. Closing either would take watching the window, with an
    /// AXObserver recording where it settles and dropping the entry when it moves anywhere else.
    ///
    /// Returns the outcome and, when a placement was recorded, where the window landed.
    private func place(_ window: some MovableWindow, key: WindowIdentity?, at target: CGRect, by tile: Tile, from current: CGRect) -> (outcome: CommandOutcome, landed: CGRect?) {
        let applied = apply(target, to: window, key: key, from: current, remembering: current)
        guard applied.outcome == .moved, let key = applied.key else { return (applied.outcome, nil) }
        guard let readBack = window.cocoaFrame else {
            diagnose("\(tile.rawValue): could not read the frame back, so the placement is not recorded")
            return (applied.outcome, nil)
        }
        guard readBack.sharesTopLeft(with: target) else {
            diagnose("\(tile.rawValue): read back \(readBack), off the top-left of \(target), so the placement is not recorded")
            return (applied.outcome, nil)
        }
        placements[key] = Placement(tile: tile, target: target, landed: readBack)
        return (applied.outcome, readBack)
    }

    /// Whether a window at `current` is already in the tile whose frame is `target`: it fills the
    /// tile, or it is where it landed the last time Loadstone sent it to this same frame. The
    /// second covers apps that never fill a tile exactly: rounding to a character grid (Terminal,
    /// iTerm2), holding a minimum width, or accepting a size write and ignoring it. A display
    /// change (a new resolution, the Dock moving) changes the tile's frame, so the window is
    /// refitted before it is carried on.
    private func isPlaced(_ current: CGRect, in target: CGRect, key: WindowIdentity?) -> Bool {
        current.isWithinAPoint(of: target)
            || standingPlacement(for: key, at: current)?.target.isWithinAPoint(of: target) == true
    }

    /// Fits a window that is not in the half `tile` into it, at `target`, and logs why it was not
    /// carried on where the press alone does not say. Either the window had a placement by this
    /// same tile that no longer held, because the window had moved since or the display had
    /// changed; or it reads back where it was: a Terminal window Loadstone has not put in the
    /// half since it started, one whose record another command dropped, or a minimum-width
    /// window that Left Third left where Left Half leaves it too, none of which the press moves,
    /// or a window at the half's top-left whose app applies the frame late and still reports the
    /// old one, which moves once the app catches up; or, with no placement standing, it had the
    /// half's top-left corner without filling it, and the fit can be too small to see. A fit the
    /// window visibly takes, from anywhere else or from where another tile put it, needs no
    /// explaining, and a refused one is reported as a refusal.
    private func fit(_ window: some MovableWindow, key: WindowIdentity?, into tile: Tile, at target: CGRect, from current: CGRect) -> CommandOutcome {
        let last = key.flatMap { placements[$0] }
        let hadStandingPlacement = standingPlacement(for: key, at: current) != nil
        let placed = place(window, key: key, at: target, by: tile, from: current)
        guard placed.outcome == .moved else { return placed.outcome }
        if let last, last.tile == tile {
            diagnose("\(tile.rawValue): the last placement no longer held: the window was at \(current), had been sent to \(last.target) and landed at \(last.landed); the tile is now \(target)")
        } else if let landed = placed.landed, landed.isWithinAPoint(of: current) {
            diagnose("\(tile.rawValue): nothing recorded the window at \(current) in this half, so it was fitted into \(target) and read back where it was; that is recorded as in the half, so the next press counts it as there")
        } else if !hadStandingPlacement, current.sharesTopLeft(with: target) {
            diagnose("\(tile.rawValue): the window at \(current) had the top-left of \(target) without filling it, and nothing recorded Loadstone putting it there, so it was fitted into the half rather than carried on")
        }
        return placed.outcome
    }

    /// Writes `frame` to the window at `current` and, once the window has accepted the write,
    /// records `previous` as the frame Restore should return to and drops the window's placement.
    /// A refused write records nothing, and keeps the placement only if the window is seen to
    /// have stayed put (below). Recording afterwards rather than before is what keeps a refused
    /// frame, or a command that never ran at all, from leaving behind a restore entry that a
    /// later Restore would act on.
    ///
    /// The placement said where a tile left the window, which has now been sent somewhere else;
    /// for a tile, `place` records a fresh one. After any other write, a step-sized or
    /// minimum-width window brought back to where it landed (a Next then Previous Display round
    /// trip, say) takes one refit press before it carries on. That is the price of never
    /// carrying a window on from a record that another Loadstone write has made stale, such as
    /// the old frame an app that applies frames late reads back, which Restore returns the
    /// window to.
    ///
    /// A refused write keeps the placement while the window is still at `current`. Part of the
    /// write can take before the refusal, though: AXWindow sets the size before the position, so
    /// an app that takes the size and then refuses the position, or times out on it, leaves the
    /// window resized at its old top-left, which can be exactly a stale frame recorded as where
    /// it landed. So after a refusal the placement is kept only if the frame, read again, is
    /// still within a point of `current`.
    ///
    /// Returns the outcome and the key the window goes by after the write, which the Restore
    /// frame here and a tile's placement in `place` are recorded under. That is `key`, except
    /// that a title-based one is read again once the write is accepted (`keyAfterWrite`). The
    /// placement dropped is still the one under `key`, which the window was looked up by, and a
    /// Restore frame recorded under `key` moves across to the new one.
    private func apply(_ frame: CGRect, to window: some MovableWindow, key: WindowIdentity?, from current: CGRect, remembering previous: CGRect?) -> (outcome: CommandOutcome, key: WindowIdentity?) {
        let error = window.setCocoaFrame(frame)
        guard error == .success else {
            if let key, placements[key] != nil, window.cocoaFrame?.isWithinAPoint(of: current) != true {
                placements.removeValue(forKey: key)
            }
            return (.rejected(error), key)
        }
        if let key { placements.removeValue(forKey: key) }
        let settled = keyAfterWrite(key, of: window)
        if let previous { rememberIfNeeded(previous, for: settled, lookedUpBy: key) }
        return (.moved, settled)
    }

    /// The key the next command will look `window` up by, once a write under `key` has been
    /// accepted. A window id cannot change with a write, but a title can: Terminal's default
    /// title carries the window's size in character cells, so what is recorded under the title
    /// from before a resize would never be found again.
    private func keyAfterWrite(_ key: WindowIdentity?, of window: some MovableWindow) -> WindowIdentity? {
        guard case .fallback = key else { return key }
        return window.identity
    }

    /// Records `frame` under `key`, the key the window goes by after the write, as where Restore
    /// returns it, unless something is recorded there already. A frame recorded under `oldKey`,
    /// the one the window was looked up by, moves across instead: the two differ only for a
    /// title-based identity whose write renamed the window, and that frame is the one the window's
    /// first command recorded.
    private func rememberIfNeeded(_ frame: CGRect, for key: WindowIdentity?, lookedUpBy oldKey: WindowIdentity?) {
        guard let key, originals[key] == nil else { return }
        if let oldKey, let first = originals.removeValue(forKey: oldKey) {
            originals[key] = first
        } else {
            originals[key] = frame
        }
    }

    /// The display a tile or Center works on for a window at `frame`. While the window is still
    /// where Loadstone last put it, that is the display holding the frame it was sent to: a
    /// window held wider than that display spills onto the next, and its centre can land there,
    /// which would send the next half from the wrong display and bounce the window between the
    /// two. Otherwise the display under its centre.
    private func display(for frame: CGRect, key: WindowIdentity?, in displays: [Display]) -> Display? {
        if let placement = standingPlacement(for: key, at: frame),
           let placedOn = ScreenGeometry.display(containing: placement.target, in: displays) {
            return placedOn
        }
        return display(under: frame, in: displays)
    }

    /// The display under the centre of a window at `frame`, or the primary display when the
    /// window is off every display (after a disconnect) so it can still be brought back.
    private func display(under frame: CGRect, in displays: [Display]) -> Display? {
        ScreenGeometry.display(containing: frame, in: displays) ?? displays.first
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
