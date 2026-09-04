import AppKit
import KeyboardShortcuts

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    /// The user guide is the README on GitHub; the Help item opens it in the browser.
    static let helpURL = URL(string: "https://github.com/mortenbrudvik/loadstone#readme")!

    private let statusItem: NSStatusItem
    private let settings = SettingsWindowController()

    /// The status-bar menu, exposed for tests.
    var menu: NSMenu {
        statusItem.menu!
    }

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Loadstone") {
                image.isTemplate = true
                button.image = image
            } else {
                // Without an image the status item would be an invisible, unclickable-looking gap.
                assertionFailure("status bar symbol is missing")
                button.title = "Loadstone"
            }
        }
        let menu = buildMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Required by KeyboardShortcuts once menu items show their shortcut via setShortcut(for:):
    // NSMenu runs the thread in tracking mode, so Carbon hot-key events would queue up and all
    // fire at once when the menu closes. Disabling them while it is open drops them instead.
    func menuWillOpen(_ menu: NSMenu) {
        KeyboardShortcuts.disable(WindowCommand.all.map(\.hotkeyName))
    }

    func menuDidClose(_ menu: NSMenu) {
        KeyboardShortcuts.enable(WindowCommand.all.map(\.hotkeyName))
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        for section in WindowCommand.sections {
            for command in section {
                let item = NSMenuItem(title: command.title, action: #selector(runCommand(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = command
                item.setShortcut(for: command.hotkeyName)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        // Key equivalents shown here only work while the menu is open; an LSUIElement app has
        // no main menu for them to live in.
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        let help = NSMenuItem(title: "Loadstone Help", action: #selector(openHelp), keyEquivalent: "?")
        help.target = self
        menu.addItem(help)

        let relaunch = NSMenuItem(title: "Relaunch", action: #selector(relaunch), keyEquivalent: "")
        relaunch.target = self
        menu.addItem(relaunch)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Loadstone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? WindowCommand else {
            assertionFailure("menu item without a WindowCommand: \(sender.title)")
            return
        }
        WindowDirector.shared.perform(command)
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc func openHelp() {
        NSWorkspace.shared.open(Self.helpURL)
    }

    @objc private func relaunch() {
        AccessibilityAuth.relaunch()
    }
}
