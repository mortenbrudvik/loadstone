import AppKit
import SwiftUI
import KeyboardShortcuts

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = NSHostingController(rootView: SettingsRootView())
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
    @State private var trusted = AccessibilityAuth.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Snap windows by dragging to screen edges", isOn: $settings.dragSnappingEnabled)
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section("Accessibility") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Loadstone can move windows." : "Grant Accessibility access to move windows.")
                    Spacer()
                    if !trusted {
                        Button("Open Settings") { AccessibilityAuth.openSystemSettings() }
                        Button("Relaunch") { AccessibilityAuth.relaunch() }
                    }
                    Button("Recheck") { trusted = AccessibilityAuth.isTrusted }
                }
            }

            Section("About") {
                LabeledContent("App", value: "Loadstone")
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
            }
        }
        .formStyle(.grouped)
        .onAppear { trusted = AccessibilityAuth.isTrusted }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            ForEach(Array(HotkeyMap.bindings.enumerated()), id: \.offset) { _, pair in
                let name = pair.0
                let command = pair.1
                HStack {
                    Text(command.menuTitle)
                    Spacer()
                    KeyboardShortcuts.Recorder(for: name)
                }
            }
        }
        .formStyle(.grouped)
    }
}
