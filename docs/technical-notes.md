# ReaderFlow Technical Notes

## Current Implementation Notes

- The tracked repo contains implementation source and public product docs.
- The detailed implementation plan remains local and ignored at `docs/implementation-plan.md`.
- XcodeGen 2.45.4 and SwiftFormat 0.61.1 are installed locally through Homebrew.
- This machine currently does not have a full Xcode install selected; `xcodebuild` points at Command Line Tools and cannot build iOS targets yet.
- Readium 3.10 depends on a Readium fork of ZIPFoundation. ReaderFlow uses `ReadiumZIPFoundation` rather than the older upstream `ZIPFoundation` package to avoid SwiftPM package identity conflicts.
- ReaderFlow bundles Atkinson Hyperlegible, Literata, and Source Serif 4 under SIL OFL 1.1 for offline reader font choices. The reader serves them through the `readerflow://app/fonts/...` scheme.

## Human-Gated Items

- Install/select a full Xcode build environment before iOS build verification.
- Run the first real-device reader/highlight spike on an iPhone.
- Choose final signing team and bundle identifier before TestFlight.
