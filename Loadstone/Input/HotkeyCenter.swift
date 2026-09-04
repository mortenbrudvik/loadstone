import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let leftHalf = Self("leftHalf", default: .init(.leftArrow, modifiers: [.control, .option]))
    static let rightHalf = Self("rightHalf", default: .init(.rightArrow, modifiers: [.control, .option]))
    static let topHalf = Self("topHalf", default: .init(.upArrow, modifiers: [.control, .option]))
    static let bottomHalf = Self("bottomHalf", default: .init(.downArrow, modifiers: [.control, .option]))
    static let topLeft = Self("topLeft", default: .init(.u, modifiers: [.control, .option]))
    static let topRight = Self("topRight", default: .init(.i, modifiers: [.control, .option]))
    static let bottomLeft = Self("bottomLeft", default: .init(.j, modifiers: [.control, .option]))
    static let bottomRight = Self("bottomRight", default: .init(.k, modifiers: [.control, .option]))
    static let leftThird = Self("leftThird", default: .init(.d, modifiers: [.control, .option]))
    static let centerThird = Self("centerThird", default: .init(.f, modifiers: [.control, .option]))
    static let rightThird = Self("rightThird", default: .init(.g, modifiers: [.control, .option]))
    static let leftTwoThirds = Self("leftTwoThirds", default: .init(.e, modifiers: [.control, .option]))
    static let rightTwoThirds = Self("rightTwoThirds", default: .init(.t, modifiers: [.control, .option]))
    static let maximize = Self("maximize", default: .init(.return, modifiers: [.control, .option]))
    static let center = Self("center", default: .init(.c, modifiers: [.control, .option]))
    static let restore = Self("restore", default: .init(.delete, modifiers: [.control, .option]))
    static let nextDisplay = Self("nextDisplay", default: .init(.rightArrow, modifiers: [.control, .option, .command]))
    static let previousDisplay = Self("previousDisplay", default: .init(.leftArrow, modifiers: [.control, .option, .command]))
}

enum HotkeyMap {
    static var names: [KeyboardShortcuts.Name] {
        bindings.map(\.0)
    }

    static func name(for command: WindowCommand) -> KeyboardShortcuts.Name? {
        bindings.first { $0.1 == command }?.0
    }

    static let bindings: [(KeyboardShortcuts.Name, WindowCommand)] = [
        (.leftHalf, .tile(.leftHalf)),
        (.rightHalf, .tile(.rightHalf)),
        (.topHalf, .tile(.topHalf)),
        (.bottomHalf, .tile(.bottomHalf)),
        (.topLeft, .tile(.topLeft)),
        (.topRight, .tile(.topRight)),
        (.bottomLeft, .tile(.bottomLeft)),
        (.bottomRight, .tile(.bottomRight)),
        (.leftThird, .tile(.leftThird)),
        (.centerThird, .tile(.centerThird)),
        (.rightThird, .tile(.rightThird)),
        (.leftTwoThirds, .tile(.leftTwoThirds)),
        (.rightTwoThirds, .tile(.rightTwoThirds)),
        (.maximize, .tile(.maximize)),
        (.center, .center),
        (.restore, .restore),
        (.nextDisplay, .nextDisplay),
        (.previousDisplay, .previousDisplay),
    ]
}

@MainActor
final class HotkeyCenter {
    func start() {
        for (name, command) in HotkeyMap.bindings {
            KeyboardShortcuts.onKeyUp(for: name) {
                Task { @MainActor in
                    WindowDirector.shared.perform(command)
                }
            }
        }
    }
}
