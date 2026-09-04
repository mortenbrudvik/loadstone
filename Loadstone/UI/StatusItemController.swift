import AppKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let settings = SettingsWindowController()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Loadstone")
            button.image?.isTemplate = true
        }
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.disable(HotkeyMap.names)
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(HotkeyMap.names)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        func add(_ command: WindowCommand) {
            let item = NSMenuItem(title: command.menuTitle, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Box(command)
            if let name = HotkeyMap.name(for: command) {
                item.setShortcut(for: name)
            }
            menu.addItem(item)
        }

        add(.tile(.leftHalf))
        add(.tile(.rightHalf))
        add(.tile(.topHalf))
        add(.tile(.bottomHalf))
        menu.addItem(.separator())
        add(.tile(.topLeft))
        add(.tile(.topRight))
        add(.tile(.bottomLeft))
        add(.tile(.bottomRight))
        menu.addItem(.separator())
        add(.tile(.leftThird))
        add(.tile(.centerThird))
        add(.tile(.rightThird))
        add(.tile(.leftTwoThirds))
        add(.tile(.rightTwoThirds))
        menu.addItem(.separator())
        add(.tile(.maximize))
        add(.center)
        add(.restore)
        menu.addItem(.separator())
        add(.nextDisplay)
        add(.previousDisplay)
        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let relaunch = NSMenuItem(title: "Relaunch", action: #selector(relaunch), keyEquivalent: "")
        relaunch.target = self
        menu.addItem(relaunch)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Loadstone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<WindowCommand> else { return }
        WindowDirector.shared.perform(box.value)
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func relaunch() {
        AccessibilityAuth.relaunch()
    }
}

private final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}
