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
    private let displays: () -> [Display]

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

    /// Runs `command` on `window`, using the display under the window's centre.
    @discardableResult
    func perform(_ command: WindowCommand, on window: some MovableWindow) -> CommandOutcome {
        guard let current = window.cocoaFrame else { return .frameUnreadable }
        let displays = self.displays()

        switch command {
        case .tile(let tile):
            guard let display = display(for: current, in: displays) else { return .noDisplay }
            return apply(tile.frame(in: display.visibleFrame), to: window, remembering: current)
        case .center:
            guard let display = display(for: current, in: displays) else { return .noDisplay }
            return apply(Layout.centered(current, in: display.visibleFrame), to: window, remembering: current)
        case .restore:
            // Restore must not record: it would store the current frame and then "restore" to it.
            // The memory is dropped only once the window has actually accepted the old frame, so
            // an app that refuses the write can still be restored on a later attempt.
            guard let key = window.identity, let original = originals[key] else {
                return .nothingToRestore
            }
            let outcome = apply(original, to: window, remembering: nil)
            if outcome == .moved { originals.removeValue(forKey: key) }
            return outcome
        case .nextDisplay:
            return move(window, current: current, delta: 1, in: displays)
        case .previousDisplay:
            return move(window, current: current, delta: -1, in: displays)
        }
    }

    /// Snaps `window` into `tile` on `display`: the display the drag gesture ended on, which is
    /// not necessarily the one under the window's centre when a wide window straddles two.
    @discardableResult
    func snap(_ tile: Tile, window: some MovableWindow, on display: Display) -> CommandOutcome {
        guard let current = window.cocoaFrame else { return .frameUnreadable }
        return apply(tile.frame(in: display.visibleFrame), to: window, remembering: current)
    }

    /// Drops restore memory for every window of a process that has quit.
    func forgetWindows(ofProcess pid: pid_t) {
        originals = originals.filter { $0.key.pid != pid }
    }

    private func move(_ window: some MovableWindow, current: CGRect, delta: Int, in displays: [Display]) -> CommandOutcome {
        guard let display = display(for: current, in: displays),
              let neighbor = ScreenGeometry.neighbor(of: display, delta: delta, in: displays) else { return .noDisplay }
        guard neighbor != display else { return .noOtherDisplay }
        return apply(Layout.mapped(current, from: display.visibleFrame, to: neighbor.visibleFrame), to: window, remembering: current)
    }

    /// Writes `frame`, then records `previous` as the frame Restore should return to — but only
    /// once the window has accepted the write. Recording afterwards rather than before is what
    /// keeps a refused frame, or a command that never ran at all, from leaving behind a restore
    /// entry that a later Restore would act on.
    private func apply(_ frame: CGRect, to window: some MovableWindow, remembering previous: CGRect?) -> CommandOutcome {
        let error = window.setCocoaFrame(frame)
        guard error == .success else { return .rejected(error) }
        if let previous { rememberIfNeeded(window, current: previous) }
        return .moved
    }

    private func rememberIfNeeded(_ window: some MovableWindow, current: CGRect) {
        guard let key = window.identity, originals[key] == nil else { return }
        originals[key] = current
    }

    /// The display under the window's centre, or the primary display when the window is off
    /// every display (after a disconnect) so it can still be brought back.
    private func display(for frame: CGRect, in displays: [Display]) -> Display? {
        ScreenGeometry.display(containing: frame, in: displays) ?? displays.first
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
