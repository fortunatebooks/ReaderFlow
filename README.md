# ReaderFlow

ReaderFlow is an iOS EPUB reader focused on smooth vertical autoscroll and fast excerpt capture.

The app is being designed for readers, proofreaders, and reviewers who want to move through DRM-free EPUB books quickly, pause with a tap, and save selected passages with useful chapter/location context.

## Current Status

Planning and project setup are in progress.

Important documents:

- [Design spec](docs/design-spec.md)
- [Implementation plan](docs/implementation-plan.md)

## Product Direction

- iOS 18+.
- DRM-free reflowable EPUB support first.
- Continuous vertical autoscroll.
- Tap to pause/resume.
- Adjustable speed, text size, font, theme, line height, and margins.
- One-color highlights saved as excerpts.
- Plain text excerpt export through the iOS share sheet.
- Local-first storage with no account or backend in the MVP.

## Development

The implementation plan commits to:

- SwiftUI app shell.
- Swift 6.
- SwiftData for local metadata and excerpts.
- Readium Swift Toolkit for EPUB opening and metadata.
- A custom continuous `WKWebView` reader for the core reading surface.
- XcodeGen for reproducible project generation.

The Xcode project has not been generated yet. Follow `docs/implementation-plan.md` for the build order.

