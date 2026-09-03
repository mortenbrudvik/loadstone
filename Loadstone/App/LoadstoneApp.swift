import SwiftUI

@main
struct LoadstoneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu-bar app: windows are created in AppKit (status item + settings).
        Settings {
            EmptyView()
        }
    }
}
