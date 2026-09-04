import Foundation
import os

/// Unified-logging categories. Read them with
/// `log stream --predicate 'subsystem == "com.brudvik.loadstone"' --level debug`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.brudvik.loadstone"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let ax = Logger(subsystem: subsystem, category: "accessibility")
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let drag = Logger(subsystem: subsystem, category: "drag")
    static let settings = Logger(subsystem: subsystem, category: "settings")
}
