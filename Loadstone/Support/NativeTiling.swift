import Foundation

/// macOS 15+ tiles windows itself when you drag to an edge. That fights Loadstone.
enum NativeTiling {
    private static let suite = "com.apple.WindowManager"
    private static let keys = [
        "EnableTilingByEdgeDrag",
        "EnableTopTilingByEdgeDrag",
    ]

    static func disableEdgeTiling() {
        guard let defaults = UserDefaults(suiteName: suite) else { return }
        for key in keys {
            defaults.set(false, forKey: key)
        }
        defaults.synchronize()
    }
}
