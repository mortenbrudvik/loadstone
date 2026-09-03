import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var hotkeys: HotkeyCenter?
    private var dragMonitor: EdgeDragMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NativeTiling.disableEdgeTiling()
        AccessibilityAuth.startWatching()
        statusItem = StatusItemController()
        hotkeys = HotkeyCenter()
        hotkeys?.start()
        dragMonitor = EdgeDragMonitor()
        dragMonitor?.start()
    }
}
