# Loadstone

A native macOS window manager in the spirit of [Magnet](https://magnet.crowdcafe.com/). Snap windows into halves, quarters, and thirds with keyboard shortcuts or by dragging to a screen edge.

Loadstone lives in the menu bar. It has no dock icon.

## Features

- Left / right / top / bottom halves
- Four quarters
- Thirds and two-thirds
- Maximize, center, restore
- Next / previous display
- Drag a window to an edge or corner to snap it
- Magnet-style keyboard shortcuts (customizable)
- Launch at login

## Requirements

- macOS 14 or later
- Accessibility permission (prompted on first launch)

## Build

```bash
eval "$(/opt/homebrew/bin/brew shellenv zsh)"
xcodegen
xcodebuild -scheme Loadstone -configuration Debug -destination 'platform=macOS' build
```

Then open the app from DerivedData, or run it from Xcode.

Grant **Accessibility** access in System Settings → Privacy & Security → Accessibility, or Loadstone cannot move other apps' windows.

## Default shortcuts

| Action | Shortcut |
| --- | --- |
| Left / Right / Top / Bottom half | ⌃⌥← ⌃⌥→ ⌃⌥↑ ⌃⌥↓ |
| Quarters | ⌃⌥U I J K |
| Thirds | ⌃⌥D F G |
| Two thirds | ⌃⌥E / ⌃⌥T |
| Maximize | ⌃⌥↩ |
| Center | ⌃⌥C |
| Restore | ⌃⌥⌫ |
| Next / previous display | ⌃⌥⌘→ / ⌃⌥⌘← |

## Notes

The app is not sandboxed. The Accessibility API used to move windows does not work inside App Sandbox without extra Apple entitlements.
