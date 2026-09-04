import ApplicationServices

/// How `WindowDirector` recognises a window across commands, so Restore can find its memory.
enum WindowIdentity: Hashable, Sendable {
    /// Stable for the window's lifetime. macOS reuses ids after a window closes, which is why
    /// the director drops entries when their process quits.
    case cgWindow(CGWindowID, pid: pid_t)
    /// Weaker fallback when the window id is unavailable: titles change (browser tabs, "edited"
    /// markers), which orphans the memory.
    case fallback(pid: pid_t, title: String)

    var pid: pid_t {
        switch self {
        case .cgWindow(_, let pid), .fallback(let pid, _):
            return pid
        }
    }
}

/// What `WindowDirector` needs from a window. `AXWindow` is the real one; tests use a fake.
@MainActor
protocol MovableWindow {
    var identity: WindowIdentity? { get }
    /// Nil when the frame cannot be read (window gone, app hung, Accessibility disabled).
    var cocoaFrame: CGRect? { get }
    /// Applies the frame. Returns `.success` or the first error the app answered with.
    @discardableResult
    func setCocoaFrame(_ frame: CGRect) -> AXError
}
