# PrismCapture



## Download the app

1. Go to [**Releases**](https://github.com/facudelima/PrismCapture/releases)
2. Download `PrismCapture-*-macos.zip`
3. Unzip and move `PrismCapture.app` to **Applications**
4. First time: right-click → **Open** (Gatekeeper)

Requires **macOS 14+** and **Screen Recording** permission.

The installed version is shown in the menu bar and in Settings → About. The app can check for and install updates from Releases (no extra configuration needed).

The interface follows the **system language** (currently: English and Spanish).

> The repo is **public** so updates work without tokens.

## Requirements (development)

- macOS 14+
- Xcode 16+
- **Screen Recording** permission

## Open and build

```bash
open PrismCapture.xcodeproj
```

In Xcode: target **PrismCapture** → Run (⌘R).

From the terminal:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project PrismCapture.xcodeproj -scheme PrismCapture -configuration Debug build
```

Generate a Release zip (to install as an app):

```bash
./scripts/build-release.sh 1.0.0
# → dist/PrismCapture-1.0.0-macos.zip
```

## Usage

The app lives in the menu bar (`LSUIElement`).

| Shortcut | Action |
|-------|--------|
| ⌘⇧2 | Capture area |
| ⌘⇧3 | Full screen |
| ⌘C | Copy |
| ⌘S | Save |
| Esc | Cancel / close |

After capturing, a floating editor appears with annotation tools (rectangle, circle, arrow, pencil, highlighter, blur, pixelate, text, markers, emoji), undo/redo, OCR, and upload. The **Move** tool re-captures the area (Lightshot-style).

## Architecture

SwiftUI + MVVM:

- `App/` — Menu bar, global state
- `Services/` — capture (ScreenCaptureKit), clipboard, files, OCR (Vision), upload, hotkeys
- `ViewModels/` — capture, annotation, history, settings
- `Views/` — selection overlay, editor, settings, history

## Notes

- Imgur requires replacing `YOUR_IMGUR_CLIENT_ID` in `UploadService.swift`.
- The accent color inherits from macOS.
- Theme: Light / Dark / Auto in Settings.
