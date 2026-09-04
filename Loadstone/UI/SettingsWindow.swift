import AppKit
import SwiftUI
import KeyboardShortcuts
import ServiceManagement

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = NSHostingController(rootView: SettingsRootView())
            // NSWindow(contentViewController:) leaves isReleasedWhenClosed false, so holding the
            // window here and re-showing it after the user closes it is safe.
            let panel = NSWindow(contentViewController: root)
            panel.title = "Loadstone Settings"
            panel.styleMask = [.titled, .closable, .miniaturizable]
            panel.setContentSize(NSSize(width: 520, height: 560))
            panel.center()
            window = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 480)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    /// Accessibility has no change notification, so this is a snapshot taken on appear and
    /// refreshed by Recheck. It probes a real AX call, not just what TCC says, so a grant that
    /// has not applied yet (relaunch pending) shows as not working.
    @State private var trusted = AccessibilityAuth.isEffectivelyTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Snap windows by dragging to screen edges", isOn: $settings.dragSnappingEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let message = settings.loginItemMessage {
                    HStack {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if settings.loginItemStatus == .requiresApproval {
                            Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                        }
                    }
                }
            }

            Section("Accessibility") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Loadstone can move windows." : "Grant Accessibility access, then relaunch Loadstone.")
                    Spacer()
                    if !trusted {
                        Button("Open Settings") { AccessibilityAuth.openSystemSettings() }
                        Button("Relaunch") { AccessibilityAuth.relaunch() }
                    }
                    Button("Recheck") { trusted = AccessibilityAuth.isEffectivelyTrusted }
                }
            }

            Section("About") {
                LabeledContent("App", value: "Loadstone")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = AccessibilityAuth.isEffectivelyTrusted }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            ForEach(WindowCommand.all, id: \.self) { command in
                HStack {
                    Text(command.title)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: command.hotkeyName)
                }
            }
        }
        .formStyle(.grouped)
    }
}
