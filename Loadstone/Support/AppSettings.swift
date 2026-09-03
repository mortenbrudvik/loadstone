import Foundation
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let dragSnapping = "dragSnappingEnabled"
        static let launchAtLogin = "launchAtLogin"
    }

    @Published var dragSnappingEnabled: Bool {
        didSet { UserDefaults.standard.set(dragSnappingEnabled, forKey: Key.dragSnapping) }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem() }
    }

    private init() {
        dragSnappingEnabled = UserDefaults.standard.object(forKey: Key.dragSnapping) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func applyLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
