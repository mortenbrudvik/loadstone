import XCTest
@testable import Loadstone

final class TileLayoutTests: XCTestCase {
    private let area = CGRect(x: 100, y: 50, width: 1200, height: 900)

    func testHalvesCoverTheWorkArea() {
        let left = Tile.leftHalf.frame(in: area)
        let right = Tile.rightHalf.frame(in: area)
        XCTAssertEqual(left.width + right.width, area.width)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.height, area.height)
        XCTAssertEqual(right.maxX, area.maxX)
    }

    func testQuartersMeetInTheCenter() {
        let topLeft = Tile.topLeft.frame(in: area)
        let bottomRight = Tile.bottomRight.frame(in: area)
        XCTAssertEqual(topLeft.maxX, bottomRight.minX)
        XCTAssertEqual(topLeft.minY, area.midY)
        XCTAssertEqual(bottomRight.maxY, area.midY)
    }

    func testThirdsFillTheWidth() {
        let left = Tile.leftThird.frame(in: area)
        let center = Tile.centerThird.frame(in: area)
        let right = Tile.rightThird.frame(in: area)
        XCTAssertEqual(left.maxX, center.minX)
        XCTAssertEqual(center.maxX, right.minX)
        XCTAssertEqual(right.maxX, area.maxX)
        XCTAssertEqual(left.width + center.width + right.width, area.width)
    }

    func testTwoThirdsComplementAThird() {
        let leftTwo = Tile.leftTwoThirds.frame(in: area)
        let right = Tile.rightThird.frame(in: area)
        XCTAssertEqual(leftTwo.maxX, right.minX)
        XCTAssertEqual(leftTwo.width + right.width, area.width)
    }

    func testMaximizeUsesTheWholeArea() {
        XCTAssertEqual(Tile.maximize.frame(in: area), area)
    }

    func testCenterKeepsSizeAndClamps() {
        let current = CGRect(x: 0, y: 0, width: 200, height: 100)
        let centered = Layout.centered(current, in: area)
        XCTAssertEqual(centered.width, 200)
        XCTAssertEqual(centered.height, 100)
        XCTAssertEqual(centered.midX, area.midX)
        XCTAssertEqual(centered.midY, area.midY)
    }

    func testLandscapeLeftEdgeSnapsToLeftHalf() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 2, y: 540), screenFrame: screen), .leftHalf)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 1918, y: 540), screenFrame: screen), .rightHalf)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 960, y: 1078), screenFrame: screen), .maximize)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 400, y: 2), screenFrame: screen), .leftThird)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 960, y: 2), screenFrame: screen), .centerThird)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 1500, y: 2), screenFrame: screen), .rightThird)
    }

    func testCornersSnapToQuarters() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 2, y: 1078), screenFrame: screen), .topLeft)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 1918, y: 1078), screenFrame: screen), .topRight)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 2, y: 2), screenFrame: screen), .bottomLeft)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 1918, y: 2), screenFrame: screen), .bottomRight)
    }

    func testCornerSquareBeatsMaximizeAndHalves() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 80, y: 1000), screenFrame: screen), .topLeft)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 1840, y: 1000), screenFrame: screen), .topRight)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 80, y: 60), screenFrame: screen), .bottomLeft)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 1840, y: 60), screenFrame: screen), .bottomRight)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 960, y: 1075), screenFrame: screen), .maximize)
        XCTAssertEqual(SnapZones.tile(at: CGPoint(x: 4, y: 540), screenFrame: screen), .leftHalf)
    }

    func testInteriorDoesNotSnap() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertNil(SnapZones.tile(at: CGPoint(x: 400, y: 400), screenFrame: screen))
    }
}
