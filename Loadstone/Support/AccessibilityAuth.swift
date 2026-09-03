import ApplicationServices
import AppKit

@MainActor
enum AccessibilityAuth {
    private static var didAskThisSession = false
    private static var watchTimer: Timer?

    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
    }

    static func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func startWatching() {
        watchTimer?.invalidate()
        guard !isTrusted else { return }
        prompt()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if isTrusted {
                    watchTimer?.invalidate()
                    watchTimer = nil
                }
            }
        }
    }

    /// Ask at most once per launch. Never reopen Settings on every snap.
    static func requestIfNeeded() {
        guard !isTrusted else { return }
        guard !didAskThisSession else { return }
        didAskThisSession = true
        prompt()
        showRelaunchAlert()
    }

    static func showRelaunchAlert() {
        let alert = NSAlert()
        alert.messageText = "Loadstone needs Accessibility"
        alert.informativeText = """
        1. System Settings → Privacy & Security → Accessibility
        2. If Loadstone is listed, select it and click − to remove it
        3. Click + and choose /Applications/Loadstone.app
        4. Turn it on
        5. Click Relaunch here

        macOS does not apply this permission until Loadstone restarts.
        """
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            relaunch()
        case .alertSecondButtonReturn:
            openSystemSettings()
        default:
            break
        }
    }

    static func relaunch() {
        let appPath = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "sleep 0.6; /usr/bin/open '\(appPath)'"]
        try? process.run()
        NSApp.terminate(nil)
    }

    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for spec in candidates {
            if let url = URL(string: spec), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
