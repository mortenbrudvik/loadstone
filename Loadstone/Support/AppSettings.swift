import Foundation
import ServiceManagement

/// The slice of `SMAppService` that `AppSettings` uses, so the toggle logic can be tested
/// against a fake. `SMAppService` conforms as-is.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Key {
        static let dragSnapping = "dragSnappingEnabled"
    }

    @Published var dragSnappingEnabled: Bool {
        didSet { defaults.set(dragSnappingEnabled, forKey: Key.dragSnapping) }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLoginItem() }
    }

    /// Why the login item is not simply on or off (approval pending, last change failed).
    /// Nil when there is nothing to explain.
    @Published private(set) var loginItemMessage: String?

    var loginItemStatus: SMAppService.Status {
        loginItems.status
    }

    private let defaults: UserDefaults
    private let loginItems: any LoginItemService
    private var isApplyingLoginItem = false

    init(defaults: UserDefaults = .standard, loginItems: any LoginItemService = SMAppService.mainApp) {
        self.defaults = defaults
        self.loginItems = loginItems
        // object(forKey:) rather than bool(forKey:) so a missing key means on (opt-out default).
        dragSnappingEnabled = defaults.object(forKey: Key.dragSnapping) as? Bool ?? true
        launchAtLogin = loginItems.status == .enabled
        loginItemMessage = Self.message(for: loginItems.status)
    }

    private func applyLoginItem() {
        // Swift fires `didSet` for every assignment that goes through the setter, including the
        // rollback below (it is in a method, not lexically inside the observer). Without this
        // guard a failing register() followed by a failing unregister() recurses until the
        // stack overflows.
        guard !isApplyingLoginItem else { return }
        isApplyingLoginItem = true
        defer { isApplyingLoginItem = false }

        do {
            if launchAtLogin {
                try loginItems.register()
            } else {
                try loginItems.unregister()
            }
            loginItemMessage = Self.message(for: loginItems.status)
        } catch {
            let action = launchAtLogin ? "register" : "unregister"
            Log.settings.error("Login item \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            loginItemMessage = "Could not change Launch at login: \(error.localizedDescription)"
            launchAtLogin = loginItems.status == .enabled
        }
    }

    private static func message(for status: SMAppService.Status) -> String? {
        switch status {
        case .requiresApproval:
            // register() succeeded, but macOS wants the user to approve the item before it
            // will launch anything. Without this the toggle looks on while nothing happens.
            return "Approve Loadstone under System Settings › General › Login Items."
        default:
            return nil
        }
    }
}
