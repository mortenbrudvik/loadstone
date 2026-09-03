import Foundation

/// A named screen tile, computed against a bottom-left origin work area (Cocoa space).
enum Tile: String, CaseIterable, Sendable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case leftThird
    case centerThird
    case rightThird
    case leftTwoThirds
    case rightTwoThirds
    case maximize
}

enum WindowCommand: Equatable, Sendable {
    case tile(Tile)
    case center
    case restore
    case nextDisplay
    case previousDisplay

    var menuTitle: String {
        switch self {
        case .tile(.leftHalf): return "Left Half"
        case .tile(.rightHalf): return "Right Half"
        case .tile(.topHalf): return "Top Half"
        case .tile(.bottomHalf): return "Bottom Half"
        case .tile(.topLeft): return "Top Left Corner"
        case .tile(.topRight): return "Top Right Corner"
        case .tile(.bottomLeft): return "Bottom Left Corner"
        case .tile(.bottomRight): return "Bottom Right Corner"
        case .tile(.leftThird): return "Left Third"
        case .tile(.centerThird): return "Center Third"
        case .tile(.rightThird): return "Right Third"
        case .tile(.leftTwoThirds): return "Left Two Thirds"
        case .tile(.rightTwoThirds): return "Right Two Thirds"
        case .tile(.maximize): return "Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        }
    }
}

extension Tile {
    /// Lays this tile into `workArea`. Origin is bottom-left.
    func frame(in workArea: CGRect) -> CGRect {
        let x = workArea.minX
        let y = workArea.minY
        let w = workArea.width
        let h = workArea.height
        let halfW = (w / 2).rounded(.towardZero)
        let halfH = (h / 2).rounded(.towardZero)
        let thirdW = (w / 3).rounded(.towardZero)
        let twoThirdsW = w - thirdW

        switch self {
        case .leftHalf:
            return CGRect(x: x, y: y, width: halfW, height: h)
        case .rightHalf:
            return CGRect(x: x + halfW, y: y, width: w - halfW, height: h)
        case .topHalf:
            return CGRect(x: x, y: y + halfH, width: w, height: h - halfH)
        case .bottomHalf:
            return CGRect(x: x, y: y, width: w, height: halfH)
        case .topLeft:
            return CGRect(x: x, y: y + halfH, width: halfW, height: h - halfH)
        case .topRight:
            return CGRect(x: x + halfW, y: y + halfH, width: w - halfW, height: h - halfH)
        case .bottomLeft:
            return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .bottomRight:
            return CGRect(x: x + halfW, y: y, width: w - halfW, height: halfH)
        case .leftThird:
            return CGRect(x: x, y: y, width: thirdW, height: h)
        case .centerThird:
            return CGRect(x: x + thirdW, y: y, width: thirdW, height: h)
        case .rightThird:
            return CGRect(x: x + 2 * thirdW, y: y, width: w - 2 * thirdW, height: h)
        case .leftTwoThirds:
            return CGRect(x: x, y: y, width: twoThirdsW, height: h)
        case .rightTwoThirds:
            return CGRect(x: x + thirdW, y: y, width: w - thirdW, height: h)
        case .maximize:
            return workArea
        }
    }
}

enum SnapZones {
    static let edgeThickness: CGFloat = 16
    static let cornerSize: CGFloat = 140

    /// Detects a Magnet-style snap tile from a Cocoa-space mouse point against the full screen frame.
    static func tile(at point: CGPoint, screenFrame: CGRect) -> Tile? {
        let f = screenFrame
        let padded = f.insetBy(dx: -edgeThickness, dy: -edgeThickness)
        guard padded.contains(point) else { return nil }

        let x = min(max(point.x, f.minX), f.maxX)
        let y = min(max(point.y, f.minY), f.maxY)
        let fromLeft = x - f.minX
        let fromRight = f.maxX - x
        let fromBottom = y - f.minY
        let fromTop = f.maxY - y

        if fromLeft <= cornerSize && fromTop <= cornerSize { return .topLeft }
        if fromRight <= cornerSize && fromTop <= cornerSize { return .topRight }
        if fromLeft <= cornerSize && fromBottom <= cornerSize { return .bottomLeft }
        if fromRight <= cornerSize && fromBottom <= cornerSize { return .bottomRight }

        let nearLeft = fromLeft <= edgeThickness
        let nearRight = fromRight <= edgeThickness
        let nearBottom = fromBottom <= edgeThickness
        let nearTop = fromTop <= edgeThickness

        if nearTop { return .maximize }

        let portrait = f.height > f.width
        if portrait {
            if nearLeft || nearRight {
                return thirdAlongHeight(y, frame: f, leftSide: nearLeft)
            }
            if nearBottom { return x < f.midX ? .leftHalf : .rightHalf }
            return nil
        }

        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearBottom { return thirdAlongWidth(x, frame: f) }
        return nil
    }

    private static func thirdAlongWidth(_ x: CGFloat, frame: CGRect) -> Tile {
        let t = (x - frame.minX) / max(frame.width, 1)
        if t < 1.0 / 3.0 { return .leftThird }
        if t < 2.0 / 3.0 { return .centerThird }
        return .rightThird
    }

    private static func thirdAlongHeight(_ y: CGFloat, frame: CGRect, leftSide: Bool) -> Tile {
        let t = (y - frame.minY) / max(frame.height, 1)
        if leftSide {
            if t < 1.0 / 3.0 { return .bottomLeft }
            if t < 2.0 / 3.0 { return .leftThird }
            return .topLeft
        }
        if t < 1.0 / 3.0 { return .bottomRight }
        if t < 2.0 / 3.0 { return .rightThird }
        return .topRight
    }
}

enum Layout {
    static func centered(_ current: CGRect, in workArea: CGRect) -> CGRect {
        let width = min(current.width, workArea.width)
        let height = min(current.height, workArea.height)
        return CGRect(
            x: workArea.midX - width / 2,
            y: workArea.midY - height / 2,
            width: width,
            height: height
        )
    }

    static func mapped(_ current: CGRect, from source: CGRect, to destination: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return destination }
        let rx = (current.minX - source.minX) / source.width
        let ry = (current.minY - source.minY) / source.height
        let rw = current.width / source.width
        let rh = current.height / source.height
        return CGRect(
            x: destination.minX + rx * destination.width,
            y: destination.minY + ry * destination.height,
            width: rw * destination.width,
            height: rh * destination.height
        )
    }
}
