import AppKit
import XCTest
@testable import Loadstone

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testMenuHasAHelpItemThatOpensTheReadme() throws {
        let controller = StatusItemController()
        let help = try XCTUnwrap(
            controller.menu.items.first { $0.title == "Loadstone Help" },
            "no Help item in \(controller.menu.items.map(\.title))"
        )
        XCTAssertEqual(help.action, #selector(StatusItemController.openHelp))
        XCTAssertEqual(StatusItemController.helpURL.absoluteString, "https://github.com/mortenbrudvik/loadstone#readme")
    }

    func testHelpSitsWithTheAppItemsBetweenSettingsAndQuit() throws {
        let titles = StatusItemController().menu.items.map(\.title)
        let help = try XCTUnwrap(titles.firstIndex(of: "Loadstone Help"))
        XCTAssertGreaterThan(help, try XCTUnwrap(titles.firstIndex(of: "Settings…")))
        XCTAssertLessThan(help, try XCTUnwrap(titles.firstIndex(of: "Quit Loadstone")))
    }

    func testEveryCommandAppearsInTheMenuInOrderWithItsCommandAttached() {
        let menu = StatusItemController().menu
        let commands = menu.items.compactMap { $0.representedObject as? WindowCommand }
        XCTAssertEqual(commands, WindowCommand.all,
                       "WindowCommand.all is the single source of truth for the menu")
    }

    func testEveryCommandItemIsWiredToTheDirector() {
        // The controller must stay alive for the assertions: NSMenuItem.target is a weak
        // reference, so a temporary would leave every target nil.
        let controller = StatusItemController()
        let items = controller.menu.items.filter { $0.representedObject is WindowCommand }
        XCTAssertFalse(items.isEmpty)
        for item in items {
            XCTAssertNotNil(item.target, "\(item.title) would be disabled with no target")
            XCTAssertNotNil(item.action, "\(item.title) does nothing when clicked")
        }
    }

    func testSectionsAreSeparatedInTheMenu() {
        let menu = StatusItemController().menu
        let separators = menu.items.filter(\.isSeparatorItem).count
        XCTAssertEqual(separators, WindowCommand.Section.allCases.count + 1,
                       "one divider per section, plus the one above Quit")
    }
}
