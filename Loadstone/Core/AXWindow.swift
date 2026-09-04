import ApplicationServices
import AppKit

/// Why the frontmost app's focused window could not be resolved.
enum FocusLookupFailure: Error, Equatable {
    case noFrontmostApp
    /// Loadstone itself is frontmost (its Settings window is key). It never moves its own windows.
    case selfIsFrontmost
    /// The focused element is not a window: a sheet, a popover, or an app with no windows.
    case notAWindow(role: String?)
    /// The app did not answer. `.apiDisabled` means Accessibility is not granted (or the grant
    /// has not applied yet); `.cannotComplete` usually means the app is hung.
    case axError(AXError)
}

/// Thin wrapper around a window `AXUIElement`. This is the only place in the app that handles
/// Accessibility-space (top-left origin) coordinates; everything it exposes is Cocoa space.
@MainActor
struct AXWindow: MovableWindow {
    private let element: AXUIElement

    /// How long one AX request may block. The system default is 6 seconds, which would freeze
    /// Loadstone's main thread for that long whenever the target app is beachballing.
    static let messagingTimeout: Float = 0.25
    private static let enhancedUserInterface = "AXEnhancedUserInterface" as CFString
    /// How many ancestors to walk from a hit-tested element before giving up on finding a window.
    private static let maxAncestorDepth = 16

    /// Fails unless `element` has the window role, so a sheet or a group can never be wrapped.
    init?(windowElement element: AXUIElement) {
        guard stringValue(element, kAXRoleAttribute) == kAXWindowRole else { return nil }
        self.element = element
    }

    /// Makes `messagingTimeout` the process-wide default for every AX request. Call once at launch.
    static func installMessagingTimeout() {
        let error = AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), messagingTimeout)
        if error != .success {
            Log.ax.error("could not set the AX messaging timeout (AXError \(error.rawValue))")
        }
    }

    // MARK: Identity

    var pid: pid_t? {
        var value: pid_t = 0
        guard AXUIElementGetPid(element, &value) == .success else { return nil }
        return value
    }

    var title: String? {
        stringValue(element, kAXTitleAttribute)
    }

    var identity: WindowIdentity? {
        guard let pid else { return nil }
        if let id = cgWindowID {
            return .cgWindow(id, pid: pid)
        }
        return .fallback(pid: pid, title: title ?? "")
    }

    /// The CGWindowID behind this element, through a private HIServices SPI that has no public
    /// header. Resolved with dlsym so a macOS that drops the symbol yields nil (and the weaker
    /// title-based identity) instead of failing at load. Not App Store safe.
    var cgWindowID: CGWindowID? {
        guard let getWindow = Self.getWindow else { return nil }
        var identifier: CGWindowID = 0
        guard getWindow(element, &identifier) == .success else { return nil }
        return identifier
    }

    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let getWindow: GetWindowFunction? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "_AXUIElementGetWindow") else {
            Log.ax.error("_AXUIElementGetWindow is unavailable; Restore will identify windows by title")
            return nil
        }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    // MARK: Frame

    var cocoaFrame: CGRect? {
        guard let axFrame, let top = ScreenGeometry.primaryMaxY else { return nil }
        return ScreenGeometry.cocoaRect(fromAX: axFrame, primaryMaxY: top)
    }

    @discardableResult
    func setCocoaFrame(_ frame: CGRect) -> AXError {
        guard let top = ScreenGeometry.primaryMaxY else { return .failure }
        let ax = ScreenGeometry.axRect(fromCocoa: frame, primaryMaxY: top)
        return withEnhancedUserInterfaceDisabled {
            // Size, then position, then size again. If position goes first, an app can clamp the
            // window back onto its current screen when the target rect would not fit there
            // (moving to a smaller or differently placed display), so shrink first. The trailing
            // size pass is for apps that clamped the first one to the *old* screen's bounds.
            var error = setSize(ax.size)
            guard error == .success else { return error }
            error = setPoint(ax.origin)
            guard error == .success else { return error }
            return setSize(ax.size)
        }
    }

    private var axFrame: CGRect? {
        guard let origin = point(attribute: kAXPositionAttribute),
              let size = size(attribute: kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// `AXEnhancedUserInterface` is switched on for an app while an assistive client is attached
    /// (VoiceOver; Electron and Chromium also set it themselves). While it is on, AppKit animates
    /// AX position and size writes and can drop or clamp one that lands mid-animation, so tiles
    /// end up off target. Turn it off just around the write and put it back, so assistive-tech
    /// users of that app are not left with it disabled.
    private func withEnhancedUserInterfaceDisabled(_ write: () -> AXError) -> AXError {
        guard let pid else { return write() }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let wasOn = AXUIElementCopyAttributeValue(app, Self.enhancedUserInterface, &value) == .success
            && (value as? NSNumber)?.boolValue == true
        guard wasOn else { return write() }

        let disabled = AXUIElementSetAttributeValue(app, Self.enhancedUserInterface, kCFBooleanFalse)
        if disabled != .success {
            Log.ax.notice("could not disable enhanced UI for pid \(pid) (AXError \(disabled.rawValue))")
        }
        let result = write()
        let restored = AXUIElementSetAttributeValue(app, Self.enhancedUserInterface, kCFBooleanTrue)
        if restored != .success {
            Log.ax.error("could not restore enhanced UI for pid \(pid) (AXError \(restored.rawValue))")
        }
        return result
    }

    // MARK: Lookup

    static func focusedWindow() -> Result<AXWindow, FocusLookupFailure> {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .failure(.noFrontmostApp) }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return .failure(.selfIsFrontmost) }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value)
        guard error == .success else { return .failure(.axError(error)) }
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failure(.notAWindow(role: nil)) }
        let element = value as! AXUIElement
        guard let window = AXWindow(windowElement: element) else {
            return .failure(.notAWindow(role: stringValue(element, kAXRoleAttribute)))
        }
        return .success(window)
    }

    /// The window under a Cocoa-space point, found by walking up from the deepest element
    /// there. Nil when there is none, when it belongs to Loadstone, or when the app under the
    /// pointer does not answer.
    static func atCocoaPoint(_ point: CGPoint) -> AXWindow? {
        guard let top = ScreenGeometry.primaryMaxY else { return nil }
        // The system-wide hit test takes Accessibility (top-left) coordinates.
        let axPoint = ScreenGeometry.axPoint(fromCocoa: point, primaryMaxY: top)
        var found: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(axPoint.x), Float(axPoint.y), &found)
        guard error == .success, let found else {
            if error != .success {
                Log.ax.debug("no element at \(point.x), \(point.y) (AXError \(error.rawValue))")
            }
            return nil
        }
        return window(containing: found)
    }

    private static func window(containing element: AXUIElement) -> AXWindow? {
        var current: AXUIElement? = element
        for _ in 0..<maxAncestorDepth {
            guard let node = current else { return nil }
            if let window = AXWindow(windowElement: node) {
                // Never move our own windows (Settings, the snap preview).
                if let pid = window.pid,
                   NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == Bundle.main.bundleIdentifier {
                    return nil
                }
                return window
            }
            current = copyElement(node, kAXParentAttribute)
        }
        return nil
    }

    // MARK: Raw attribute access

    private func point(attribute: String) -> CGPoint? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(attribute: String) -> CGSize? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func setPoint(_ point: CGPoint) -> AXError {
        var value = point
        guard let ax = AXValueCreate(.cgPoint, &value) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, ax)
    }

    private func setSize(_ size: CGSize) -> AXError {
        var value = size
        guard let ax = AXValueCreate(.cgSize, &value) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, ax)
    }
}

private func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else { return nil }
    return value
}

private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}

private func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
    copyValue(element, attribute) as? String
}
