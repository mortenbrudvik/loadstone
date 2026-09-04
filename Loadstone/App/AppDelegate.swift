import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let nativeTiling = NativeTiling()
    private var statusItem: StatusItemController?
    private var hotkeys: HotkeyCenter?
    private var dragMonitor: EdgeDragMonitor?
    private var terminationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Under `xcodebuild test` this process only hosts the test bundle: leave the user's
        // system preferences, permission prompts, hotkeys, and event monitors alone.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // Order matters: the AX timeout before any AX call, native tiling off before the first
        // drag can happen, monitors last.
        AXWindow.installMessagingTimeout()
        nativeTiling.disableEdgeTiling()
        AccessibilityAuth.promptAtLaunchIfNeeded()
        statusItem = StatusItemController()
        hotkeys = HotkeyCenter()
        hotkeys?.start()
        dragMonitor = EdgeDragMonitor()
        dragMonitor?.start()

        // Restore memory is keyed by window id, which macOS reuses; drop a process's entries
        // when it quits so a new window cannot inherit a stale frame.
        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            MainActor.assumeIsolated {
                WindowDirector.shared.forgetWindows(ofProcess: pid)
            }
        }

        Log.app.info("""
            launched: trusted=\(AccessibilityAuth.isTrusted) effective=\(AccessibilityAuth.isEffectivelyTrusted) \
            dragSnapping=\(AppSettings.shared.dragSnappingEnabled) monitoring=\(self.dragMonitor?.isMonitoring ?? false)
            """)
    }

    func applicationWillTerminate(_ notification: Notification) {
        nativeTiling.restoreEdgeTiling()
    }
}
