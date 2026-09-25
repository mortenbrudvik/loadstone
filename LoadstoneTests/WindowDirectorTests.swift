import XCTest
import ApplicationServices
@testable import Loadstone

@MainActor
final class WindowDirectorTests: XCTestCase {
    private final class FakeWindow: MovableWindow {
        var identity: WindowIdentity?
        var cocoaFrame: CGRect?
        var writes: [CGRect] = []
        var rejectWith: AXError?
        /// Set to act like Terminal or iTerm2, which round a window's size down to whole character
        /// cells and keep its top-left corner, so it never fills a tile exactly.
        var grid: CGSize?
        /// Set to act like an app that applies a frame only after the write has returned, so the
        /// frame read straight back is still the old one. `catchUp()` applies it.
        var appliesLate = false
        private var pending: CGRect?

        init(frame: CGRect, identity: WindowIdentity? = .cgWindow(1, pid: 42)) {
            cocoaFrame = frame
            self.identity = identity
        }

        @discardableResult
        func setCocoaFrame(_ frame: CGRect) -> AXError {
            if let rejectWith { return rejectWith }
            writes.append(frame)
            var landed = frame
            if let grid {
                let width = (frame.width / grid.width).rounded(.down) * grid.width
                let height = (frame.height / grid.height).rounded(.down) * grid.height
                landed = CGRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
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

    func testAWindowMovedSinceItWasPlacedGoesBackIntoTheHalfInsteadOfContinuing() {
        let window = FakeWindow(frame: floating)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        window.cocoaFrame = floating  // dragged back out by hand

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: right.visibleFrame))
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
        let placed = window.cocoaFrame

        window.rejectWith = .cannotComplete
        XCTAssertEqual(director.perform(.tile(.leftHalf), on: window), .rejected(.cannotComplete))
        XCTAssertEqual(window.cocoaFrame, placed)
        window.rejectWith = nil

        director.perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(window.writes.last, Tile.rightHalf.frame(in: primary.visibleFrame))
        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.writes.last, floating)
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
}
