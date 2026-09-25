import XCTest
import ApplicationServices
@testable import Loadstone

@MainActor
final class WindowDirectorTests: XCTestCase {
    private final class FakeWindow: MovableWindow {
        var identity: WindowIdentity? {
            guard titleFollowsSize, let cocoaFrame else { return assignedIdentity }
            let cell = grid ?? CGSize(width: 1, height: 1)
            return .fallback(pid: 42, title: "\(Int(cocoaFrame.width / cell.width))×\(Int(cocoaFrame.height / cell.height))")
        }
        var cocoaFrame: CGRect?
        var writes: [CGRect] = []
        var rejectWith: AXError?
        /// Set to act like Terminal or iTerm2, which round a window's size down to whole character
        /// cells and keep its top-left corner, so it never fills a tile exactly.
        var grid: CGSize?
        /// Set to act like an app that will not make the window narrower than this. Like the grid,
        /// it keeps the top-left corner, so the window grows to the right.
        var minimumWidth: CGFloat?
        /// Set to act like an app that applies a frame only after the write has returned, so the
        /// frame read straight back is still the old one. `catchUp()` applies it.
        var appliesLate = false
        /// Set to act like AXWindow writing to an app that takes the size and then refuses the
        /// position, or times out on it: the window has the new size at its old top-left corner,
        /// and the write fails with this error.
        var refusesPositionWith: AXError?
        /// Set to act like Terminal when the window id is unavailable: the identity falls back to
        /// the title, and Terminal's default title carries the window's size in character cells
        /// ("80×24"), so a write that resizes the window renames it.
        var titleFollowsSize = false
        /// Set to act like a hung app, whose frame cannot be read either once it has refused a
        /// write: the refusal leaves `cocoaFrame` nil until the test sets it again.
        var unreadableOnceRefused = false
        private let assignedIdentity: WindowIdentity?
        private var pending: CGRect?

        init(frame: CGRect, identity: WindowIdentity? = .cgWindow(1, pid: 42)) {
            cocoaFrame = frame
            assignedIdentity = identity
        }

        @discardableResult
        func setCocoaFrame(_ frame: CGRect) -> AXError {
            if let rejectWith {
                if unreadableOnceRefused { cocoaFrame = nil }
                return rejectWith
            }
            writes.append(frame)
            if let refusesPositionWith, let old = cocoaFrame {
                cocoaFrame = CGRect(x: old.minX, y: old.maxY - frame.height, width: frame.width, height: frame.height)
                return refusesPositionWith
            }
            var landed = frame
            if let grid {
                let width = (frame.width / grid.width).rounded(.down) * grid.width
                let height = (frame.height / grid.height).rounded(.down) * grid.height
                landed = CGRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
            }
            if let minimumWidth {
                landed.size.width = max(landed.width, minimumWidth)
            }
            if appliesLate {
                pending = landed
            } else {
                cocoaFrame = landed
            }
            return .success
        }

        func catchUp() {
            if let pending { cocoaFrame = pending }
            pending = nil
        }
    }

    private let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 80, width: 1920, height: 975)
    )
    private let right = Display(
        frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1415)
    )
    private let left = Display(
        frame: CGRect(x: -1440, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: -1440, y: 0, width: 1440, height: 875)
    )
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)
    /// On the right-hand display and in no tile.
    private let floating = CGRect(x: 2200, y: 100, width: 800, height: 600)
    /// On the right-hand display, flush with the top-left corner of its visible frame, so it
    /// shares that corner with the display's left half without being in it.
    private let flushTopLeft = CGRect(x: 1920, y: 515, width: 800, height: 600)
    /// A Terminal character cell. No half's width or height here is a whole number of them.
    private let terminalCell = CGSize(width: 7, height: 17)

    private func makeDirector() -> WindowDirector {
        WindowDirector(displays: { [self.primary, self.right] })
    }

    /// The lines a director diagnoses, which the app sends to the log at info level.
    private final class Diagnostics {
        var lines: [String] = []
    }

    private func makeDirector(diagnosingInto diagnostics: Diagnostics) -> WindowDirector {
        WindowDirector(displays: { [self.primary, self.right] }, diagnose: { diagnostics.lines.append($0) })
    }

    func testTilePlacesTheWindowOnTheDisplayUnderItsCentre() {
        let window = FakeWindow(frame: original)
        let outcome = makeDirector().perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: primary.visibleFrame))
    }

    func testRestoreReturnsToTheFrameBeforeTheFirstCommand() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        director.perform(.tile(.rightHalf), on: window)
        director.perform(.center, on: window)

        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, original)
    }

    func testRestoreIsOneShot() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        director.perform(.restore, on: window)
        let writesSoFar = window.writes.count

        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore)
        XCTAssertEqual(window.writes.count, writesSoFar)
    }

    func testRestoreWithNothingRememberedWritesNothing() {
        let window = FakeWindow(frame: original)
        XCTAssertEqual(makeDirector().perform(.restore, on: window), .nothingToRestore)
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testMovingToTheNextDisplayIsRememberedForRestore() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.nextDisplay, on: window)
        XCTAssertNotEqual(window.cocoaFrame, original)

        director.perform(.restore, on: window)
        XCTAssertEqual(window.cocoaFrame, original)
    }

    func testNextDisplayMapsTheWindowProportionally() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: primary.visibleFrame))
        makeDirector().perform(.nextDisplay, on: window)
        let expected = Tile.leftHalf.frame(in: right.visibleFrame)
        XCTAssertEqual(window.cocoaFrame!.minX, expected.minX, accuracy: 1e-6)
        XCTAssertEqual(window.cocoaFrame!.minY, expected.minY, accuracy: 1e-6)
        XCTAssertEqual(window.cocoaFrame!.width, expected.width, accuracy: 1e-6)
        XCTAssertEqual(window.cocoaFrame!.height, expected.height, accuracy: 1e-6)
    }

    func testPreviousDisplayWrapsAround() {
        let window = FakeWindow(frame: original)
        makeDirector().perform(.previousDisplay, on: window)
        XCTAssertTrue(right.visibleFrame.contains(window.cocoaFrame!), "\(window.cocoaFrame!)")
    }

    func testNextDisplayWithASingleDisplayReportsInsteadOfReapplying() {
        let window = FakeWindow(frame: original)
        let director = WindowDirector(displays: { [self.primary] })
        XCTAssertEqual(director.perform(.nextDisplay, on: window), .noOtherDisplay)
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testSnapUsesTheGivenDisplayNotTheOneUnderTheWindow() {
        let window = FakeWindow(frame: original)
        let outcome = makeDirector().snap(.rightHalf, window: window, on: right)
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.rightHalf.frame(in: right.visibleFrame))
    }

    func testCenterKeepsTheSize() {
        let window = FakeWindow(frame: original)
        makeDirector().perform(.center, on: window)
        XCTAssertEqual(window.cocoaFrame?.size, original.size)
        XCTAssertEqual(window.cocoaFrame?.midX, primary.visibleFrame.midX)
    }

    func testWindowOffEveryDisplayIsTiledOnThePrimary() {
        let window = FakeWindow(frame: CGRect(x: 9000, y: 9000, width: 300, height: 200))
        makeDirector().perform(.tile(.maximize), on: window)
        XCTAssertEqual(window.cocoaFrame, primary.visibleFrame)
    }

    func testRejectedFrameIsReportedNotSwallowed() {
        let window = FakeWindow(frame: original)
        window.rejectWith = .cannotComplete
        XCTAssertEqual(makeDirector().perform(.tile(.leftHalf), on: window), .rejected(.cannotComplete))
    }

    func testUnreadableFrameIsReported() {
        let window = FakeWindow(frame: original)
        window.cocoaFrame = nil
        XCTAssertEqual(makeDirector().perform(.tile(.leftHalf), on: window), .frameUnreadable)
    }

    func testForgettingAProcessDropsItsRestoreMemory() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)

        director.forgetWindows(ofProcess: 42)

        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore)
    }

    func testWindowsWithoutIdentityStillMoveButCannotRestore() {
        let window = FakeWindow(frame: original, identity: nil)
        let director = makeDirector()
        XCTAssertEqual(director.perform(.tile(.leftHalf), on: window), .moved)
        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore)
    }

    func testAWindowWhoseTitleFollowsItsSizeCanStillBeRestored() {
        let window = FakeWindow(frame: floating)
        window.titleFollowsSize = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)

        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, floating)
    }

    func testRestoreAfterTwoResizesReturnsAWindowWhoseTitleFollowsItsSizeToWhereItStarted() {
        let window = FakeWindow(frame: floating)
        window.titleFollowsSize = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        director.perform(.tile(.maximize), on: window)

        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, floating)
    }

    func testTheRestoreFrameOfAWindowWhoseTitleFollowsItsSizeIsNeverOverwritten() {
        // Resized by hand, the window goes by a title nothing is recorded under, so Center records
        // its frame there. Left Half then gives it back the title its first command recorded under,
        // which already holds the frame from before Loadstone first touched it.
        let window = FakeWindow(frame: floating)
        window.titleFollowsSize = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.cocoaFrame = CGRect(x: 2300, y: 200, width: 901, height: 601)
        director.perform(.center, on: window)
        director.perform(.tile(.leftHalf), on: window)

        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, floating)
    }

    func testARejectedCommandIsNotRememberedForRestore() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        window.rejectWith = .cannotComplete
        XCTAssertEqual(director.perform(.tile(.leftHalf), on: window), .rejected(.cannotComplete))

        window.rejectWith = nil
        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore,
                       "a command the app refused must not leave a restore entry behind")
    }

    func testACommandThatNeverRanIsNotRememberedForRestore() {
        let window = FakeWindow(frame: original)
        let director = WindowDirector(displays: { [self.primary] })
        XCTAssertEqual(director.perform(.nextDisplay, on: window), .noOtherDisplay)

        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore,
                       "nothing moved, so there is nothing to restore to")
    }

    // MARK: Continuing across displays

    func testLeftHalfOnAWindowAlreadyThereContinuesToTheRightHalfOfTheDisplayToTheLeft() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: right.visibleFrame))
        XCTAssertEqual(makeDirector().perform(.tile(.leftHalf), on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.rightHalf.frame(in: primary.visibleFrame))
    }

    func testRightHalfOnAWindowAlreadyThereContinuesToTheLeftHalfOfTheDisplayToTheRight() {
        let window = FakeWindow(frame: Tile.rightHalf.frame(in: primary.visibleFrame))
        makeDirector().perform(.tile(.rightHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAWindowNotInTheHalfYetSnapsOnItsOwnDisplayFirst() {
        let window = FakeWindow(frame: floating)
        makeDirector().perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAtTheEdgeOfTheDeskAHalfStaysWhereItIs() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: primary.visibleFrame))
        XCTAssertEqual(makeDirector().perform(.tile(.leftHalf), on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: primary.visibleFrame))
    }

    func testRepeatedLeftHalfWalksAWindowAcrossTheDeskOneHalfAtATime() {
        // The window never fills a half, so each step has to be recognised from where Loadstone
        // last put it, and each step has to record the half it actually landed in.
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        let director = WindowDirector(displays: { [self.primary, self.right, self.left] })

        for _ in 0..<5 { director.perform(.tile(.leftHalf), on: window) }

        XCTAssertEqual(window.writes, [
            Tile.leftHalf.frame(in: right.visibleFrame),
            Tile.rightHalf.frame(in: primary.visibleFrame),
            Tile.leftHalf.frame(in: primary.visibleFrame),
            Tile.rightHalf.frame(in: left.visibleFrame),
            Tile.leftHalf.frame(in: left.visibleFrame),
        ])
    }

    func testRepeatedLeftHalfKeepsAWindowWiderThanTheDisplayToItsLeftOnThatDisplay() {
        // The left display is 1440 wide, and this window will not go below 1501. In the right
        // half of it, which starts at x = -720, the window reaches past the seam at x = 0: its
        // centre is at -720 + 1501 / 2 = 30.5, on primary. It still belongs to the left display.
        let window = FakeWindow(frame: CGRect(x: 100, y: 100, width: 1501, height: 600))
        window.minimumWidth = 1501
        let director = WindowDirector(displays: { [self.primary, self.right, self.left] })

        for _ in 0..<4 { director.perform(.tile(.leftHalf), on: window) }

        XCTAssertEqual(window.writes, [
            Tile.leftHalf.frame(in: primary.visibleFrame),
            Tile.rightHalf.frame(in: left.visibleFrame),
            Tile.leftHalf.frame(in: left.visibleFrame),
            Tile.leftHalf.frame(in: left.visibleFrame),
        ])
    }

    func testCenterWorksOnTheDisplayAWiderWindowWasPlacedOn() throws {
        // As above, the right half of the left display leaves this window's centre on primary.
        let window = FakeWindow(frame: CGRect(x: -1400, y: 100, width: 1501, height: 600))
        window.minimumWidth = 1501
        let director = WindowDirector(displays: { [self.primary, self.right, self.left] })
        director.perform(.tile(.rightHalf), on: window)
        let placed = try XCTUnwrap(window.cocoaFrame)

        director.perform(.center, on: window)
        XCTAssertEqual(window.writes.last, Layout.centered(placed, in: left.visibleFrame))
    }

    func testDisplayMovesMapAWindowFromTheDisplayUnderItsCentre() throws {
        // The right half of the left display leaves this window mostly on primary. Mapped from the
        // left display, which is narrower than the window, it would grow on the way: Previous
        // Display would ask for 2668pt of the right-hand display, most of it off the desk.
        for (command, destination) in [(WindowCommand.nextDisplay, right), (.previousDisplay, left)] {
            let window = FakeWindow(frame: CGRect(x: -1400, y: 100, width: 1501, height: 600))
            window.minimumWidth = 1501
            let director = WindowDirector(displays: { [self.primary, self.right, self.left] })
            director.perform(.tile(.rightHalf), on: window)
            let placed = try XCTUnwrap(window.cocoaFrame)

            director.perform(command, on: window)
            XCTAssertEqual(window.writes.last, Layout.mapped(placed, from: primary.visibleFrame, to: destination.visibleFrame), "\(command)")
        }
    }

    func testAWindowMovedSinceItWasPlacedGoesBackIntoTheHalfInsteadOfContinuing() {
        let window = FakeWindow(frame: floating)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.cocoaFrame = floating  // dragged back out by hand

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAWindowResizedSinceItWasPlacedGoesBackIntoTheHalfInsteadOfContinuing() throws {
        let window = FakeWindow(frame: floating)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        let landed = try XCTUnwrap(window.cocoaFrame)
        // Resized by hand from its bottom-right corner, which keeps the top-left where it landed.
        window.cocoaFrame = CGRect(x: landed.minX, y: landed.maxY - 601, width: 901, height: 601)

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAWindowAnotherTileLeftAtTheHalfsTopLeftGoesIntoTheHalfInsteadOfContinuing() {
        // Each first tile shares the half's top-left corner, so the window still stands where
        // that tile put it, with the corner the half would give it. Only a placement sent to the
        // half's own frame counts as in the half.
        let cases: [(first: Tile, half: Tile, start: CGRect, display: Display)] = [
            (.maximize, .leftHalf, floating, right),
            (.topLeft, .leftHalf, floating, right),
            (.topHalf, .leftHalf, floating, right),
            (.leftThird, .leftHalf, floating, right),
            (.leftTwoThirds, .leftHalf, floating, right),
            (.topRight, .rightHalf, original, primary),
        ]
        for (first, half, start, display) in cases {
            let window = FakeWindow(frame: start)
            let director = makeDirector()
            director.perform(.tile(first), on: window)

            director.perform(.tile(half), on: window)
            XCTAssertEqual(window.writes.last, half.frame(in: display.visibleFrame), "\(first) then \(half)")
        }
    }

    func testAWindowMovedToAnotherDisplaySinceItWasPlacedIsTiledOnTheDisplayItIsNowOn() {
        let window = FakeWindow(frame: floating)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.cocoaFrame = original  // dragged onto primary by hand

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: primary.visibleFrame))
    }

    func testRestoreUndoesAContinuation() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: right.visibleFrame))
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)

        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAHalfReachedByDraggingContinuesToo() {
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        let director = makeDirector()
        director.snap(.leftHalf, window: window, on: right)

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.rightHalf.frame(in: primary.visibleFrame))
    }

    func testAWindowWhoseTitleFollowsItsSizeCarriesOnAtTheSecondPress() {
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        window.titleFollowsSize = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.rightHalf.frame(in: primary.visibleFrame))
    }

    func testMovingToAnotherDisplayForgetsWhereAHalfPutAWindowWhoseTitleFollowsItsSize() throws {
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        window.titleFollowsSize = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        let landed = try XCTUnwrap(window.cocoaFrame)
        director.perform(.nextDisplay, on: window)
        window.cocoaFrame = landed  // dragged back by hand, which gives it back that title

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAHalfCarriedOverByNextDisplayStillCountsAsThatHalf() {
        let odd = Display(
            frame: CGRect(x: 1920, y: 0, width: 1201, height: 901),
            visibleFrame: CGRect(x: 1920, y: 0, width: 1201, height: 876)
        )
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: primary.visibleFrame))
        let director = WindowDirector(displays: { [self.primary, odd] })
        director.perform(.nextDisplay, on: window)
        XCTAssertEqual(window.cocoaFrame?.width, 600.5, "Next Display maps proportionally, leaving it half a point wider than the tile")

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.rightHalf.frame(in: primary.visibleFrame))
    }

    func testAHalfCarriedFromAnOddWidthOntoAnEvenOneMoreThanTwiceAsWideIsRefittedFirst() throws {
        let (window, director, _, wide) = leftHalfCarriedByNextDisplay(onto: 2560)
        let carried = try XCTUnwrap(window.cocoaFrame)
        XCTAssertEqual(Tile.leftHalf.frame(in: wide.visibleFrame).width - carried.width, 2560 / 2402, accuracy: 1e-9,
                       "W2 / (2 * W1) short of the half, over a point")

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: wide.visibleFrame))
    }

    func testAHalfCarriedFromAnOddWidthOntoAnOddOneMoreThanTwiceAsWideStillCountsAsThatHalf() throws {
        let (window, director, narrow, wide) = leftHalfCarriedByNextDisplay(onto: 2561)
        let carried = try XCTUnwrap(window.cocoaFrame)
        XCTAssertEqual(Tile.leftHalf.frame(in: wide.visibleFrame).width - carried.width, 2561 / 2402 - 0.5, accuracy: 1e-9,
                       "the half's own flooring takes half a point off the miss, leaving it under a point")

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.rightHalf.frame(in: narrow.visibleFrame))
    }

    /// A window in the left half of a display 1201 wide, moved by Next Display onto a display
    /// `width` wide to its right.
    private func leftHalfCarriedByNextDisplay(onto width: CGFloat) -> (window: FakeWindow, director: WindowDirector, narrow: Display, wide: Display) {
        let narrow = Display(
            frame: CGRect(x: 0, y: 0, width: 1201, height: 901),
            visibleFrame: CGRect(x: 0, y: 0, width: 1201, height: 877)
        )
        let wide = Display(
            frame: CGRect(x: 1201, y: 0, width: width, height: 1441),
            visibleFrame: CGRect(x: 1201, y: 0, width: width, height: 1415)
        )
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: narrow.visibleFrame))
        let director = WindowDirector(displays: { [narrow, wide] })
        director.perform(.nextDisplay, on: window)
        return (window, director, narrow, wide)
    }

    func testARefusedHalfIsNotRememberedAsPlaced() {
        // The refused window stays where it was, which shares the half's top-left, so only the
        // refusal itself keeps that frame from being recorded as where the half left it.
        let window = FakeWindow(frame: flushTopLeft)
        let director = makeDirector()
        window.rejectWith = .cannotComplete
        XCTAssertEqual(director.perform(.tile(.leftHalf), on: window), .rejected(.cannotComplete))
        window.rejectWith = nil

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testARefusedContinuationKeepsThePlacementAndTheRestoreFrame() {
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        let director = makeDirector()
        director.snap(.leftHalf, window: window, on: right)

        window.rejectWith = .cannotComplete
        XCTAssertEqual(director.perform(.tile(.leftHalf), on: window), .rejected(.cannotComplete))
        window.rejectWith = nil

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.rightHalf.frame(in: primary.visibleFrame))
        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.writes.last, floating)
    }

    func testARefusedCommandThatLeftTheWindowWhereItWasKeepsThePlacement() {
        for command in [WindowCommand.center, .restore, .nextDisplay] {
            let window = FakeWindow(frame: floating)
            window.grid = terminalCell
            let director = makeDirector()
            director.perform(.tile(.leftHalf), on: window)

            window.rejectWith = .cannotComplete
            XCTAssertEqual(director.perform(command, on: window), .rejected(.cannotComplete), "\(command)")
            window.rejectWith = nil

            director.perform(.tile(.leftHalf), on: window)
            XCTAssertEqual(window.writes.last, Tile.rightHalf.frame(in: primary.visibleFrame), "\(command)")
        }
    }

    func testAWindowStillReportingItsOldFrameIsNotRememberedAsPlaced() {
        // Read straight back, the frame is still the old one. Dragged back to exactly that frame,
        // the window would be thrown onto the next display by a remembered placement.
        let window = FakeWindow(frame: floating)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        window.cocoaFrame = floating

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAnOldFrameOnlyOnTheHalfsLeftEdgeIsNotRememberedAsPlaced() {
        // Flush with the display's left edge, below its top.
        let start = CGRect(x: 1920, y: 100, width: 800, height: 600)
        let window = FakeWindow(frame: start)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        window.cocoaFrame = start

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAnOldFrameOnlyAtTheHalfsTopIsNotRememberedAsPlaced() {
        // Flush with the display's top, right of its left edge.
        let start = CGRect(x: 2200, y: 515, width: 800, height: 600)
        let window = FakeWindow(frame: start)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        window.cocoaFrame = start

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    // An app that applies frames late reports the old frame when read straight back. A window
    // flush in the display's top-left corner already shares the half's top-left, so that stale
    // frame is recorded as where the half left it. The tests below put the window back on it
    // after another command has moved it elsewhere, and expect the next Left Half to halve it.

    func testRestoreForgetsWhereAHalfPutTheWindow() {
        let window = FakeWindow(frame: flushTopLeft)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        director.perform(.restore, on: window)
        window.catchUp()

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testCenterForgetsWhereAHalfPutTheWindow() {
        let window = FakeWindow(frame: flushTopLeft)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        director.perform(.center, on: window)
        window.catchUp()
        window.cocoaFrame = flushTopLeft  // dragged back by hand

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testMovingToAnotherDisplayForgetsWhereAHalfPutTheWindow() throws {
        let window = FakeWindow(frame: flushTopLeft)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        window.cocoaFrame = flushTopLeft  // dragged back by hand
        director.perform(.nextDisplay, on: window)
        window.catchUp()
        director.perform(.previousDisplay, on: window)
        window.catchUp()
        let back = try XCTUnwrap(window.cocoaFrame)
        XCTAssertEqual(back.minX, flushTopLeft.minX, accuracy: 1, "the round trip lands back on the recorded frame")
        XCTAssertEqual(back.maxX, flushTopLeft.maxX, accuracy: 1)
        XCTAssertEqual(back.minY, flushTopLeft.minY, accuracy: 1)
        XCTAssertEqual(back.maxY, flushTopLeft.maxY, accuracy: 1)

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testATileWhoseReadBackMissesForgetsWhereAHalfPutTheWindow() {
        let window = FakeWindow(frame: flushTopLeft)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        // Read straight back, the window is still in the left half, off the right half's top-left.
        director.perform(.tile(.rightHalf), on: window)
        window.catchUp()
        window.cocoaFrame = flushTopLeft  // dragged back by hand

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testARefusedWriteThatStillResizedTheWindowForgetsWhereAHalfPutIt() {
        // Top Right is the size of Top Left here. Its size takes and its position is refused,
        // which leaves the window in the top-left quadrant: back on the old frame Left Half read
        // back, with no hand move, and not where Top Right sent it. What counts is that the
        // window left where it was, not whether it reached the frame asked for.
        let topLeft = Tile.topLeft.frame(in: right.visibleFrame)
        let window = FakeWindow(frame: topLeft)
        window.appliesLate = true
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.catchUp()
        window.appliesLate = false
        window.refusesPositionWith = .cannotComplete
        XCTAssertEqual(director.perform(.tile(.topRight), on: window), .rejected(.cannotComplete))
        XCTAssertEqual(window.cocoaFrame, topLeft)
        window.refusesPositionWith = nil

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testARefusedWriteThatLeftTheFrameUnreadableForgetsWhereAHalfPutIt() throws {
        // A hung app refuses Center and does not answer the read after it either, so nothing
        // shows that the window is still where the half left it.
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        let landed = try XCTUnwrap(window.cocoaFrame)
        window.rejectWith = .cannotComplete
        window.unreadableOnceRefused = true
        XCTAssertEqual(director.perform(.center, on: window), .rejected(.cannotComplete))
        window.rejectWith = nil
        window.cocoaFrame = landed  // answering again, and still where it landed

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    func testAHalfWhoseDisplayHasChangedSinceIsRefittedRatherThanCarriedOn() {
        // A new resolution leaves the window where it was, which is no longer the left half.
        var desk = [primary, right]
        let director = WindowDirector(displays: { desk })
        let window = FakeWindow(frame: floating)
        director.perform(.tile(.leftHalf), on: window)
        let roomier = Display(
            frame: CGRect(x: 1920, y: -300, width: 3008, height: 1692),
            visibleFrame: CGRect(x: 1920, y: -300, width: 3008, height: 1667)
        )
        desk = [primary, roomier]

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: roomier.visibleFrame))
    }

    func testForgettingAProcessDropsWhereItsWindowsWerePut() {
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)

        director.forgetWindows(ofProcess: 42)

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.leftHalf.frame(in: right.visibleFrame))
    }

    // MARK: What the log says

    // A half press that does not carry a window on explains itself only where the press alone
    // does not show why. Each test below clears the lines before the press it is about.

    func testAFirstPressIsLoggedOnlyForAWindowThatHadTheHalfsTopLeft() {
        // From anywhere else the fit shows. From the half's top-left corner, with nothing to say
        // how the window got there, it can be too small to see.
        let diagnostics = Diagnostics()
        makeDirector(diagnosingInto: diagnostics).perform(.tile(.leftHalf), on: FakeWindow(frame: floating))
        XCTAssertEqual(diagnostics.lines, [])

        makeDirector(diagnosingInto: diagnostics).perform(.tile(.leftHalf), on: FakeWindow(frame: flushTopLeft))
        XCTAssertEqual(diagnostics.lines.count, 1, "\(diagnostics.lines)")
        XCTAssertTrue(diagnostics.lines.allSatisfy { $0.contains("had the top-left") }, "\(diagnostics.lines)")
    }

    func testAHalfAfterMaximizeIsNotLogged() {
        // Maximize leaves the window with the half's top-left, but Loadstone put it there, and
        // the fit into the half shows.
        let window = FakeWindow(frame: floating)
        let diagnostics = Diagnostics()
        let director = makeDirector(diagnosingInto: diagnostics)
        director.perform(.tile(.maximize), on: window)
        diagnostics.lines.removeAll()

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(diagnostics.lines, [])
    }

    func testAPlacementByAnotherTileIsNotLoggedAsNoLongerHolding() {
        // Put in Top Left and dragged out by hand.
        let window = FakeWindow(frame: floating)
        let diagnostics = Diagnostics()
        let director = makeDirector(diagnosingInto: diagnostics)
        director.perform(.tile(.topLeft), on: window)
        window.cocoaFrame = floating
        diagnostics.lines.removeAll()

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(diagnostics.lines, [])

        // Carried on by Left Half, the window was placed by Right Half, the half it moved into.
        let carried = FakeWindow(frame: Tile.leftHalf.frame(in: right.visibleFrame), identity: .cgWindow(2, pid: 42))
        director.perform(.tile(.leftHalf), on: carried)
        carried.cocoaFrame = carried.cocoaFrame?.offsetBy(dx: -41, dy: -43)  // nudged by hand
        diagnostics.lines.removeAll()

        director.perform(.tile(.leftHalf), on: carried)
        XCTAssertEqual(diagnostics.lines, [])
    }

    func testAPlacementByTheSameHalfThatNoLongerHoldsIsLogged() {
        // Put in Left Half and dragged out by hand.
        let window = FakeWindow(frame: floating)
        window.grid = terminalCell
        let diagnostics = Diagnostics()
        let director = makeDirector(diagnosingInto: diagnostics)
        director.perform(.tile(.leftHalf), on: window)
        window.cocoaFrame = floating
        diagnostics.lines.removeAll()

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(diagnostics.lines.count, 1, "\(diagnostics.lines)")
        XCTAssertTrue(diagnostics.lines.allSatisfy { $0.contains("no longer held") }, "\(diagnostics.lines)")

        // Carried on by Left Half into primary's right half, nudged by hand, then Right Half.
        let carried = FakeWindow(frame: Tile.leftHalf.frame(in: right.visibleFrame), identity: .cgWindow(2, pid: 42))
        director.perform(.tile(.leftHalf), on: carried)
        carried.cocoaFrame = carried.cocoaFrame?.offsetBy(dx: -41, dy: -43)
        diagnostics.lines.removeAll()

        director.perform(.tile(.rightHalf), on: carried)
        XCTAssertEqual(diagnostics.lines.count, 1, "\(diagnostics.lines)")
        XCTAssertTrue(diagnostics.lines.allSatisfy { $0.contains("no longer held") }, "\(diagnostics.lines)")
    }

    func testAWindowThatReadsBackWhereItWasIsLogged() throws {
        // A Terminal window already in the half, with nothing recorded since Loadstone started.
        let terminal = FakeWindow(frame: floating)
        terminal.grid = terminalCell
        makeDirector().perform(.tile(.leftHalf), on: terminal)
        // A window that will not go below 1501pt, which Left Third leaves where Left Half would.
        let wide = FakeWindow(frame: floating, identity: .cgWindow(2, pid: 42))
        wide.minimumWidth = 1501
        let diagnostics = Diagnostics()
        let director = makeDirector(diagnosingInto: diagnostics)
        director.perform(.tile(.leftThird), on: wide)

        for window in [terminal, wide] {
            let before = try XCTUnwrap(window.cocoaFrame)
            diagnostics.lines.removeAll()

            director.perform(.tile(.leftHalf), on: window)
            XCTAssertEqual(window.cocoaFrame, before, "the press changed nothing that shows")
            XCTAssertEqual(diagnostics.lines.count, 1, "\(diagnostics.lines)")
            XCTAssertTrue(diagnostics.lines.allSatisfy { $0.contains("read back where it was") }, "\(diagnostics.lines)")
        }
    }

    func testAHalfAtTheEdgeOfTheDeskIsLogged() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: primary.visibleFrame))
        let diagnostics = Diagnostics()
        makeDirector(diagnosingInto: diagnostics).perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(diagnostics.lines.count, 1, "\(diagnostics.lines)")
        XCTAssertTrue(diagnostics.lines.allSatisfy { $0.contains("no display to the left") }, "\(diagnostics.lines)")
    }

    func testCarryingAWindowOnIsLogged() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: right.visibleFrame))
        let diagnostics = Diagnostics()
        makeDirector(diagnosingInto: diagnostics).perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(diagnostics.lines, ["leftHalf: carrying on to the display at \(primary.frame)"])
    }
}
