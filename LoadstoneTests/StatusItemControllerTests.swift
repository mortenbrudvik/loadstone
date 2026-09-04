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
}
