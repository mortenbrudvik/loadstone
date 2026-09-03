# Loadstone

<p align="center">
  <img src="Loadstone/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="128" height="128" alt="Loadstone icon">
</p>

<p align="center">
  <strong>Snap any Mac window into place.</strong><br>
  Halves, corners, and thirds — from the keyboard or by dragging to an edge.<br>
  A native Swift menu-bar app. No dock icon. No Electron.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/status-early-blue" alt="Early">
</p>

Loadstone sits in the menu bar and stays out of the way. When you need two docs side by side, a browser in a third, or a window parked in a corner, it moves the frontmost window to a precise tile of the visible screen — dock and menu bar included in the math, not covered by the window.

<p align="center">
  <img src="docs/layouts.svg" alt="Halves, corner quarters, and thirds with their default shortcuts" width="960">
</p>

## Features

- **Halves** — left, right, top, bottom
- **Corners** — four quarters
- **Thirds** — left, center, right, plus two-thirds
- **Maximize, center, restore** — restore returns the window to the size it had before the first snap
- **Drag to snap** — edges for halves, corners for quarters, top to maximize, bottom for thirds
- **Multi-display** — send a window to the next or previous screen
- **Custom shortcuts** — Magnet-style defaults, all editable
- **Launch at login** — optional, from Settings
- **Portrait screens** — thirds run along the long sides

Loadstone turns off macOS’s built-in “drag to tile” while it is running, so the two systems don’t fight.

## Default shortcuts

All of these are Control-Option unless noted. Change them in **Settings → Shortcuts**.

| Layout | Shortcut |
| --- | --- |
| Left / right / top / bottom half | `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` |
| Top left / top right corner | `⌃⌥U` `⌃⌥I` |
| Bottom left / bottom right corner | `⌃⌥J` `⌃⌥K` |
| Left / center / right third | `⌃⌥D` `⌃⌥F` `⌃⌥G` |
| Left / right two thirds | `⌃⌥E` `⌃⌥T` |
| Maximize | `⌃⌥↩` |
| Center (keeps the current size) | `⌃⌥C` |
| Restore | `⌃⌥⌫` |
| Next / previous display | `⌃⌥⌘→` `⌃⌥⌘←` |

The corner keys are a square on the keyboard:

```
U  I
J  K
```

## Install from source

There is no signed download yet. You build it, copy it to Applications, then grant Accessibility.

**You need:** macOS 14+, Xcode 16+, [Homebrew](https://brew.sh), [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/mortenbrudvik/loadstone.git
cd loadstone
xcodegen
xcodebuild -scheme Loadstone -configuration Release -destination 'platform=macOS' build
```

Copy the built app into Applications (path will include your DerivedData folder):

```bash
ditto "$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Release/Loadstone.app' | head -1)" /Applications/Loadstone.app
open /Applications/Loadstone.app
```

The first launch is unsigned. **Right-click the app → Open**, or allow it in **System Settings → Privacy & Security**.

### Accessibility (required)

Loadstone moves other apps’ windows through the Accessibility API. macOS will not apply the permission until the app restarts.

1. System Settings → **Privacy & Security** → **Accessibility**
2. If Loadstone is already listed, select it and click **−**
3. Click **+** and choose **`/Applications/Loadstone.app`**
4. Turn it **on**
5. Menu bar → Loadstone → **Relaunch**

After that, `⌃⌥←` should pin the frontmost window to the left half.

Optional: **Settings → Launch at login**.

## Build and test

```bash
xcodegen                      # regenerate the Xcode project after adding files
xcodebuild -scheme Loadstone -destination 'platform=macOS' test
```

Open `Loadstone.xcodeproj` in Xcode if you prefer a GUI.

## How it works

Loadstone is a menu-bar-only app (`LSUIElement`). Shortcuts and drag gestures go to a small window director that:

1. Finds the window (Accessibility)
2. Converts between Cocoa and Accessibility coordinates
3. Lays out a tile against the screen’s **visible frame**
4. Sets size, then position, then size again so the window survives a display change

It is **not sandboxed**. App Sandbox blocks the Accessibility calls this kind of tool needs.

## Name

A lodestone is a naturally magnetic rock. Loadstone is the window magnet.

## License

No license file yet — all rights reserved until one is chosen.
