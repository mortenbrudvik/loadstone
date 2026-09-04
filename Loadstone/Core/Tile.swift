import Foundation
import KeyboardShortcuts

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

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left Corner"
        case .topRight: return "Top Right Corner"
        case .bottomLeft: return "Bottom Left Corner"
        case .bottomRight: return "Bottom Right Corner"
        case .leftThird: return "Left Third"
        case .centerThird: return "Center Third"
        case .rightThird: return "Right Third"
        case .leftTwoThirds: return "Left Two Thirds"
        case .rightTwoThirds: return "Right Two Thirds"
        case .maximize: return "Maximize"
        }
    }
}

/// Everything a user can ask Loadstone to do to a window. This is the single source of truth
/// for the hotkey list, the status-bar menu, and the Shortcuts settings pane: adding a case
/// (or a `Tile`) fails to compile until `id`, `title`, `defaultShortcut`, and `section` cover it,
/// and then it appears everywhere automatically.
enum WindowCommand: Hashable, Sendable {
    case tile(Tile)
    case center
    case restore
    case nextDisplay
    case previousDisplay

    /// Every command, in menu and settings order.
    static let all: [WindowCommand] =
        Tile.allCases.map(WindowCommand.tile) + [.center, .restore, .nextDisplay, .previousDisplay]

    /// Persistence key. KeyboardShortcuts stores a user's custom binding in UserDefaults under
    /// "KeyboardShortcuts_<id>", so an id must never change once shipped: renaming one silently
    /// discards that customization. `WindowCommandTests` pins the full list.
    var id: String {
        switch self {
        case .tile(let tile): return tile.rawValue
        case .center: return "center"
        case .restore: return "restore"
        case .nextDisplay: return "nextDisplay"
        case .previousDisplay: return "previousDisplay"
        }
    }

    var title: String {
        switch self {
        case .tile(let tile): return tile.title
        case .center: return "Center"
        case .restore: return "Restore"
        case .nextDisplay: return "Next Display"
        case .previousDisplay: return "Previous Display"
        }
    }

    /// Magnet-style defaults: Control-Option plus a key, Control-Option-Command for displays.
    /// The corner keys U I / J K form a square on the keyboard.
    var defaultShortcut: KeyboardShortcuts.Shortcut {
        switch self {
        case .tile(.leftHalf): return .init(.leftArrow, modifiers: [.control, .option])
        case .tile(.rightHalf): return .init(.rightArrow, modifiers: [.control, .option])
        case .tile(.topHalf): return .init(.upArrow, modifiers: [.control, .option])
        case .tile(.bottomHalf): return .init(.downArrow, modifiers: [.control, .option])
        case .tile(.topLeft): return .init(.u, modifiers: [.control, .option])
        case .tile(.topRight): return .init(.i, modifiers: [.control, .option])
        case .tile(.bottomLeft): return .init(.j, modifiers: [.control, .option])
        case .tile(.bottomRight): return .init(.k, modifiers: [.control, .option])
        case .tile(.leftThird): return .init(.d, modifiers: [.control, .option])
        case .tile(.centerThird): return .init(.f, modifiers: [.control, .option])
        case .tile(.rightThird): return .init(.g, modifiers: [.control, .option])
        case .tile(.leftTwoThirds): return .init(.e, modifiers: [.control, .option])
        case .tile(.rightTwoThirds): return .init(.t, modifiers: [.control, .option])
        case .tile(.maximize): return .init(.return, modifiers: [.control, .option])
        case .center: return .init(.c, modifiers: [.control, .option])
        case .restore: return .init(.delete, modifiers: [.control, .option])
        case .nextDisplay: return .init(.rightArrow, modifiers: [.control, .option, .command])
        case .previousDisplay: return .init(.leftArrow, modifiers: [.control, .option, .command])
        }
    }

    /// The KeyboardShortcuts handle for this command. Built once per command: creating a `Name`
    /// is what tells the library about the default binding.
    var hotkeyName: KeyboardShortcuts.Name {
        Self.hotkeyNames[self]!
    }

    private static let hotkeyNames: [WindowCommand: KeyboardShortcuts.Name] = Dictionary(
        uniqueKeysWithValues: all.map { ($0, KeyboardShortcuts.Name($0.id, default: $0.defaultShortcut)) }
    )

    /// Groups separated by a divider in the status-bar menu.
    enum Section: CaseIterable {
        case halves, corners, thirds, whole, displays
    }

    var section: Section {
        switch self {
        case .tile(.leftHalf), .tile(.rightHalf), .tile(.topHalf), .tile(.bottomHalf):
            return .halves
        case .tile(.topLeft), .tile(.topRight), .tile(.bottomLeft), .tile(.bottomRight):
            return .corners
        case .tile(.leftThird), .tile(.centerThird), .tile(.rightThird), .tile(.leftTwoThirds), .tile(.rightTwoThirds):
            return .thirds
        case .tile(.maximize), .center, .restore:
            return .whole
        case .nextDisplay, .previousDisplay:
            return .displays
        }
    }

    static var sections: [[WindowCommand]] {
        Section.allCases.map { section in all.filter { $0.section == section } }
    }
}

extension Tile {
    /// Lays this tile into `workArea`.
    func frame(in workArea: CGRect) -> CGRect {
        let x = workArea.minX
        let y = workArea.minY
        let w = workArea.width
        let h = workArea.height
        // Floor the left/bottom pieces and give the remainder to the right/top ones, so
        // complementary tiles sum to the work area exactly with no 1pt seam or overlap on
        // widths that do not divide evenly. `leftTwoThirds` must end where `rightThird`
        // starts (2 * thirdW), not at `w - thirdW`, or the two overlap on widths ≢ 0 mod 3.
        let halfW = (w / 2).rounded(.towardZero)
        let halfH = (h / 2).rounded(.towardZero)
        let thirdW = (w / 3).rounded(.towardZero)
        let twoThirdsW = 2 * thirdW

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
    /// Depth of the edge bands, and how far past an outer edge the pointer may overshoot.
    static let edgeThickness: CGFloat = 16
    /// Side of the square corner zones. Tuned by feel, like `edgeThickness`.
    static let cornerSize: CGFloat = 140

    /// Detects a Magnet-style snap tile from a Cocoa-space pointer against the *full* screen
    /// frame (the tile itself is later laid into the visible frame). Priority: the corner
    /// squares (`cornerSize`²) beat everything, then the top band (maximize), then the side
    /// bands, then the bottom band. Bands are `edgeThickness` deep and extend the same distance
    /// outside the frame so an overshoot past an outer edge still counts.
    /// Portrait (height > width): the side bands split along their length into bottom quarter /
    /// full-height third / top quarter, and the bottom band gives halves rather than thirds.
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
                return thirdAlongHeight(y, frame: f, side: nearLeft ? .left : .right)
            }
            if nearBottom { return x < f.midX ? .leftHalf : .rightHalf }
            return nil
        }

        if nearLeft { return .leftHalf }
        if nearRight { return .rightHalf }
        if nearBottom { return thirdAlongWidth(x, frame: f) }
        return nil
    }

    private enum Side { case left, right }

    private static func thirdAlongWidth(_ x: CGFloat, frame: CGRect) -> Tile {
        let t = (x - frame.minX) / max(frame.width, 1)
        if t < 1.0 / 3.0 { return .leftThird }
        if t < 2.0 / 3.0 { return .centerThird }
        return .rightThird
    }

    private static func thirdAlongHeight(_ y: CGFloat, frame: CGRect, side: Side) -> Tile {
        let t = (y - frame.minY) / max(frame.height, 1)
        switch side {
        case .left:
            if t < 1.0 / 3.0 { return .bottomLeft }
            if t < 2.0 / 3.0 { return .leftThird }
            return .topLeft
        case .right:
            if t < 1.0 / 3.0 { return .bottomRight }
            if t < 2.0 / 3.0 { return .rightThird }
            return .topRight
        }
    }
}

enum Layout {
    /// Keeps the window's size (clamped to the work area) and centres it.
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

    /// Places `current` in `destination` at the same relative position and size it had in
    /// `source`, so a half stays a half and a maximized window stays maximized on the new
    /// display. A degenerate source yields the whole destination.
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
