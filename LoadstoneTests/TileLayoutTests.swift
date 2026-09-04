import XCTest
@testable import Loadstone

final class TileLayoutTests: XCTestCase {
    private let area = CGRect(x: 100, y: 50, width: 1200, height: 900)
    /// Neither dimension divides by 2 or 3, so every rounding path is exercised.
    private let oddArea = CGRect(x: 100, y: 50, width: 1201, height: 901)
    /// A display to the left of and below the primary one has negative coordinates.
    private let negativeArea = CGRect(x: -1440, y: -300, width: 1440, height: 900)

    func testHalvesCoverTheWorkArea() {
        let left = Tile.leftHalf.frame(in: area)
        let right = Tile.rightHalf.frame(in: area)
        XCTAssertEqual(left.width + right.width, area.width)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.height, area.height)
        XCTAssertEqual(right.maxX, area.maxX)
    }

    func testHalvesPartitionAnOddWidthWithoutASeam() {
        let left = Tile.leftHalf.frame(in: oddArea)
        let right = Tile.rightHalf.frame(in: oddArea)
        XCTAssertEqual(left.maxX, right.minX)
        XCTAssertEqual(left.width + right.width, oddArea.width)
        let top = Tile.topHalf.frame(in: oddArea)
        let bottom = Tile.bottomHalf.frame(in: oddArea)
        XCTAssertEqual(bottom.maxY, top.minY)
        XCTAssertEqual(top.height + bottom.height, oddArea.height)
    }

    func testQuartersAreAdjacentOnOddDimensions() {
        let topLeft = Tile.topLeft.frame(in: oddArea)
        let topRight = Tile.topRight.frame(in: oddArea)
        let bottomLeft = Tile.bottomLeft.frame(in: oddArea)
        let bottomRight = Tile.bottomRight.frame(in: oddArea)
        XCTAssertEqual(topLeft.maxX, topRight.minX)
        XCTAssertEqual(bottomLeft.maxX, bottomRight.minX)
        XCTAssertEqual(bottomLeft.maxY, topLeft.minY)
        XCTAssertEqual(bottomRight.maxY, topRight.minY)
        XCTAssertEqual(topLeft.width + topRight.width, oddArea.width)
        XCTAssertEqual(bottomLeft.height + topLeft.height, oddArea.height)
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

    func testThirdsPartitionWidthsNotDivisibleByThree() {
        for width in [1201, 2559, 3440, 7] as [CGFloat] {
            let area = CGRect(x: 100, y: 50, width: width, height: 901)
            let left = Tile.leftThird.frame(in: area)
            let center = Tile.centerThird.frame(in: area)
            let right = Tile.rightThird.frame(in: area)
            XCTAssertEqual(left.maxX, center.minX, "width \(width)")
            XCTAssertEqual(center.maxX, right.minX, "width \(width)")
            XCTAssertEqual(right.maxX, area.maxX, "width \(width)")
        }
    }

    func testTwoThirdsComplementAThird() {
        let leftTwo = Tile.leftTwoThirds.frame(in: area)
        let right = Tile.rightThird.frame(in: area)
        XCTAssertEqual(leftTwo.maxX, right.minX)
        XCTAssertEqual(leftTwo.width + right.width, area.width)
    }

    func testLeftTwoThirdsMeetsRightThirdOnWidthsNotDivisibleByThree() {
        for width in [1201, 2559, 3440, 7] as [CGFloat] {
            let area = CGRect(x: 100, y: 50, width: width, height: 901)
            let leftTwo = Tile.leftTwoThirds.frame(in: area)
            let right = Tile.rightThird.frame(in: area)
            XCTAssertEqual(leftTwo.maxX, right.minX, "width \(width)")
            XCTAssertEqual(leftTwo.width + right.width, area.width, "width \(width)")
        }
    }

    func testLeftThirdMeetsRightTwoThirdsOnWidthsNotDivisibleByThree() {
        for width in [1201, 2559, 3440, 7] as [CGFloat] {
            let area = CGRect(x: 100, y: 50, width: width, height: 901)
            let left = Tile.leftThird.frame(in: area)
            let rightTwo = Tile.rightTwoThirds.frame(in: area)
            XCTAssertEqual(left.maxX, rightTwo.minX, "width \(width)")
            XCTAssertEqual(left.width + rightTwo.width, area.width, "width \(width)")
        }
    }

    func testMaximizeUsesTheWholeArea() {
        XCTAssertEqual(Tile.maximize.frame(in: area), area)
    }

    func testEveryTileStaysInsideTheWorkArea() {
        for workArea in [area, oddArea, negativeArea] {
            for tile in Tile.allCases {
                let frame = tile.frame(in: workArea)
                XCTAssertTrue(workArea.contains(frame), "\(tile) \(frame) escapes \(workArea)")
                XCTAssertGreaterThan(frame.width, 0, "\(tile)")
                XCTAssertGreaterThan(frame.height, 0, "\(tile)")
            }
        }
    }

    func testCenterKeepsSize() {
        let current = CGRect(x: 0, y: 0, width: 200, height: 100)
        let centered = Layout.centered(current, in: area)
        XCTAssertEqual(centered.width, 200)
        XCTAssertEqual(centered.height, 100)
        XCTAssertEqual(centered.midX, area.midX)
        XCTAssertEqual(centered.midY, area.midY)
    }

    func testCenterClampsAnOversizedWindowToTheWorkArea() {
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        XCTAssertEqual(Layout.centered(huge, in: oddArea), oddArea)
    }

    func testMappedIsIdentityWhenSourceEqualsDestination() {
        let window = CGRect(x: 300, y: 200, width: 500, height: 400)
        let mapped = Layout.mapped(window, from: area, to: area)
        XCTAssertEqual(mapped.minX, window.minX, accuracy: 1e-9)
        XCTAssertEqual(mapped.minY, window.minY, accuracy: 1e-9)
        XCTAssertEqual(mapped.width, window.width, accuracy: 1e-9)
        XCTAssertEqual(mapped.height, window.height, accuracy: 1e-9)
    }

    func testMappedFillsDestinationWhenSourceIsDegenerate() {
        let window = CGRect(x: 300, y: 200, width: 500, height: 400)
        XCTAssertEqual(Layout.mapped(window, from: .zero, to: negativeArea), negativeArea)
    }

    func testMappedKeepsAHalfAHalfOnADisplayTwiceTheSize() {
        let small = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let large = CGRect(x: 3000, y: -100, width: 2400, height: 1800)
        let half = Tile.leftHalf.frame(in: small)
        let mapped = Layout.mapped(half, from: small, to: large)
        let expected = Tile.leftHalf.frame(in: large)
        XCTAssertEqual(mapped.minX, expected.minX, accuracy: 1e-9)
        XCTAssertEqual(mapped.minY, expected.minY, accuracy: 1e-9)
        XCTAssertEqual(mapped.width, expected.width, accuracy: 1e-9)
        XCTAssertEqual(mapped.height, expected.height, accuracy: 1e-9)
    }

    func testMappedRoundTripsBetweenDisplays() {
        let window = CGRect(x: 300, y: 200, width: 500, height: 400)
        let there = Layout.mapped(window, from: area, to: negativeArea)
        let back = Layout.mapped(there, from: negativeArea, to: area)
        XCTAssertEqual(back.minX, window.minX, accuracy: 1e-9)
        XCTAssertEqual(back.minY, window.minY, accuracy: 1e-9)
        XCTAssertEqual(back.width, window.width, accuracy: 1e-9)
        XCTAssertEqual(back.height, window.height, accuracy: 1e-9)
    }
}
