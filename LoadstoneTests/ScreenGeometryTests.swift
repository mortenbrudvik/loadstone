import XCTest
@testable import Loadstone

final class ScreenGeometryTests: XCTestCase {
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
    private var displays: [Display] { [primary, right, left] }

    // MARK: Cocoa ↔ Accessibility

    func testCocoaToAXFlipsAboutThePrimaryTopEdge() {
        let cocoa = CGRect(x: 100, y: 50, width: 640, height: 480)
        let ax = ScreenGeometry.axRect(fromCocoa: cocoa, primaryMaxY: 1080)
        XCTAssertEqual(ax, CGRect(x: 100, y: 550, width: 640, height: 480))
    }

    func testAXToCocoaRoundTripsOnEveryDisplay() {
        for rect in [
            CGRect(x: 100, y: 50, width: 640, height: 480),
            CGRect(x: 2500, y: -200, width: 800, height: 600),
            CGRect(x: -1000, y: 300, width: 400, height: 300),
        ] {
            let ax = ScreenGeometry.axRect(fromCocoa: rect, primaryMaxY: 1080)
            XCTAssertEqual(ScreenGeometry.cocoaRect(fromAX: ax, primaryMaxY: 1080), rect)
        }
    }

    func testAXPointFlipsY() {
        let ax = ScreenGeometry.axPoint(fromCocoa: CGPoint(x: 10, y: 1000), primaryMaxY: 1080)
        XCTAssertEqual(ax, CGPoint(x: 10, y: 80))
    }

    // MARK: Display lookup

    func testPointOnTheTopEdgeOfADisplayResolvesToIt() {
        XCTAssertEqual(ScreenGeometry.display(containing: CGPoint(x: 960, y: 1080), in: displays), primary)
    }

    func testPointOnASharedEdgeGoesToTheDisplayThatContainsItExactly() {
        XCTAssertEqual(ScreenGeometry.display(containing: CGPoint(x: 1920, y: 500), in: displays), right)
        XCTAssertEqual(ScreenGeometry.display(containing: CGPoint(x: 0, y: 500), in: displays), primary)
    }

    func testPointOffEveryDisplayResolvesToNothing() {
        XCTAssertNil(ScreenGeometry.display(containing: CGPoint(x: 960, y: 5000), in: displays))
        XCTAssertNil(ScreenGeometry.display(containing: CGPoint.zero, in: []))
    }

    func testRectResolvesByItsCenter() {
        let straddling = CGRect(x: 1500, y: 100, width: 1000, height: 500)
        XCTAssertEqual(ScreenGeometry.display(containing: straddling, in: displays), right)
    }

    // MARK: Neighbors

    func testNeighborWrapsInBothDirections() {
        XCTAssertEqual(ScreenGeometry.neighbor(of: primary, delta: -1, in: displays), left)
        XCTAssertEqual(ScreenGeometry.neighbor(of: left, delta: 1, in: displays), primary)
        XCTAssertEqual(ScreenGeometry.neighbor(of: primary, delta: 1, in: displays), right)
    }

    func testNeighborOfTheOnlyDisplayIsItself() {
        XCTAssertEqual(ScreenGeometry.neighbor(of: primary, delta: 1, in: [primary]), primary)
    }

    func testNeighborOfAnUnknownDisplayIsNothing() {
        XCTAssertNil(ScreenGeometry.neighbor(of: left, delta: 1, in: [primary, right]))
    }

    func testNeighborsFollowLeftToRightOrderNotAppKitOrder() {
        // AppKit lists the primary first and the rest in connection order. Here the primary sits
        // between the other two, so AppKit's cycle (primary → left → right) differs from the
        // spatial one (left → primary → right).
        let appKitOrder = [primary, left, right]
        XCTAssertEqual(ScreenGeometry.neighbor(of: primary, delta: 1, in: appKitOrder), right)
        XCTAssertEqual(ScreenGeometry.neighbor(of: primary, delta: -1, in: appKitOrder), left)
    }

    func testNeighborWrapsFromTheRightmostToTheLeftmost() {
        let appKitOrder = [primary, left, right]
        XCTAssertEqual(ScreenGeometry.neighbor(of: right, delta: 1, in: appKitOrder), left)
        XCTAssertEqual(ScreenGeometry.neighbor(of: left, delta: -1, in: appKitOrder), right)
    }

    func testDisplaysStackedAtTheSameXGoTopToBottom() {
        // Reading order: a column of displays is walked top to bottom before moving right.
        let below = Display(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 80, width: 1920, height: 975)
        )
        let above = Display(
            frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 1080, width: 1920, height: 1055)
        )
        let appKitOrder = [below, above, left]
        XCTAssertEqual(ScreenGeometry.neighbor(of: left, delta: 1, in: appKitOrder), above)
        XCTAssertEqual(ScreenGeometry.neighbor(of: above, delta: 1, in: appKitOrder), below)
        XCTAssertEqual(ScreenGeometry.neighbor(of: below, delta: 1, in: appKitOrder), left)
    }

    // MARK: Adjacent

    /// A display whose visible frame is its whole frame: adjacency only reads the arrangement.
    private func display(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> Display {
        let frame = CGRect(x: x, y: y, width: width, height: height)
        return Display(frame: frame, visibleFrame: frame)
    }

    func testAdjacentIsTheDisplayOnThatSide() {
        XCTAssertEqual(ScreenGeometry.adjacent(to: primary, toward: .left, in: displays), left)
        XCTAssertEqual(ScreenGeometry.adjacent(to: primary, toward: .right, in: displays), right)
    }

    func testAdjacentIsTheNearestDisplayOnThatSide() {
        // Beyond the primary, and sharing more of the right display's height than the primary does.
        let farLeft = display(x: -2560, y: -300, width: 2560, height: 1440)
        XCTAssertEqual(ScreenGeometry.adjacent(to: right, toward: .left, in: [farLeft, primary, right]), primary)
    }

    func testAdjacentStopsAtTheEdgeOfTheDeskInsteadOfWrapping() {
        XCTAssertNil(ScreenGeometry.adjacent(to: left, toward: .left, in: displays))
        XCTAssertNil(ScreenGeometry.adjacent(to: right, toward: .right, in: displays))
    }

    func testADisplayAboveOrBelowIsNotAdjacent() {
        // A laptop under a monitor. Reading order puts the monitor just before the laptop, which
        // suits Previous Display but would send a move to the left up onto the monitor.
        let monitor = display(x: 0, y: 0, width: 2560, height: 1440)
        let laptop = display(x: 524, y: -982, width: 1512, height: 982)
        let desk = [monitor, laptop]
        XCTAssertNil(ScreenGeometry.adjacent(to: laptop, toward: .left, in: desk))
        XCTAssertNil(ScreenGeometry.adjacent(to: laptop, toward: .right, in: desk))
        XCTAssertNil(ScreenGeometry.adjacent(to: monitor, toward: .left, in: desk))
    }

    func testADisplayTouchingOnlyAtACornerIsNotAdjacent() {
        let corner = display(x: -1440, y: -900, width: 1440, height: 900)
        XCTAssertNil(ScreenGeometry.adjacent(to: primary, toward: .left, in: [primary, corner]))
    }

    func testOfAStackedPairTheDisplaySharingMoreHeightIsAdjacent() {
        let upper = display(x: -1920, y: 700, width: 1920, height: 1080)   // shares 380pt of the primary's height
        let lower = display(x: -1920, y: -380, width: 1920, height: 1080)  // shares 700pt
        XCTAssertEqual(ScreenGeometry.adjacent(to: primary, toward: .left, in: [primary, upper, lower]), lower)
        XCTAssertEqual(ScreenGeometry.adjacent(to: primary, toward: .left, in: [primary, lower, upper]), lower)
    }

    func testAStackedPairSharingEqualHeightResolvesTheSameInAnyListOrder() {
        let upper = display(x: -1920, y: 540, width: 1920, height: 1080)
        let lower = display(x: -1920, y: -540, width: 1920, height: 1080)
        let one = ScreenGeometry.adjacent(to: primary, toward: .left, in: [primary, upper, lower])
        let other = ScreenGeometry.adjacent(to: primary, toward: .left, in: [primary, lower, upper])
        XCTAssertNotNil(one)
        XCTAssertEqual(one, other)
    }
}
