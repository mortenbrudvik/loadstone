import XCTest
import KeyboardShortcuts
@testable import Loadstone

final class WindowCommandTests: XCTestCase {
    func testAllCoversEveryTileAndEveryOtherCommand() {
        for tile in Tile.allCases {
            XCTAssertTrue(WindowCommand.all.contains(.tile(tile)), "\(tile) has no command")
        }
        for command in [WindowCommand.center, .restore, .nextDisplay, .previousDisplay] {
            XCTAssertTrue(WindowCommand.all.contains(command), "\(command) missing")
        }
        XCTAssertEqual(WindowCommand.all.count, Tile.allCases.count + 4)
    }

    /// These strings are the UserDefaults keys under which users' custom shortcuts are stored
    /// (KeyboardShortcuts_<id>). Changing one silently discards that customization.
    func testIdsAreStablePersistenceKeys() {
        XCTAssertEqual(WindowCommand.all.map(\.id), [
            "leftHalf", "rightHalf", "topHalf", "bottomHalf",
            "topLeft", "topRight", "bottomLeft", "bottomRight",
            "leftThird", "centerThird", "rightThird", "leftTwoThirds", "rightTwoThirds",
            "maximize", "center", "restore", "nextDisplay", "previousDisplay",
        ])
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(WindowCommand.all.map(\.id)).count, WindowCommand.all.count)
    }

    func testTitlesAreNonEmptyAndUnique() {
        let titles = WindowCommand.all.map(\.title)
        XCTAssertFalse(titles.contains(""))
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertEqual(WindowCommand.tile(.topLeft).title, "Top Left Corner")
        XCTAssertEqual(WindowCommand.nextDisplay.title, "Next Display")
    }

    func testDefaultShortcutsAreUnique() {
        let shortcuts = WindowCommand.all.map(\.defaultShortcut)
        XCTAssertEqual(Set(shortcuts).count, shortcuts.count)
    }

    func testDefaultShortcutsMatchTheDocumentedOnes() {
        XCTAssertEqual(WindowCommand.tile(.leftHalf).defaultShortcut, .init(.leftArrow, modifiers: [.control, .option]))
        XCTAssertEqual(WindowCommand.tile(.topLeft).defaultShortcut, .init(.u, modifiers: [.control, .option]))
        XCTAssertEqual(WindowCommand.tile(.maximize).defaultShortcut, .init(.return, modifiers: [.control, .option]))
        XCTAssertEqual(WindowCommand.restore.defaultShortcut, .init(.delete, modifiers: [.control, .option]))
        XCTAssertEqual(WindowCommand.nextDisplay.defaultShortcut, .init(.rightArrow, modifiers: [.control, .option, .command]))
    }

    func testHotkeyNameCarriesTheIdAndTheDefault() {
        for command in WindowCommand.all {
            XCTAssertEqual(command.hotkeyName.rawValue, command.id)
            XCTAssertEqual(command.hotkeyName.defaultShortcut, command.defaultShortcut)
        }
    }
}
