import AppKit
import KeyboardShortcuts

/// Registers one global hotkey per `WindowCommand`. The library registers them through Carbon
/// `RegisterEventHotKey`, so they fire while any app is frontmost and need no Input Monitoring
/// permission, only Accessibility for the window moves that follow.
@MainActor
final class HotkeyCenter {
    private let director: WindowDirector
    private var started = false

    init(director: WindowDirector = .shared) {
        self.director = director
    }

    /// Safe to call more than once: the library keeps handlers globally, so registering twice
    /// would move every window twice per key press.
    func start() {
        guard !started else { return }
        started = true
        for command in WindowCommand.all {
            let name = command.hotkeyName
            // Fires on release, so the window moves once the chord is let go rather than while
            // the modifiers are still held. The library's closure is not actor-isolated; hop
            // back to the main actor for the AX work.
            KeyboardShortcuts.onKeyUp(for: name) { [director] in
                Task { @MainActor in
                    director.perform(command)
                }
            }
        }
        logBindings()
    }

    /// The library swallows Carbon registration failures (it prints to stdout, which an
    /// LSUIElement app discards, and still records the shortcut as registered), so the best
    /// diagnostic available is the effective binding per command at startup.
    private func logBindings() {
        for command in WindowCommand.all {
            let shortcut = KeyboardShortcuts.getShortcut(for: command.hotkeyName)
            Log.hotkeys.info("\(command.id, privacy: .public): \(shortcut.map(String.init(describing:)) ?? "unbound", privacy: .public)")
        }
    }
}
