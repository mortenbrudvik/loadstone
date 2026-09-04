import ApplicationServices
import AppKit

/// Accessibility permission: checking it, asking for it, and walking the user through the
/// relaunch macOS requires before a new grant takes effect.
@MainActor
enum AccessibilityAuth {
    private static var didShowSystemPrompt = false
    private static var didShowRelaunchAlert = false

    /// What TCC says. Can be true while AX calls still fail; see `isEffectivelyTrusted`.
    static var isTrusted: Bool {
        AXIsProcessTrustedWithOptions([promptOption: false] as CFDictionary)
    }

    /// Whether an actual Accessibility call succeeds. After a grant, or after a rebuild that
    /// changed the code signature, `isTrusted` can say yes while every call answers
    /// `.apiDisabled` until the app relaunches. This is what the Settings pane reports.
    ///
    /// The probe must target *another application's* element. Two ways to get this wrong:
    /// the system-wide element answers `.cannotComplete` when the process is untrusted and
    /// never `.apiDisabled`, so a probe against it reports every process as working; and a
    /// process may always read its own hierarchy, trusted or not, so probing ourselves would
    /// answer yes just as uselessly. Only a cross-application read tells the states apart.
    static var isEffectivelyTrusted: Bool {
        // No other app to ask (no window server, a bare test rig): fall back to what TCC says
        // rather than inventing an answer.
        guard let pid = probeTarget else { return isTrusted }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value
        )
        // Anything but `.apiDisabled` means the call was allowed through: the app having no
        // focused window, or not answering, is not a permission problem.
        return error != .apiDisabled
    }

    /// A regular app that is not Loadstone, to aim the trust probe at.
    private static var probeTarget: pid_t? {
        NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }?.processIdentifier
    }

    /// The value of `kAXTrustedCheckOptionPrompt`. The constant itself is imported as a global
    /// `var`, which Swift 6 strict concurrency rejects as shared mutable state.
    private static let promptOption = "AXTrustedCheckOptionPrompt"

    /// Shows the system Accessibility dialog at launch when the permission is missing. That
    /// dialog and the relaunch alert each appear at most once per launch.
    static func promptAtLaunchIfNeeded() {
        guard !isTrusted else { return }
        showSystemPromptOnce()
    }

    /// Guards the command path: a command that fails because Accessibility is disabled shows
    /// the system dialog (if not yet shown this launch) and the relaunch alert (once per launch),
    /// never a dialog on every attempt.
    static func requestIfNeeded() {
        showSystemPromptOnce()
        guard !didShowRelaunchAlert else { return }
        didShowRelaunchAlert = true
        showRelaunchAlert()
    }

    private static func showSystemPromptOnce() {
        guard !didShowSystemPrompt else { return }
        didShowSystemPrompt = true
        _ = AXIsProcessTrustedWithOptions([promptOption: true] as CFDictionary)
    }

    /// Why "remove, then add again": TCC ties the grant to the code signature. Debug builds are
    /// ad-hoc signed, so each rebuild is a new identity and the old row shows as on but does not
    /// apply; re-adding re-keys it. Developer ID release builds keep a stable identity, so
    /// release users normally only need steps 3 to 5.
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

    /// Quits and starts a fresh process, which is what makes a new Accessibility grant apply.
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // `open` on a bundle that is still running only activates the running instance, so wait
        // for terminate(nil) to finish before asking LaunchServices for a new one; 0.6s is
        // empirical. The bundle path is passed as an argument ($0), never spliced into the
        // script, so quotes or spaces in it cannot break the command.
        process.arguments = ["-c", "sleep 0.6; exec /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        do {
            try process.run()
        } catch {
            Log.app.error("relaunch helper failed to start: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Loadstone could not relaunch itself"
            alert.informativeText = "Quit Loadstone and open it again from Applications.\n\n\(error.localizedDescription)"
            alert.runModal()
            return
        }
        NSApp.terminate(nil)
    }

    static func openSystemSettings() {
        // Deep links, tried in order:
        //   1. macOS 13+ System Settings, straight to the Accessibility pane
        //   2. the pre-Ventura System Preferences anchor, which System Settings still maps
        //   3. the Privacy & Security root, if the pane query is rejected
        // Last resort: the app with no pane selected.
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
        if !NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            Log.app.error("could not open System Settings")
        }
    }
}
