import ApplicationServices
import AppKit

/// Thin wrapper around a window `AXUIElement`.
@MainActor
struct AXWindow {
    let element: AXUIElement

    var pid: pid_t {
        var value: pid_t = 0
        AXUIElementGetPid(element, &value)
        return value
    }

    var title: String {
        string(attribute: kAXTitleAttribute as String) ?? ""
    }

    var role: String {
        string(attribute: kAXRoleAttribute as String) ?? ""
    }

    var axFrame: CGRect? {
        get {
            guard let origin = point(attribute: kAXPositionAttribute as String),
                  let size = size(attribute: kAXSizeAttribute as String) else { return nil }
            return CGRect(origin: origin, size: size)
        }
        nonmutating set {
            guard let newValue else { return }
            setSize(newValue.size)
            setPoint(newValue.origin)
            setSize(newValue.size)
        }
    }

    var cocoaFrame: CGRect? {
        get {
            guard let axFrame else { return nil }
            return ScreenGeometry.cocoaRect(fromAX: axFrame)
        }
        nonmutating set {
            guard let newValue else { return }
            axFrame = ScreenGeometry.axRect(fromCocoa: newValue)
        }
    }

    var cgWindowID: CGWindowID? {
        var identifier: CGWindowID = 0
        let error = AXUIElementGetWindow(element, &identifier)
        return error == .success ? identifier : nil
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static func focused() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        disableEnhancedUIIfNeeded(axApp)
        guard let window = copyElement(axApp, kAXFocusedWindowAttribute as String) else { return nil }
        let wrapped = AXWindow(element: window)
        guard wrapped.role == (kAXWindowRole as String) else { return nil }
        return wrapped
    }

    static func atCocoaPoint(_ point: CGPoint) -> AXWindow? {
        let axPoint = ScreenGeometry.axPoint(fromCocoa: point)
        let system = AXUIElementCreateSystemWide()
        var found: AXUIElement?
        let error = AXUIElementCopyElementAtPosition(system, Float(axPoint.x), Float(axPoint.y), &found)
        guard error == .success, let found else { return nil }
        return window(containing: found)
    }

    private static func window(containing element: AXUIElement) -> AXWindow? {
        var current: AXUIElement? = element
        for _ in 0..<16 {
            guard let node = current else { return nil }
            let role = stringValue(node, kAXRoleAttribute as String)
            if role == (kAXWindowRole as String) {
                let window = AXWindow(element: node)
                if let app = NSRunningApplication(processIdentifier: window.pid),
                   app.bundleIdentifier == Bundle.main.bundleIdentifier {
                    return nil
                }
                return window
            }
            current = copyElement(node, kAXParentAttribute as String)
        }
        return nil
    }

    private static func disableEnhancedUIIfNeeded(_ app: AXUIElement) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &value)
        if error == .success, let number = value as? NSNumber, number.boolValue {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
        }
    }

    private func point(attribute: String) -> CGPoint? {
        guard let value = copy(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func size(attribute: String) -> CGSize? {
        guard let value = copy(attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func string(attribute: String) -> String? {
        stringValue(element, attribute)
    }

    private func setPoint(_ point: CGPoint) {
        var value = point
        guard let ax = AXValueCreate(.cgPoint, &value) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, ax)
    }

    private func setSize(_ size: CGSize) {
        var value = size
        guard let ax = AXValueCreate(.cgSize, &value) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, ax)
    }

    private func copy(_ attribute: String) -> CFTypeRef? {
        copyValue(element, attribute)
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

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError
