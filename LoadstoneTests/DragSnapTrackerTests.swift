import XCTest
@testable import Loadstone

final class DragSnapTrackerTests: XCTestCase {
    private struct FakeWindow: Equatable {
        let id: Int
    }

    private let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 80, width: 1920, height: 975)
    )
    private let right = Display(
        frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1415)
    )
    private var displays: [Display] { [primary, right] }

    /// Drives the tracker the way the monitor does, with a controllable window under the pointer
    /// whose origin the test can move.
    private final class Harness {
        var tracker = DragSnapTracker<FakeWindow>()
        var windowUnderPointer: FakeWindow? = FakeWindow(id: 1)
        var origin: CGPoint? = CGPoint(x: 400, y: 400)
        var lookups = 0
        var originReads = 0
        /// Event time. Tests that do not care pass no `at:` and get events a full second apart,
        /// which is far outside any poll interval, so throttling never affects them.
        private var clock: TimeInterval = 0

        func drag(to point: CGPoint, at time: TimeInterval? = nil, displays: [Display]) -> DragSnapTracker<FakeWindow>.Target? {
            clock = time ?? clock + 1
            return tracker.mouseDragged(
                to: point,
                at: clock,
                displays: displays,
                windowUnderPointer: { self.lookups += 1; return self.windowUnderPointer },
                originOf: { _ in self.originReads += 1; return self.origin }
            )
        }
    }

    /// Simulates the window following the pointer, which is what a real title-bar drag does.
    private func moveWindow(_ h: Harness, by delta: CGPoint) {
        h.origin = CGPoint(x: h.origin!.x + delta.x, y: h.origin!.y + delta.y)
    }

    func testClickWithoutMovementDoesNothing() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        XCTAssertNil(h.tracker.mouseUp())
        XCTAssertEqual(h.lookups, 0)
    }

    func testDragBelowTheThresholdDoesNotLookUpTheWindow() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        XCTAssertNil(h.drag(to: CGPoint(x: 504, y: 504), displays: displays))
        XCTAssertEqual(h.lookups, 0)
    }

    func testDragWithNoWindowUnderThePointerNeverSnaps() {
        let h = Harness()
        h.windowUnderPointer = nil
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        XCTAssertNil(h.drag(to: CGPoint(x: 300, y: 500), displays: displays))
        XCTAssertNil(h.drag(to: CGPoint(x: 2, y: 540), displays: displays))
        XCTAssertNil(h.tracker.mouseUp())
        XCTAssertEqual(h.lookups, 1, "one lookup once the threshold is passed, then nothing")
    }

    func testADragThatDoesNotMoveTheWindowIsNotAWindowDrag() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        XCTAssertNil(h.drag(to: CGPoint(x: 300, y: 500), displays: displays))
        XCTAssertNil(h.drag(to: CGPoint(x: 2, y: 540), displays: displays), "text selection reaching the edge must not preview")
        XCTAssertNil(h.tracker.mouseUp())
    }

    func testAWindowDragArmsOnceTheWindowHasMovedAndPreviewsTheTile() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        XCTAssertNil(h.drag(to: CGPoint(x: 300, y: 500), displays: displays))
        moveWindow(h, by: CGPoint(x: -498, y: 40))
        let target = h.drag(to: CGPoint(x: 2, y: 540), displays: displays)
        XCTAssertEqual(target, .init(tile: .leftHalf, display: primary))

        let commit = h.tracker.mouseUp()
        XCTAssertEqual(commit?.window, FakeWindow(id: 1))
        XCTAssertEqual(commit?.target, .init(tile: .leftHalf, display: primary))
    }

    func testLeavingTheZoneHidesThePreviewAndReleasingThereDoesNothing() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = h.drag(to: CGPoint(x: 300, y: 500), displays: displays)
        moveWindow(h, by: CGPoint(x: -200, y: 0))
        XCTAssertNotNil(h.drag(to: CGPoint(x: 2, y: 540), displays: displays))

        XCTAssertNil(h.drag(to: CGPoint(x: 400, y: 400), displays: displays))
        XCTAssertNil(h.tracker.mouseUp())
    }

    func testTargetFollowsThePointerDisplayNotTheWindow() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 1800, y: 500))
        _ = h.drag(to: CGPoint(x: 1850, y: 500), displays: displays)
        moveWindow(h, by: CGPoint(x: 50, y: 0))
        let target = h.drag(to: CGPoint(x: 1922, y: 500), displays: displays)
        XCTAssertEqual(target, .init(tile: .leftHalf, display: right))
    }

    func testTheWindowOriginIsOnlyReadInsideASnapZone() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = h.drag(to: CGPoint(x: 300, y: 500), displays: displays)
        XCTAssertEqual(h.originReads, 1, "baseline read when the threshold is passed")
        _ = h.drag(to: CGPoint(x: 600, y: 600), displays: displays)
        _ = h.drag(to: CGPoint(x: 700, y: 700), displays: displays)
        XCTAssertEqual(h.originReads, 1, "no reads while the pointer is in the interior")
        moveWindow(h, by: CGPoint(x: 100, y: 100))
        _ = h.drag(to: CGPoint(x: 2, y: 540), displays: displays)
        XCTAssertEqual(h.originReads, 2, "one read on entering a zone")
        _ = h.drag(to: CGPoint(x: 4, y: 540), displays: displays)
        XCTAssertEqual(h.originReads, 2, "none once armed")
    }

    func testMouseUpResetsSoTheNextDragStartsFresh() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = h.drag(to: CGPoint(x: 300, y: 500), displays: displays)
        moveWindow(h, by: CGPoint(x: -200, y: 0))
        _ = h.drag(to: CGPoint(x: 2, y: 540), displays: displays)
        _ = h.tracker.mouseUp()

        XCTAssertNil(h.drag(to: CGPoint(x: 2, y: 540), displays: displays), "a drag without a mouse-down is ignored")
        XCTAssertNil(h.tracker.mouseUp())
    }

    func testResetAbandonsAnArmedDrag() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = h.drag(to: CGPoint(x: 300, y: 500), displays: displays)
        moveWindow(h, by: CGPoint(x: -200, y: 0))
        _ = h.drag(to: CGPoint(x: 2, y: 540), displays: displays)

        h.tracker.reset()

        XCTAssertNil(h.tracker.mouseUp())
    }

    func testTheWindowOriginIsNotPolledOnEveryEventWhileWaitingForTheWindowToMove() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = h.drag(to: CGPoint(x: 300, y: 500), at: 0, displays: displays)
        XCTAssertEqual(h.originReads, 1, "baseline read when the threshold is passed")

        // A slider drag parked in a snap zone: the window never moves, and a real drag delivers
        // events far faster than the poll interval. Each read is an AX round trip on the main
        // thread that can block for the messaging timeout, so they must not track event rate.
        _ = h.drag(to: CGPoint(x: 2, y: 540), at: 0.100, displays: displays)
        _ = h.drag(to: CGPoint(x: 3, y: 541), at: 0.108, displays: displays)
        _ = h.drag(to: CGPoint(x: 4, y: 542), at: 0.116, displays: displays)
        _ = h.drag(to: CGPoint(x: 5, y: 543), at: 0.124, displays: displays)
        XCTAssertEqual(h.originReads, 2, "one poll on entering the zone, then throttled")

        _ = h.drag(to: CGPoint(x: 6, y: 544), at: 0.400, displays: displays)
        XCTAssertEqual(h.originReads, 3, "polls again once the interval has elapsed")
    }

    func testThrottlingStillArmsOnceTheWindowHasMoved() {
        let h = Harness()
        h.tracker.mouseDown(at: CGPoint(x: 500, y: 500))
        _ = h.drag(to: CGPoint(x: 300, y: 500), at: 0, displays: displays)
        moveWindow(h, by: CGPoint(x: -298, y: 40))

        XCTAssertNil(h.drag(to: CGPoint(x: 2, y: 540), at: 0.001, displays: displays),
                     "the first in-zone event polls, but the throttle has not elapsed for a second look")
        XCTAssertEqual(h.drag(to: CGPoint(x: 2, y: 540), at: 0.200, displays: displays),
                       .init(tile: .leftHalf, display: primary))
    }
}
