import SwiftUI

@main
struct LoadstoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `App` needs at least one Scene. `Settings` is the only one that does not open a window
        // at launch, and with LSUIElement there is no app menu to summon it, so it stays inert.
        // The real UI (status item, settings window) is built in AppKit by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
