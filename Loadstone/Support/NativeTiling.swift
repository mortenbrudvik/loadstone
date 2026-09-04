import Foundation

/// macOS 15 tiles windows itself when you drag to an edge, which fights Loadstone's own
/// snapping. This writes the two System Settings → Desktop & Dock → Windows toggles to off in
/// WindowManager's own defaults domain at launch, remembers what the user had, and puts it
/// back at quit. The keys are unknown on macOS 14 (the deployment target), where the writes
/// are harmless. A crash or force-quit skips the restore; the README tells users where to
/// re-enable it by hand.
final class NativeTiling {
    static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]
    private static let suite = "com.apple.WindowManager"

    private let defaults: UserDefaults
    /// The user's values before Loadstone touched them. A nil value means the key was absent,
    /// so macOS's own default applied. Recorded once, on the first disable, and cleared on restore.
    private var previous: [String: Bool?]?

    /// `UserDefaults(suiteName:)` only returns nil for reserved suite names.
    init(defaults: UserDefaults = UserDefaults(suiteName: NativeTiling.suite)!) {
        self.defaults = defaults
    }

    func disableEdgeTiling() {
        if previous == nil {
            previous = Dictionary(uniqueKeysWithValues: Self.keys.map { ($0, defaults.object(forKey: $0) as? Bool) })
        }
        for key in Self.keys {
            defaults.set(false, forKey: key)
        }
        for key in Self.keys where defaults.object(forKey: key) as? Bool != false {
            Log.app.error("could not turn off \(key, privacy: .public); macOS edge tiling will fight drag snapping")
        }
    }

    func restoreEdgeTiling() {
        guard let previous else { return }
        for (key, value) in previous {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        self.previous = nil
    }
}
