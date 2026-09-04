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
}
