import XCTest
@testable import Loadstone

final class SnapZonesTests: XCTestCase {
    private let landscape = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    private let portrait = CGRect(x: 0, y: 0, width: 1080, height: 1920)
    /// A second display to the right of the primary one, offset vertically.
    private let secondary = CGRect(x: 1920, y: -300, width: 2560, height: 1440)

    private func tile(_ x: CGFloat, _ y: CGFloat, on screen: CGRect) -> Tile? {
        SnapZones.tile(at: CGPoint(x: x, y: y), screenFrame: screen)
    }

    func testLandscapeEdgesSnapToHalvesMaximizeAndThirds() {
        XCTAssertEqual(tile(2, 540, on: landscape), .leftHalf)
        XCTAssertEqual(tile(1918, 540, on: landscape), .rightHalf)
        XCTAssertEqual(tile(960, 1078, on: landscape), .maximize)
        XCTAssertEqual(tile(400, 2, on: landscape), .leftThird)
        XCTAssertEqual(tile(960, 2, on: landscape), .centerThird)
        XCTAssertEqual(tile(1500, 2, on: landscape), .rightThird)
    }

    func testCornersSnapToQuarters() {
        XCTAssertEqual(tile(2, 1078, on: landscape), .topLeft)
        XCTAssertEqual(tile(1918, 1078, on: landscape), .topRight)
        XCTAssertEqual(tile(2, 2, on: landscape), .bottomLeft)
        XCTAssertEqual(tile(1918, 2, on: landscape), .bottomRight)
    }

    func testCornerSquareBeatsMaximizeAndHalves() {
        XCTAssertEqual(tile(80, 1000, on: landscape), .topLeft)
        XCTAssertEqual(tile(1840, 1000, on: landscape), .topRight)
        XCTAssertEqual(tile(80, 60, on: landscape), .bottomLeft)
        XCTAssertEqual(tile(1840, 60, on: landscape), .bottomRight)
        XCTAssertEqual(tile(960, 1075, on: landscape), .maximize)
        XCTAssertEqual(tile(4, 540, on: landscape), .leftHalf)
    }

    func testInteriorDoesNotSnap() {
        XCTAssertNil(tile(400, 400, on: landscape))
    }

    func testCornerAndEdgeThresholdsAreInclusive() {
        XCTAssertEqual(tile(140, 940, on: landscape), .topLeft)
        XCTAssertNil(tile(141, 939, on: landscape))
        XCTAssertEqual(tile(16, 540, on: landscape), .leftHalf)
        XCTAssertNil(tile(17, 540, on: landscape))
    }

    func testPointerJustOutsideTheScreenStillSnaps() {
        XCTAssertEqual(tile(-10, 540, on: landscape), .leftHalf)
        XCTAssertNil(tile(-17, 540, on: landscape))
        XCTAssertEqual(tile(960, 1090, on: landscape), .maximize)
    }

    func testThirdsBoundaryAtExactlyOneThirdBelongsToTheCenter() {
        XCTAssertEqual(tile(640, 2, on: landscape), .centerThird)
        XCTAssertEqual(tile(639, 2, on: landscape), .leftThird)
    }

    func testPortraitSideEdgesSplitIntoCornerThirdCorner() {
        XCTAssertEqual(tile(2, 300, on: portrait), .bottomLeft)
        XCTAssertEqual(tile(2, 960, on: portrait), .leftThird)
        XCTAssertEqual(tile(2, 1500, on: portrait), .topLeft)
        XCTAssertEqual(tile(1078, 300, on: portrait), .bottomRight)
        XCTAssertEqual(tile(1078, 960, on: portrait), .rightThird)
        XCTAssertEqual(tile(1078, 1500, on: portrait), .topRight)
    }

    func testPortraitBottomEdgeGivesHalvesAndTopMaximizes() {
        XCTAssertEqual(tile(300, 2, on: portrait), .leftHalf)
        XCTAssertEqual(tile(800, 2, on: portrait), .rightHalf)
        XCTAssertEqual(tile(540, 1918, on: portrait), .maximize)
    }

    func testZonesAreRelativeToTheScreenOrigin() {
        XCTAssertEqual(tile(1922, 400, on: secondary), .leftHalf)
        XCTAssertEqual(tile(4478, 1138, on: secondary), .topRight)
        XCTAssertEqual(tile(3200, -298, on: secondary), .centerThird)
        XCTAssertNil(tile(2, 400, on: secondary), "a point on the primary display is not on the secondary")
    }
}
