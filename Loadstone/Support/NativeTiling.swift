import Foundation

/// macOS 15 tiles windows itself when you drag to an edge, which fights Loadstone's own
/// snapping. This writes the two System Settings → Desktop & Dock → Windows toggles to off in
/// WindowManager's own defaults domain at launch, remembers what the user had, and puts it
/// back at quit. The keys are unknown on macOS 14 (the deployment target), where the writes
/// are harmless. A crash or force-quit skips the restore; the README tells users where to
/// re-enable it by hand.
final class NativeTiling {
    static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]
    /// Where the pre-Loadstone values are parked in Loadstone's own defaults for the duration
    /// of a run, so an unclean exit can be detected and undone at the next launch.
    static let markerKey = "nativeTilingPreviousValues"
    private static let suite = "com.apple.WindowManager"

    private let defaults: UserDefaults
    private let marker: UserDefaults
    /// The user's values before Loadstone touched them. A nil value means the key was absent,
    /// so macOS's own default applied. Recorded once, on the first disable, and cleared on restore.
    private var previous: [String: Bool?]?

    /// `UserDefaults(suiteName:)` only returns nil for reserved suite names.
    init(defaults: UserDefaults = UserDefaults(suiteName: NativeTiling.suite)!, marker: UserDefaults = .standard) {
        self.defaults = defaults
        self.marker = marker
    }

    func disableEdgeTiling() {
        if previous == nil {
            recoverFromUncleanExit()
            let captured = Dictionary(uniqueKeysWithValues: Self.keys.map { ($0, defaults.object(forKey: $0) as? Bool) })
            previous = captured
            // Park the capture where it outlives the process. Keys the user had not set are
            // simply absent from the stored dictionary, which is how restore tells "put this
            // value back" apart from "remove the key so macOS's own default applies".
            marker.set(captured.compactMapValues { $0 }, forKey: Self.markerKey)
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
        apply(previous.compactMapValues { $0 })
        self.previous = nil
        marker.removeObject(forKey: Self.markerKey)
    }

    /// A run that was force-quit or crashed never reached `restoreEdgeTiling`, so its marker is
    /// still parked in Loadstone's defaults and the user's real settings are still overwritten
    /// with false. Put them back before capturing a new baseline: capturing first would record
    /// Loadstone's own false as "what the user had" and make the change permanent.
    private func recoverFromUncleanExit() {
        guard let stored = marker.dictionary(forKey: Self.markerKey) as? [String: Bool] else { return }
        Log.app.notice("recovering macOS edge tiling settings left behind by an unclean exit")
        apply(stored)
        marker.removeObject(forKey: Self.markerKey)
    }

    /// Writes the values a capture holds, removing any key the capture does not mention so
    /// macOS's own default applies again.
    private func apply(_ values: [String: Bool]) {
        for key in Self.keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
