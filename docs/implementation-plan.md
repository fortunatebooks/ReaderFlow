# ReaderFlow Implementation Plan

Status: Reviewed implementation roadmap  
Date: 2026-06-30  
Product spec: `docs/design-spec.md`

## 0. Create And Maintain This Plan

This file is the implementation roadmap. Keep it current as the app is built.

Rules:

- Do the steps in order unless a later step is explicitly unblocked by an earlier one.
- Update this file when a technical fact changes, when a milestone is complete, or when a decision is reversed.
- Keep the design spec focused on product behavior and this file focused on implementation.
- Do not start broad feature work until the core reader proof works on a real iPhone.
- Do not introduce account systems, cloud sync, DRM support, store integrations, PDF support, or multi-color annotation workflows during MVP.

## 1. Final Technical Decisions

### Platform

- Minimum OS: iOS 18.0.
- Device priority: iPhone first.
- iPad support: adaptive layouts where easy, but no separate iPad-specific workflow until after iPhone polish.
- Language mode: Swift 6 with strict concurrency enabled where dependencies allow it.
- IDE/toolchain: latest stable Xcode available at implementation time, with Xcode 16.4 as the minimum because Readium 3.10.0 requires it.

### App Architecture

- App UI: SwiftUI.
- Native bridge surfaces: UIKit only where needed for `WKWebView`, document import edge cases, or share sheet behavior.
- State style: SwiftUI Observation plus Swift concurrency.
- Persistence: SwiftData for library metadata, excerpts, settings, and reading progress.
- File storage: app container under Application Support for EPUB files, expanded EPUB resources, covers, generated reader cache, and font assets.
- Project setup: XcodeGen project spec checked into the repo, generating the `.xcodeproj` reproducibly.
- Package manager: Swift Package Manager only.
- Persistence writes that can happen during import, export, or reader progress updates go through a dedicated SwiftData `ModelActor` so autoscroll never waits on main-thread database work.

### EPUB Architecture

Use a hybrid engine:

- Readium Swift Toolkit for EPUB opening, validation, metadata, table of contents, reading order, and future compatibility with standard EPUB concepts.
- ReaderFlow-owned continuous `WKWebView` renderer for the reading surface.
- ZIPFoundation for expanding EPUB packages into the app container.
- SwiftSoup for parsing XHTML/HTML resources and building ReaderFlow's continuous document.
- Custom `WKURLSchemeHandler` for serving EPUB resources, reader JavaScript/CSS, and bundled fonts into the web view without a local HTTP server.
- ReaderFlow's own locator format is the source of truth for progress, highlights, and jump-back. The MVP includes an optional `readiumLocatorJSON` field for compatibility/debug metadata, but ReaderFlow locators are the only required anchor.

Decision rationale:

- Readium is the best current native EPUB toolkit for iOS metadata, publication structure, and EPUB correctness.
- ReaderFlow's defining behavior is smooth vertical autoscroll through the book. The app should own that behavior directly instead of relying on a paginated navigator whose scrolling model is not designed around this product.
- WKWebView is the right rendering layer because EPUB content is HTML/CSS, WebKit has mature international text shaping, and JavaScript gives precise control over autoscroll, selection, highlight wrapping, and progress reporting.

### Reader Scope

- MVP supports DRM-free reflowable EPUB 2 and EPUB 3.
- Fixed-layout EPUB is detected and rejected with a clear message for MVP.
- Books remain fully local.
- The reader uses vertical continuous scroll.
- New books open paused.
- Previously opened books restore the last position and begin autoscrolling automatically.
- Speed control is native UI: slider plus right-edge swipe up/down.
- One highlight color in MVP.
- One global reader preference set in MVP.

### Fonts

Use:

- System sans: `-apple-system`.
- System serif: `ui-serif`, falling back to Georgia/New York-like system rendering where available.
- Atkinson Hyperlegible, bundled with license file.
- Literata, bundled with license file.
- Source Serif 4, bundled with license file.

Do not bundle large Noto CJK families in MVP. Rely on iOS system fallback for broad script coverage, and add targeted font packs only if testing shows gaps.

### Storage Decisions

Use SwiftData entities backed by file-system assets:

- SwiftData stores metadata, preferences, excerpt text, locator payloads, and archive state.
- EPUB binaries, expanded resources, covers, generated reader HTML, and export files live on disk.
- Codable substructures are stored as JSON `Data` fields in SwiftData to keep model migrations simple.
- `BookEntity` is not deleted when the user removes a book file. It becomes archived, so excerpts can remain grouped and exportable.

### Export Decisions

- Export per book or archived book collection.
- Export format: plain `.txt`.
- Export destination: iOS share sheet.
- Include chapter, location/progress, saved date, selected excerpt, and context.
- Context format:

```text
Context: ...{before} [excerpt] {selected text} [/excerpt] {after}...
```

### Dependency Pins

Initial versions:

- Readium Swift Toolkit: `3.10.0`.
- SwiftSoup: `2.13.5`.
- ZIPFoundation: `0.9.20`.
- XcodeGen: `2.45.4` or newer patch release.

Update only intentionally, with a build/test pass after each change.

## 2. Repo And Project Setup

### 2.1 Add Baseline Files

Create:

- `README.md`
- `.gitignore`
- `.swiftformat`
- `project.yml`
- `Makefile`
- `docs/implementation-plan.md`
- `docs/design-spec.md`
- `docs/technical-notes.md`
- `docs/testing-checklist.md`

The README should include:

- Product summary.
- Development prerequisites.
- How to generate the Xcode project.
- How to build and test from terminal.
- Current MVP status.

### 2.2 Configure XcodeGen

Create a single iOS app target and test targets:

- `ReaderFlow`
- `ReaderFlowTests`
- `ReaderFlowUITests`

Initial project settings:

- Deployment target: iOS 18.0.
- Bundle ID placeholder: `com.readerflow.ReaderFlow`.
- Swift version: Swift 6.
- App icons and launch screen placeholders.
- Supported orientations: portrait for iPhone MVP. Allow iPad orientation later.
- Declare `CFBundleDocumentTypes` for EPUB so "Open in ReaderFlow" appears from the Files share/open UI.
- Declare imported document type support for `org.idpf.epub-container` / `.epub`.
- Set `LSSupportsOpeningDocumentsInPlace` to false because ReaderFlow copies imported files into its own app container.
- Keep iTunes/File Sharing off unless manual sideload testing requires it.

### 2.3 Add Dependencies

Add Swift Package dependencies through `project.yml`:

- Readium Swift Toolkit `3.10.0`.
- ZIPFoundation `0.9.20`.
- SwiftSoup `2.13.5`.

Add development-only tools:

- SwiftFormat command in `Makefile`.
- Xcode build and test commands in `Makefile`.

Do not add analytics, crash reporting, networking frameworks, or third-party UI kits in MVP.

### 2.4 Create Folder Structure

Use this structure:

```text
ReaderFlow/
  App/
  Core/
    EPUB/
    Export/
    Files/
    Models/
    Persistence/
    ReaderBridge/
    Resources/
    Settings/
  Features/
    Library/
    Reader/
    Excerpts/
    Settings/
  Resources/
    ReaderWeb/
      reader.html
      reader.css
      reader.js
    Fonts/
    Assets.xcassets/
ReaderFlowTests/
ReaderFlowUITests/
docs/
```

Keep feature UI thin. Core services own parsing, storage, exporting, and web/native bridge behavior.

## 3. Data Model And Persistence

### 3.1 Define SwiftData Models

Create these SwiftData models.

`BookEntity`:

- `id: UUID`, unique.
- `title: String`.
- `authorDisplay: String`.
- `authorsJSON: Data`.
- `languageCode: String?`.
- `titleSortKey: String`.
- `authorSortKey: String`.
- `originalFileName: String`.
- `epubFileName: String?`.
- `expandedDirectoryName: String?`.
- `coverFileName: String?`.
- `importedAt: Date`.
- `lastOpenedAt: Date?`.
- `lastOpenedSortKey: Date?`.
- `readingProgress: Double`.
- `lastLocatorJSON: Data?`.
- `tableOfContentsJSON: Data?`.
- `isArchived: Bool`.
- `archivedAt: Date?`.
- `deletedFileAt: Date?`.
- `importStatus: String`.
- `fileSizeBytes: Int64`.
- `expandedSizeBytes: Int64`.
- `xhtmlSizeBytes: Int64`.
- `spineItemCount: Int`.
- `estimatedDomNodeCount: Int`.
- `imageCount: Int`.
- `contentFingerprint: String`, unique.
- `schemaVersion: Int`.

`ExcerptEntity`:

- `id: UUID`, unique.
- `bookId: UUID`.
- `bookTitleSnapshot: String`.
- `authorDisplaySnapshot: String`.
- `chapterTitle: String?`.
- `selectedText: String`.
- `contextBefore: String`.
- `contextAfter: String`.
- `locatorJSON: Data`.
- `createdAt: Date`.
- `copiedToClipboard: Bool`.
- `sourceBookAvailable: Bool`.
- `sortProgress: Double`.
- `schemaVersion: Int`.

`ReaderSettingsEntity`:

- `id: UUID`, singleton.
- `theme: String`, values `system`, `light`, `dark`.
- `fontFamily: String`.
- `textSize: Double`.
- `lineHeight: Double`.
- `marginScale: Double`.
- `autoscrollSpeed: Double`.
- `autoCopyHighlights: Bool`.
- `hapticsEnabled: Bool`.
- `exportDetailLevel: String`.
- `schemaVersion: Int`.

SwiftData constraints and indexes:

- Enforce uniqueness for `BookEntity.id`.
- Enforce uniqueness for `BookEntity.contentFingerprint`.
- Enforce uniqueness for `ExcerptEntity.id`.
- Index active library queries by `isArchived`, `lastOpenedSortKey`, `titleSortKey`, and `authorSortKey`.
- Index excerpt queries by `bookId`, `sortProgress`, and `createdAt`.
- Use lightweight migrations for additive fields.
- Add explicit migration plans before renaming or changing stored field types.

### 3.2 Define Codable Payloads

Create Codable structs stored in JSON `Data` fields:

- `AuthorPayload`
- `TableOfContentsPayload`
- `ReaderLocator`
- `TextQuoteSelector`

`ReaderLocator` fields:

- `bookId`
- `bookFingerprint`
- `spineIndex`
- `href`
- `chapterTitle`
- `chapterProgression`
- `totalProgression`
- `scrollY`
- `documentHeight`
- `textQuote`
- `domTextPath`
- `contentHash`
- `readiumLocatorJSON`, optional compatibility payload
- `createdAt`

`TextQuoteSelector` fields:

- `exact`
- `prefix`
- `suffix`
- `normalizedStartOffset`
- `normalizedEndOffset`

### 3.3 Build Persistence Services

Create:

- `LibraryRepository`
- `ExcerptRepository`
- `SettingsRepository`
- `ReadingProgressStore`

Rules:

- UI code does not call SwiftData directly except through view queries for simple lists.
- Import, delete, export, and reader progress updates go through repositories.
- Progress saves are throttled to avoid writes every animation frame.
- Repository methods that write during import/export/progress run through a `ModelActor`.
- SwiftUI list queries may use `@Query` only for read-only presentation.
- All repository APIs return app-specific errors, not raw SwiftData errors.

### 3.4 Build File Storage Service

Create `AppFileStore`.

Directory layout:

```text
Application Support/
  ReaderFlow/
    Books/
      {bookId}/
        source.epub
        expanded/
        cover.jpg
        reader-cache/
    Fonts/
    Exports/
```

Responsibilities:

- Create book directories.
- Copy imported EPUBs.
- Expand EPUBs.
- Delete source/expanded files when a book is archived.
- Keep excerpts and metadata after archiving.
- Create temporary export files.
- Clean stale temporary exports.

## 4. Import Pipeline

### 4.1 Build EPUB Picker

Use SwiftUI `fileImporter` with `UTType.epub`.

Flow:

1. User taps Import.
2. App presents file importer.
3. App opens security-scoped access.
4. App copies the file into a staging directory.
5. App validates and imports from staging.
6. App deletes staging file after success or failure.

Also support opening an EPUB sent from Files or another app:

1. iOS launches ReaderFlow with the incoming file URL.
2. App copies the file into staging.
3. App follows the same import pipeline as `fileImporter`.
4. App never edits the original file in place.

### 4.2 Run EPUB Preflight

Before full import, calculate:

- Compressed EPUB size.
- Estimated expanded size.
- Combined XHTML byte count.
- Spine item count.
- Image count.
- Estimated DOM node count.

MVP limits:

- Warn internally over 50 MB compressed.
- Reject over 150 MB compressed.
- Reject over 300 MB expanded.
- Reject over 8 MB combined XHTML before chapter-window rendering exists.
- Reject over 400 spine items before chapter-window rendering exists.
- Reject over 1,000 images for MVP.

User-facing rejection copy:

```text
This EPUB is too large for this version of ReaderFlow.
Your file was not imported.
```

These limits can be raised only after large-book rendering and memory tests pass on device.

### 4.3 Validate With Readium

Use Readium's current publication opening APIs.

Validation should detect:

- Not an EPUB.
- DRM/protected publication.
- Fixed-layout EPUB.
- Missing spine/reading order.
- Corrupt package.
- Duplicate content fingerprint.

Content fingerprint:

- Hash stable file bytes with SHA-256.
- Use fingerprint to detect duplicate import.

### 4.4 Extract Metadata

Extract:

- Title.
- Authors.
- Language.
- Cover image.
- Table of contents.
- Reading order hrefs.
- Fixed-layout/reflowable metadata.
- Direction/progression metadata when available.

Fallbacks:

- Missing title: use file name without extension.
- Missing author: `Unknown Author`.
- Missing cover: generated typographic cover.

### 4.5 Expand EPUB Resources

Use ZIPFoundation to expand into:

```text
Application Support/ReaderFlow/Books/{bookId}/expanded/
```

Rules:

- Prevent zip-slip path traversal.
- Ignore macOS metadata entries.
- Preserve relative paths.
- Record root package path from `META-INF/container.xml`.
- Keep the original EPUB as `source.epub`.

### 4.6 Create Book Record

Create `BookEntity` with:

- Metadata.
- File paths.
- Cover path.
- `readingProgress = 0`.
- `lastLocatorJSON = nil`.
- `isArchived = false`.
- `importStatus = imported`.
- preflight counts and sizes.
- sort keys.
- `schemaVersion`.

### 4.7 Import Tests

Add unit tests using small fixture EPUBs:

- Valid EPUB import.
- Missing cover fallback.
- Duplicate detection.
- Fixed-layout rejection.
- Corrupt file rejection.
- Zip path traversal rejection.
- Metadata fallbacks.
- Oversize preflight rejection.
- "Open in ReaderFlow" import path.

## 5. Reader Engine

### 5.0 Build EPUB Resource Resolver And Sanitizer

Create `EPUBResourceResolver`.

Responsibilities:

- Resolve resource hrefs relative to the OPF package root, not the archive root.
- Normalize `.` and `..` path segments.
- Preserve URL fragments for internal anchors.
- Resolve manifest items where possible before falling back to file lookup.
- Rewrite chapter-to-chapter links into in-document anchors when the target spine item is present.
- Rewrite image, audio poster, stylesheet, font, SVG image, and CSS `url(...)` references.
- Rewrite CSS `@import` rules.
- Validate MIME types against manifest media type and UTType fallback.
- Reject path traversal outside the expanded EPUB directory.
- Reject unsupported remote resource URLs in MVP.

Create `EPUBContentSanitizer`.

Responsibilities:

- Remove all `<script>` elements.
- Remove inline event handler attributes such as `onclick`, `onload`, and `onerror`.
- Remove `javascript:` and `data:text/html` URLs.
- Remove iframes, forms, object/embed elements, and plugin-style content.
- Remove remote network loads from images, stylesheets, fonts, audio, video, and CSS `url(...)`.
- Sanitize SVG content by removing script, event handlers, external references, and foreign objects.
- Enforce maximum single-resource byte limits before parsing.
- Keep semantic reading HTML, images, internal links, footnotes, tables, and EPUB typography where safe.

Native WebKit policy:

- Allow navigation to `readerflow://` resources.
- Allow app-owned `about:blank` or generated document loads.
- Intercept user-tapped external links and ask before opening Safari.
- Block all automatic `http://`, `https://`, `file://`, and unknown-scheme navigation from EPUB content.
- The JavaScript bridge accepts only known message names and validates message payload schemas before acting.

Sanitizer tests:

- `<script>` element removal.
- Inline `onload=` removal.
- `javascript:` link removal.
- Remote image/font/stylesheet blocking.
- CSS `url(http...)` blocking.
- CSS `@import` blocking or safe rewriting.
- Iframe/form/object/embed removal.
- SVG script removal.
- Path traversal rejection.
- Oversized resource rejection.

### 5.1 Build Reader Resource Scheme

Create `ReaderResourceSchemeHandler`.

Scheme:

```text
readerflow://book/{bookId}/{relativeResourcePath}
readerflow://app/reader.css
readerflow://app/reader.js
readerflow://app/fonts/{fontFile}
```

Responsibilities:

- Resolve book resources from expanded EPUB directory.
- Use `EPUBResourceResolver` for every book resource path.
- Resolve bundled reader assets.
- Resolve bundled font files.
- Return correct MIME types using UTType.
- Reject path traversal.
- Cache small static app assets in memory.

### 5.2 Build Continuous Document Builder

Create `ContinuousDocumentBuilder`.

Input:

- `BookEntity`.
- Readium publication reading order.
- Expanded EPUB root directory.
- Table of contents.
- Global reader settings.

Output:

- Generated HTML string loaded into `WKWebView`.

Process:

1. Walk the EPUB spine in reading order.
2. Read each XHTML resource.
3. Apply single-resource size checks.
4. Parse with SwiftSoup.
5. Sanitize with `EPUBContentSanitizer`.
6. Extract body attributes and body HTML.
7. Extract linked stylesheets.
8. Rewrite `src`, `href`, `poster`, SVG image refs, internal anchors, stylesheet references, CSS imports, and CSS `url(...)` references with `EPUBResourceResolver`.
9. Wrap each spine item as:

```html
<section
  class="rf-chapter"
  data-spine-index="0"
  data-href="chapter1.xhtml"
  data-title="Chapter 1"
  lang="en">
  ...
</section>
```

10. Inject ReaderFlow CSS variables for theme, font, text size, line height, and margins.
11. Inject ReaderFlow JavaScript.
12. Add a small top and bottom breathing space so autoscroll can start and finish comfortably.

Do not strip author CSS wholesale. Apply ReaderFlow CSS after author CSS, and override only what is needed for readable continuous flow.

### 5.3 Large Book Strategy

Implement in two passes:

Pass 1:

- Build one continuous DOM for normal novels and proofreader manuscripts.
- Target books with up to 3 MB combined XHTML text or 250 spine items.
- Enforce import preflight limits before attempting to render.

Pass 2:

- Add section virtualization for larger books.
- Keep current chapter, previous 2 chapters, and next 3 chapters mounted.
- Preserve absolute progress by tracking cumulative chapter heights.
- Disable virtualization while a text selection is active.
- Use the same locator contract in full-DOM and chapter-window modes.

The app can ship TestFlight after Pass 1 is smooth and oversize books fail gracefully. App Store candidate should include Pass 2 chapter-window rendering so large text-heavy books are handled without building one unsafe giant DOM.

### 5.4 Build Reader JavaScript Controller

Create `reader.js` with one global controller:

```text
window.ReaderFlow
```

Responsibilities:

- Initialize book document.
- Apply settings.
- Start/pause/resume autoscroll.
- Set speed.
- Report progress.
- Restore locator.
- Save current locator.
- Detect selection completion.
- Create highlight marks.
- Reapply persisted highlights.
- Jump to highlight.
- Notify native code through `WKScriptMessageHandler`.
- Validate outbound message shape before posting to native.
- Ignore EPUB-provided scripts because sanitized EPUB content must not run arbitrary JavaScript.

Message channels:

- `readerReady`.
- `progressChanged`.
- `selectionSaved`.
- `scrollStateChanged`.
- `error`.
- `debug` in development builds only.

### 5.5 Autoscroll Implementation

Use `requestAnimationFrame`.

Algorithm:

1. Track `lastTimestamp`.
2. Compute `deltaSeconds`.
3. Scroll by `speed * deltaSeconds`.
4. Clamp to document bottom.
5. Pause at bottom and report end-of-book.
6. Do not write progress from every frame.

Pause triggers:

- Single tap.
- Manual drag/scroll.
- Text selection starts.
- Reader settings sheet opens.
- App resigns active.
- JavaScript reports render instability.

Resume behavior:

- New book: user must tap to start.
- Reopened book: auto resume after `readerReady` and locator restore.
- After manual drag: stay paused for MVP.

Speed:

- Store as CSS pixels per second.
- Default: 25.
- Range: 5 to 120.
- Native UI displays a 1 to 20 level derived from the raw speed.

### 5.6 Progress Reporting

JavaScript reports:

- `scrollY`.
- `documentHeight`.
- `viewportHeight`.
- `totalProgression`.
- Current spine index.
- Current chapter href.
- Current chapter title.
- Chapter progression.

Native throttling:

- Save at most once per second while reading.
- Save immediately when pausing, backgrounding, closing, or changing book.

### 5.7 Restore Position

Restore order:

1. Use stored `ReaderLocator.scrollY` if document height is within 10 percent of stored height.
2. Use text quote anchor if available.
3. Use chapter href plus chapter progression.
4. Use total progression.
5. Use beginning of book.

After restore:

- If this is a reopened book, begin autoscroll automatically.
- If this is first open, remain paused.

### 5.7.1 ReaderFlow Locator Contract

ReaderFlow locators are the primary persistence contract for reading progress and highlights.

Required fields:

- `bookId`.
- `bookFingerprint`.
- `spineIndex`.
- `href`.
- `chapterTitle`.
- `chapterProgression`.
- `totalProgression`.
- `scrollY`.
- `documentHeight`.
- `textQuote`.
- `domTextPath`.
- `contentHash`.
- `createdAt`.

Rules:

- `bookFingerprint` must match the imported source EPUB fingerprint before a locator is trusted.
- `href` is normalized relative to the OPF package root.
- `textQuote` is used for highlight re-anchoring.
- `domTextPath` is a hint, not the only anchor.
- `contentHash` is a normalized hash of the selected text plus nearby context.
- Readium locator JSON is optional and stored only as compatibility/debug metadata.
- Export never depends on Readium locator data.

### 5.8 Highlight Capture

Goal:

- Hold, drag, release, save automatically.

Implementation:

1. Watch `selectionchange`.
2. When selection becomes non-collapsed, mark selection as active.
3. Debounce selection changes.
4. On touch end, pointer up, or 600 ms stable selection timeout, read the selected range.
5. Reject selections shorter than 2 visible characters.
6. Build `selectedText`, `contextBefore`, `contextAfter`, and `ReaderLocator`.
7. Wrap the range in `<mark class="rf-highlight" data-highlight-id="...">`.
8. Send `selectionSaved` to native.
9. Native persists the excerpt.
10. Native optionally copies text to clipboard.
11. Native shows visual confirmation and haptic feedback.
12. JavaScript clears the native selection while leaving the highlight mark.
13. If iOS selection handles remain active and autosave has not fired within 800 ms of a stable selection, show a small floating Save button anchored near the selection. This fallback is part of MVP, but automatic save remains the default path.

Duplicate prevention:

- If the same exact text and locator is saved within 3 seconds, ignore the duplicate.
- If selection overlaps an existing highlight, create a new excerpt only when text differs materially.

Fallback:

- The floating Save button is available when automatic completion cannot confidently determine release.
- The MVP is acceptable only if normal drag selections autosave and edge cases have the floating Save fallback.

Device spike acceptance for highlighting:

- Single-paragraph selection saves.
- Cross-paragraph selection saves.
- Repeated text anchors to the correct occurrence.
- Selection during autoscroll pauses and saves.
- Selection after text-size change saves and jumps back.
- Jump-back scrolls to the saved highlight.
- Duplicate save prevention works.
- The interaction works on a real iPhone, not only Simulator.

### 5.9 Highlight Persistence And Reapplication

On reader load:

1. Native queries excerpts for the book.
2. Native sends highlight payloads to JavaScript.
3. JavaScript tries to anchor each highlight by:
   - exact text plus prefix/suffix.
   - normalized offsets within chapter.
   - chapter progression fallback.
4. JavaScript applies `<mark>` tags.
5. Failed anchors are reported to native and shown in excerpts list as saved but not currently anchorable.

### 5.10 Reader Tests

Unit-test native services:

- Resource URL rewriting.
- MIME lookup.
- Path traversal rejection.
- Locator encode/decode.
- Text quote normalization.
- Export formatting.

Add JavaScript tests for:

- Autoscroll speed math.
- Progress calculation.
- Text quote generation.
- Highlight duplicate detection.
- Restore fallback order.
- Message payload validation before native bridge calls.
- Sanitized content cannot call native bridge except through ReaderFlow-owned code.

Add on-device manual tests:

- Smooth scroll at min/default/max speed.
- Tap pause/resume.
- Right-edge speed gestures.
- Highlight while paused.
- Highlight while autoscrolling.
- Reopen auto-resume.
- Light/dark theme switch.
- Large chapter.
- RTL text sample.
- CJK sample.
- Repeated text highlight sample.
- Cross-paragraph selection sample.

## 6. Reader UI

### 6.1 SwiftUI Reader Screen

Create `ReaderView`.

Responsibilities:

- Host `ReaderWebView`.
- Show minimal overlay controls.
- Show speed indicator.
- Show pause/running state.
- Show settings sheet.
- Show save confirmation toast.
- Handle screen edge speed gestures.
- Handle navigation back to library.

Layout:

- Reader content full screen.
- Controls hidden while scrolling.
- Tap toggles pause/resume.
- A small bottom control strip appears when paused.

### 6.2 Controls

Controls:

- Play/pause button.
- Speed slider.
- Text size control.
- Font picker.
- Theme picker.
- Line height control.
- Margin control.
- Excerpts button.
- Library/back button.

Use icons where possible. Keep labels short.

### 6.3 Settings Sheet

Reader settings are global.

Changing settings:

- Updates SwiftData singleton.
- Sends updated settings to active web view.
- Keeps current locator stable where possible.
- Recalculates position after font or size changes.

### 6.4 Theme System

Themes:

- System.
- Light.
- Dark.

CSS variables:

- `--rf-bg`.
- `--rf-text`.
- `--rf-muted`.
- `--rf-highlight`.
- `--rf-link`.
- `--rf-selection`.

Highlight color:

- One warm yellow in light mode.
- One muted amber in dark mode.

### 6.5 Reader Accessibility

Requirements:

- Native controls have VoiceOver labels.
- Slider has meaningful accessibility value.
- Toast confirmation is announced.
- Settings controls are reachable without gestures.
- Respect Reduce Motion for overlay animations.
- Autoscroll remains available because it is an explicit user-controlled reading mode.

## 7. Library UI

### 7.1 Library Screen

Create `LibraryView`.

Sections:

- Recent books.
- All books.
- Archived excerpts entry.

Book cell:

- Cover.
- Title.
- Author.
- Progress.
- Last opened.

Actions:

- Open.
- View excerpts.
- Export excerpts.
- Delete local book.

### 7.2 Empty State

Show:

- App name.
- One import button.
- Short text: "Import a DRM-free EPUB to begin."

No marketing page.

### 7.3 Search And Sort

Search:

- Title.
- Author.

Sort:

- Recently opened.
- Title.
- Author.
- Date imported.

### 7.4 Delete Book Flow

Behavior:

1. User chooses delete local book.
2. Confirm that the EPUB file will be removed but saved excerpts will remain.
3. Delete `source.epub`, expanded resources, cover, and reader cache.
4. Set `BookEntity.isArchived = true`.
5. Set related `ExcerptEntity.sourceBookAvailable = false`.
6. Hide book from active library.
7. Show its excerpts under Archived Excerpts.

## 8. Excerpts UI

### 8.1 Book Excerpts Screen

Create `BookExcerptsView`.

Display:

- Book title.
- Author.
- Excerpt count.
- Export all button.
- List of excerpts.

Excerpt row:

- Selected text preview.
- Chapter.
- Saved date.
- Progress if available.

Actions:

- Jump to location.
- Copy excerpt.
- Share excerpt.
- Delete excerpt.

If source book is archived:

- Disable jump.
- Keep copy/share/delete/export.

### 8.2 Archived Excerpts Screen

Create `ArchivedExcerptsView`.

Display archived book collections grouped by book title.

Actions:

- Open excerpt list.
- Export all excerpts for archived book.
- Delete archived excerpt collection.

### 8.3 Jump To Excerpt

Flow:

1. User taps excerpt.
2. If source book exists, open reader.
3. Load document.
4. Restore excerpt locator.
5. Scroll highlight into view.
6. Pulse highlight once.
7. Start paused so user can inspect the location.

This is the one case where reopened book autoscroll does not start automatically.

### 8.4 Excerpt Deletion

Delete only the selected excerpt.

After deletion:

- Remove highlight from active reader if open.
- Keep book progress unchanged.

## 9. Export

### 9.1 Export Formatter

Create `ExcerptTextExporter`.

Output:

```text
ReaderFlow Excerpts
Book: {Title}
Author: {Author}
Exported: {Date}
Excerpt Count: {Count}

---

Chapter: {Chapter}
Location: {ProgressPercent or "Unknown"}
Saved: {Date}

{Selected text}

Context: ...{before} [excerpt] {selected text} [/excerpt] {after}...

---
```

Rules:

- Plain UTF-8 text.
- Normalize line endings to `\n`.
- Preserve paragraph breaks in selected text.
- Trim excessive whitespace.
- If context is unavailable, omit the Context line.

### 9.2 Share Sheet

Create `ShareSheetPresenter`.

Flow:

1. Generate text.
2. Write to temporary file under `Exports/`.
3. Present iOS share sheet.
4. Clean up old export files on next app launch.

Filename:

```text
ReaderFlow - {Sanitized Book Title} - Excerpts.txt
```

### 9.3 Export Tests

Test:

- Empty excerpt list.
- One excerpt.
- Multiple excerpts sorted by book progress then save date.
- Unicode text.
- RTL text.
- Multiline selection.
- Missing chapter/location.
- Filename sanitization.

## 10. Settings

### 10.1 App Settings Screen

Create `SettingsView`.

Controls:

- Theme.
- Font family.
- Text size.
- Line height.
- Margins.
- Default autoscroll speed.
- Auto-copy highlights.
- Haptic confirmation.
- Export detail level.

### 10.2 Defaults

Default settings:

- Theme: system.
- Font: system serif.
- Text size: 18 CSS px.
- Line height: 1.55.
- Margin scale: medium.
- Autoscroll speed: 25 CSS px/sec.
- Auto-copy highlights: off.
- Haptics: on.
- Export detail: detailed.

### 10.3 Settings Tests

Test:

- Singleton creation.
- Persistence across app relaunch.
- Reader receives live setting updates.
- Font changes keep approximate progress stable.

## 11. Typography And Fonts

### 11.1 Bundle Fonts

Add font files:

- Atkinson Hyperlegible regular, italic, bold, bold italic.
- Literata regular, italic, bold, bold italic.
- Source Serif 4 regular, italic, bold, bold italic.

Add license files:

- `Resources/Fonts/AtkinsonHyperlegible-LICENSE.txt`
- `Resources/Fonts/Literata-OFL.txt`
- `Resources/Fonts/SourceSerif4-OFL.txt`

### 11.2 Register Fonts In CSS

Use `@font-face` in `reader.css` pointing at:

```text
readerflow://app/fonts/{font-file}
```

Font family choices in UI:

- System Serif.
- System Sans.
- Atkinson Hyperlegible.
- Literata.
- Source Serif 4.

### 11.3 Typography QA

Test:

- Latin.
- Accented European text.
- Arabic or Hebrew RTL sample.
- Japanese or Chinese sample.
- Emoji.
- Mixed scripts.
- Long words.
- Poetry/line breaks.
- Chapter headings.
- Footnotes/endnotes.

## 12. Performance Work

### 12.1 Performance Targets

Targets on a recent iPhone:

- Import typical novel EPUB under 5 seconds after file selection.
- Open imported typical novel under 2 seconds.
- Maintain visibly smooth autoscroll at default speed.
- No repeated frame hitches during plain text autoscroll.
- Progress persistence does not affect scroll smoothness.
- Highlight save completes in under 300 ms for normal selections.

### 12.2 Instrumentation

Add debug-only metrics:

- Import duration.
- Document build duration.
- Web view load duration.
- Time to first reader ready.
- Average progress update frequency.
- Highlight save duration.
- DOM node count.
- Combined XHTML byte size.

Show debug metrics only in development builds.

### 12.3 Optimize

Order:

1. Avoid rebuilding generated HTML unless book or settings require it.
2. Cache generated reader document per book and settings hash.
3. Lazy-load images below viewport.
4. Add large-book virtualization.
5. Reduce JavaScript bridge chatter.
6. Avoid synchronous SwiftData writes during autoscroll.

## 13. Error States

Implement user-facing errors for:

- Import cancelled.
- File unavailable.
- Unsupported file type.
- Invalid EPUB.
- DRM/protected EPUB.
- Fixed-layout EPUB unsupported.
- No readable content.
- Resource missing during render.
- Export failed.
- Clipboard copy failed.
- Storage full.

Each error should include:

- Plain explanation.
- Recovery action where possible.
- No stack traces or technical jargon in user UI.

## 14. Privacy And App Review

### 14.1 Privacy

MVP behavior:

- No account.
- No analytics.
- No remote service.
- No ads.
- No third-party tracking SDKs.
- Books and excerpts remain local.

Privacy labels:

- Data not collected, unless future crash reporting is added.

### 14.2 Clipboard

Auto-copy highlights is off by default.

When enabled:

- User setting clearly states that saved highlights are copied to clipboard.
- Toast says "Excerpt saved and copied".

### 14.3 App Review Notes

Explain:

- App imports user-provided DRM-free EPUB files.
- App stores files locally.
- App exports user-created excerpts through the share sheet.
- No login is required.

## 15. Testing Strategy

### 15.1 Fixture Library

Create local test fixtures:

- Small public-domain EPUB.
- EPUB with cover.
- EPUB without cover.
- EPUB with nested resources.
- EPUB with images.
- EPUB with RTL text.
- EPUB with CJK text.
- EPUB with large chapter.
- Corrupt EPUB.
- Fixed-layout EPUB.
- Duplicate EPUB.

Keep only redistributable fixtures in repo. If a fixture cannot be committed, document where to obtain it and keep it out of Git.

### 15.2 Unit Tests

Cover:

- Import validation.
- Metadata extraction.
- File storage paths.
- EPUB preflight limits.
- Content sanitizer behavior.
- Resource rewriting.
- OPF-root-relative href resolution.
- CSS import and CSS URL rewriting.
- Custom scheme MIME mapping.
- Custom scheme path traversal rejection.
- Reader locator encoding.
- Text quote matching.
- Native bridge message schema validation.
- SwiftData repositories.
- Export formatting.
- Golden export fixtures.
- Settings defaults.

### 15.3 WebView Integration Tests

Cover with a minimal host app or XCTest harness:

- `readerReady` message shape.
- `progressChanged` throttling and payload shape.
- `selectionSaved` payload shape.
- Unknown bridge message rejection.
- EPUB content cannot invoke native bridge directly.
- Blocked remote navigation.
- External user-tapped link confirmation path.
- Reader resource scheme loads CSS, JS, images, and fonts.
- Sanitized fixture renders without executing removed scripts.

### 15.4 UI Tests

Cover:

- First launch empty library.
- Import book.
- Open book.
- Start/pause autoscroll.
- Change speed.
- Change text size.
- Save excerpt.
- View excerpts.
- Export excerpts sheet appears.
- Delete book and confirm archived excerpts remain.

### 15.5 Performance And Memory Tests

Use XCTest metrics and device-only smoke runs for:

- Import duration.
- Reader document build duration.
- WebView time to `readerReady`.
- 10-minute autoscroll with no crash.
- 10-minute autoscroll plus at least one highlight save.
- Memory before reader load, after reader ready, after 10 minutes autoscroll, and after closing reader.
- Large-book preflight rejection path.
- Chapter-window rendering once implemented.

### 15.6 Manual Device QA

Run on:

- Small modern iPhone.
- Large modern iPhone.
- One older iOS 18-supported iPhone if available.
- iPad as a sanity check.

Manual checklist:

- Scrolling smoothness.
- Heat/battery sanity during 10 minutes of autoscroll.
- Selection reliability.
- Highlight confirmation clarity.
- Reopen auto-scroll behavior.
- Settings persistence.
- Dark mode.
- Large text.
- Airplane mode.
- Low storage simulation if practical.

## 16. Milestones

### Milestone 1: Project Skeleton

Done when:

- XcodeGen project generates successfully.
- App builds and launches.
- Minimal shell screen displays.
- Unit test target runs.

### Milestone 2: Core Reader Device Spike

Done when:

- One known redistributable EPUB fixture is bundled or copied into the app container for development.
- Readium opens the fixture and exposes reading order and metadata.
- EPUB resources are expanded into app storage.
- `EPUBResourceResolver` resolves OPF-root-relative resources.
- `EPUBContentSanitizer` removes dangerous content from the fixture and security fixtures.
- A real EPUB renders in one vertical continuous WKWebView document.
- Autoscroll works with `requestAnimationFrame` on a real iPhone.
- Tap pause/resume works.
- Speed slider works.
- ReaderFlow locator saves and restores position.
- Reopened fixture auto-scrolls after restore.
- Hold-drag-release autosaves one normal excerpt on a real iPhone.
- Floating Save fallback appears for uncertain selection states.
- Jump back to the saved excerpt works.

This milestone decides whether the core product is viable. Do not proceed to full import/library until this works on device.

### Milestone 3: Import And Library

Done when:

- SwiftData container initializes.
- Empty library displays.
- EPUB import works from Files.
- "Open in ReaderFlow" works from Files.
- Metadata and cover appear in library.
- Duplicate imports are detected.
- Invalid/fixed-layout/DRM errors are handled.
- Oversize preflight rejection works.
- Imported files are stored in app container.

### Milestone 4: Reader Integration

Done when:

- Imported library books open in the continuous reader.
- Progress saves through SwiftData.
- Reopened imported books restore and auto-scroll.
- Reader bridge validates message schemas.
- Native navigation policy blocks unsafe EPUB navigation.
- Large-book preflight limits protect the renderer.

### Milestone 5: Highlight System

Done when:

- Hold-drag-release creates an excerpt on device.
- Floating Save fallback appears when automatic release is uncertain.
- Cross-paragraph selection works.
- Repeated text anchors correctly.
- Highlight appears visually.
- Excerpt is saved with chapter and ReaderFlow locator.
- Optional auto-copy works.
- Excerpt can jump back to the highlight.
- Duplicate selection protection works.
- Highlights reapply after closing and reopening the reader.

### Milestone 6: Reader Settings

Done when:

- Light/dark/system themes work.
- Font choice works.
- Text size works.
- Line height works.
- Margins work.
- Settings persist globally.
- Position remains close after typography changes.

### Milestone 7: Excerpts And Export

Done when:

- Book excerpts screen works.
- Archived excerpts screen works.
- Individual copy/share works.
- Export all creates a plain text file.
- Share sheet presents correctly.
- Deleted books keep archived excerpts.

### Milestone 8: Performance And Large Books

Done when:

- Performance targets are met for normal books.
- Large-book preflight rejection is polished.
- Chapter-window rendering is implemented for large text-heavy books.
- Debug metrics show no excessive bridge chatter.
- 10-minute autoscroll test is stable.
- 10-minute autoscroll plus highlight save is stable.

### Milestone 9: Accessibility And Polish

Done when:

- VoiceOver labels exist for native controls.
- Reader controls are reachable without gestures.
- Toasts announce important state.
- Text does not overlap controls.
- Error states are polished.
- Empty states are polished.
- App icon and launch screen are present.

### Milestone 10: TestFlight

Done when:

- App builds Archive successfully.
- Smoke tests pass on device.
- Privacy labels are prepared.
- App Review notes are drafted.
- Known limitations are documented.
- TestFlight build is uploaded.

### Milestone 11: App Store Candidate

Done when:

- Beta feedback has been triaged.
- Crashers are fixed.
- Import/render/highlight/export flows are stable.
- App metadata and screenshots are ready.
- Release build has no debug UI.

## 17. Implementation Order

Use this exact order for first implementation:

1. Add repo baseline files.
2. Add XcodeGen project.
3. Add minimal app skeleton.
4. Add one redistributable EPUB fixture for local development.
5. Add minimal app file store for the fixture.
6. Add Readium fixture opening and metadata extraction.
7. Add ZIP expansion for the fixture.
8. Add `EPUBResourceResolver`.
9. Add `EPUBContentSanitizer`.
10. Add custom URL scheme handler.
11. Add continuous document builder for the fixture.
12. Add basic WKWebView reader.
13. Add JavaScript ready/progress bridge.
14. Add autoscroll.
15. Add tap pause/resume.
16. Add speed slider.
17. Add ReaderFlow locator persistence in temporary storage.
18. Add restore and reopen auto-scroll for the fixture.
19. Add selection detection.
20. Add excerpt payload generation.
21. Add visual highlight marks.
22. Prove highlight save and jump-back on a real iPhone.
23. Add SwiftData models and repositories.
24. Move fixture progress/excerpt persistence into SwiftData.
25. Add full file storage service.
26. Add EPUB import picker.
27. Add "Open in ReaderFlow" import path.
28. Add preflight limits.
29. Add Readium validation for imported files.
30. Add metadata extraction for imported files.
31. Add ZIP expansion for imported files.
32. Show imported books in library.
33. Open imported books in reader.
34. Add saved confirmation and haptics.
35. Add auto-copy setting.
36. Add excerpt list.
37. Add jump to excerpt from excerpt list.
38. Add export formatter.
39. Add share sheet export.
40. Add delete/archive behavior.
41. Add archived excerpts screen.
42. Add font files and font selector.
43. Add theme/text/line/margin settings.
44. Add right-edge speed gestures.
45. Add search/sort library.
46. Add polished error states.
47. Add tests around every completed service.
48. Add WebView integration tests.
49. Add performance instrumentation.
50. Add large-book chapter-window rendering or final large-book limits.
51. Add accessibility pass.
52. Add visual polish.
53. Prepare TestFlight.
54. Prepare App Store candidate.

## 18. Definition Of Done

ReaderFlow MVP is done when:

- A user can import a DRM-free reflowable EPUB.
- The book appears in a library with metadata and cover.
- The book opens into a continuous vertical reader.
- Autoscroll is smooth and adjustable.
- Reopened books resume position and start autoscrolling automatically.
- Tapping pauses/resumes.
- User can save an excerpt by selecting text.
- Saved excerpt has selected text, context, chapter, and location/progress.
- Highlight is visible after saving.
- Excerpts can be viewed later.
- Excerpts can be exported to a plain text file through the share sheet.
- Deleting a book keeps its excerpts in an archive.
- Light and dark modes work.
- Text size, font, line height, and margins work.
- The app runs locally with no account or backend.
- Core flows pass tests and manual device QA.

## 19. Research Notes

Sources checked while making this plan:

- Readium Swift Toolkit: https://github.com/readium/swift-toolkit
- Readium Swift Package Index: https://swiftpackageindex.com/readium/swift-toolkit
- Readium continuous vertical scroll issue: https://github.com/readium/swift-toolkit/issues/684
- Apple SwiftData documentation: https://developer.apple.com/documentation/swiftdata
- Apple WKWebView documentation: https://developer.apple.com/documentation/webkit/wkwebview
- Apple WKScriptMessageHandler documentation: https://developer.apple.com/documentation/webkit/wkscriptmessagehandler
- Apple Uniform Type Identifiers documentation: https://developer.apple.com/documentation/uniformtypeidentifiers
- ZIPFoundation: https://github.com/weichsel/ZIPFoundation
- SwiftSoup: https://github.com/scinfu/SwiftSoup
- XcodeGen: https://github.com/yonaskolb/XcodeGen
- Atkinson Hyperlegible: https://www.brailleinstitute.org/freefont/
- Literata: https://github.com/googlefonts/literata
- Source Serif: https://github.com/adobe-fonts/source-serif
