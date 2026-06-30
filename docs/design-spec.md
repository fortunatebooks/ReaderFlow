# ReaderFlow Design Spec

Status: Draft 2  
Date: 2026-06-30  
Platform: iOS 18+, iPhone first, iPad later if it falls out naturally

## Product Summary

ReaderFlow is a lightweight EPUB reader for people who want to read or review a book as a continuous stream of text. The core experience is smooth vertical autoscroll at a personally comfortable speed, with one-tap pause and fast highlight saving.

The app should feel closer to a focused reading instrument than a full ebook platform. Import a DRM-free EPUB, open it, set a speed, read while the book scrolls, and drag across text to save anything worth returning to.

## Primary Users

- Fast readers who want less hand movement and fewer page turns.
- Proofreaders and reviewers who need to move through a book quickly and capture passages for later reference.
- Readers of non-English books who need reliable layout, text rendering, and font support.

## Core Promise

ReaderFlow lets a reader:

1. Import a DRM-free EPUB.
2. Open it in a clean continuous vertical reader.
3. Start smooth autoscroll.
4. Adjust speed without breaking reading flow.
5. Tap once to pause.
6. Highlight text with a hold-drag-release gesture.
7. See clear confirmation that the excerpt was saved.
8. Revisit or export saved excerpts later.

## Goals

- Smooth, stable vertical autoscroll.
- Fast EPUB import and opening.
- Library view with covers, progress, recent books, and saved excerpts.
- Good language coverage for reflowable EPUBs.
- Light mode and dark mode.
- Adjustable text size.
- Reasonable font selection, with a path to custom font import later.
- Saved excerpts with book, chapter, and best-available location metadata.
- Plain text export per book through the iOS share sheet.
- Optional automatic copy-to-clipboard after highlight save.

## Non-Goals for MVP

- DRM support.
- Kobo, Kindle, Apple Books, or store integrations.
- Cloud sync.
- User accounts.
- Social sharing.
- Rich note-taking workflows.
- PDF reading.
- Full proofreading markup systems.
- Cross-device reading position sync.

## Technical Constraints

### EPUB Rendering

Recommended starting point: Readium Swift Toolkit.

Reasons:

- Actively maintained EPUB toolkit for iOS and iPadOS.
- Supports reflowable EPUB, fixed-layout EPUB, RTL reading, search, and highlighting APIs.
- Provides locator/progression concepts that can support saved excerpt references.
- Available through Swift Package Manager.

Important risk:

- ReaderFlow needs true continuous vertical reading across chapters/resources. Readium supports scrolling, but recent Readium issue discussion indicates that seamless vertical scrolling across all EPUB resources may still require custom work or a careful navigator integration.
- This needs an early technical spike before building the full library UI.

Sources:

- Readium Swift Toolkit: https://github.com/readium/swift-toolkit
- Readium continuous vertical scroll issue: https://github.com/readium/swift-toolkit/issues/684

## MVP Feature Scope

### 1. Library

The library is the home screen.

Must include:

- Grid/list of imported books.
- Cover image when available.
- Title and author.
- Reading progress percentage.
- "Recently read" ordering by default.
- Import button using iOS Files/iCloud document picker.
- Search/filter by title or author.
- Per-book actions: open, view excerpts, export excerpts, delete local copy.
- Deleting a book removes the local EPUB and library entry but keeps saved excerpts in an archive.
- Saved excerpt archive for books that are no longer in the local library.

Nice-to-have:

- Separate "Recent" and "All Books" tabs.
- Sort by recent, title, author, date imported.

### 2. Import

Supported in MVP:

- DRM-free `.epub` files from Files/iCloud.
- Open in ReaderFlow from the iOS share sheet, if straightforward.

Import behavior:

- Copy the EPUB into ReaderFlow's app container.
- Extract/store metadata: title, author, cover, language, table of contents if available.
- Create a stable internal book ID.
- Preserve the original file name as fallback metadata.

Failure states:

- Invalid EPUB.
- DRM-protected EPUB.
- Unsupported or malformed content.
- Import already exists.

### 3. Reader

The reader is the main product surface.

Layout:

- Full-screen vertical text.
- Minimal chrome while reading.
- Bottom or floating compact controls when paused or after a tap.
- Safe area aware.
- No decorative UI around the text.

Required reader settings:

- Text size.
- Font family.
- Light/dark/system theme.
- Line spacing.
- Margins.
- Autoscroll speed.
- Auto-copy saved highlight to clipboard: on/off.

Font plan:

- MVP should use iOS system fonts plus a small curated set of bundled reading fonts if licensing is clean.
- Good initial choices if licenses permit: Atkinson Hyperlegible, Source Serif, Literata, Noto Serif/Sans subsets.
- Custom font import can be a post-MVP feature if the core reader is stable.

Language/rendering expectations:

- Respect EPUB language metadata where possible.
- Support right-to-left books where the rendering layer supports it.
- Avoid hard-coded Latin assumptions.
- Use Unicode-safe text extraction and export.
- Do not strip EPUB typography aggressively unless needed for readability.

### 4. Autoscroll

This is the defining feature.

Behavior:

- New books open paused on first read.
- Reopened books start autoscrolling automatically at the saved speed and last reading position.
- Tap the screen to toggle pause/resume.
- When autoscroll is active, content moves upward smoothly at the selected speed.
- Manual drag while autoscrolling temporarily pauses or suspends autoscroll.
- After manual scroll ends, the app waits briefly before resuming, or stays paused depending on a setting. MVP can choose "stay paused" for predictability.
- Autoscroll stops at chapter/book end and shows a quiet end-of-book state.

Speed model:

- Store speed as user-facing levels plus an underlying points-per-second value.
- Example range: 5 to 120 points per second.
- Default: 25 points per second.
- Controls should show a simple numeric level, not raw pixels.

Primary controls:

- Slider in reader controls.
- Swipe up on the right screen edge to increase speed.
- Swipe down on the right screen edge to decrease speed.

Gesture conflict handling:

- Right-edge swipe controls speed.
- Long press on text starts selection/highlight.
- Single tap toggles pause/resume.
- Horizontal gestures should be avoided in the core reader.

Visual feedback:

- When speed changes, show a small transient speed indicator.
- When paused, show a clear pause icon/state.
- When scrolling, hide controls after a short delay.

### 5. Highlight Saving

This is the second defining feature.

Desired gesture:

- Hold on text.
- Drag to select text.
- Release.
- App automatically saves the excerpt.

MVP behavior:

- Saved highlight appears immediately with a highlight color.
- MVP uses one highlight color only.
- A transient confirmation appears: "Excerpt saved".
- Optional light haptic feedback.
- If auto-copy is enabled, confirmation changes to "Excerpt saved and copied".
- The user does not need to tap a context menu button.

Important implementation note:

- Native text selection may show the iOS selection menu. The MVP should minimize friction, but if fully automatic release detection is brittle, the fallback is a custom "Save" action in the selection menu. The product target remains automatic save on release.

Saved excerpt fields:

```json
{
  "id": "uuid",
  "bookId": "uuid",
  "bookTitle": "string",
  "bookAuthors": ["string"],
  "chapterTitle": "string",
  "selectedText": "string",
  "locator": {
    "href": "string",
    "type": "application/xhtml+xml",
    "title": "string",
    "locations": {
      "progression": 0.42,
      "totalProgression": 0.31,
      "position": 123
    },
    "text": {
      "highlight": "string",
      "before": "string",
      "after": "string"
    }
  },
  "createdAt": "ISO-8601 string",
  "copiedToClipboard": false
}
```

Location fallback order:

1. EPUB locator/CFI if available.
2. Resource href plus progression.
3. Chapter title plus approximate book progress.
4. Chapter title only.

### 6. Saved Excerpts

Each book has an excerpts screen.

Must include:

- List of saved excerpts.
- Chapter/title metadata.
- Date saved.
- Tap excerpt to jump back to the book location if possible. If the source book was deleted, the excerpt remains readable but cannot jump back.
- Share/copy individual excerpt.
- Delete excerpt.
- Export all excerpts for the book.
- Archived excerpt collections remain available after the source EPUB is deleted.

List display:

- Excerpt text preview.
- Chapter title.
- Approximate progress if available.

### 7. Export

Export format:

- Plain text `.txt`.
- Generated per book.
- Shared through the iOS share sheet for copy, AirDrop, Save to Files, email, etc.

Filename:

```text
ReaderFlow - {Book Title} - Excerpts.txt
```

Plain text structure:

```text
ReaderFlow Excerpts
Book: {Title}
Author: {Author}
Exported: {Date}

---

Chapter: {Chapter}
Location: {Progress or locator}
Saved: {Date}

{Selected text}

Context: ...{few words before} | {few words after}...

---
```

JSON:

- Internal storage can be JSON for the MVP.
- If the app moves to SwiftData/Core Data later, keep export format stable.

### 8. Settings

App-level settings:

- Theme: system, light, dark.
- Default text size.
- Default font.
- Default autoscroll speed.
- Auto-copy saved highlights: on/off.
- Haptic confirmation: on/off.
- Export metadata verbosity: simple/detailed.

MVP has one global set of reader preferences. Per-book preference overrides are intentionally out of scope.

## UX Principles

- Reading first. Controls should appear when needed and disappear quickly.
- No modal workflow for common reading actions.
- Highlight saving must feel instant and trustworthy.
- The reader should be calm, not gamified.
- Every saved excerpt needs enough context to be useful later.
- Export should be plain and portable.

## Core User Flows

### First Import

1. User opens ReaderFlow.
2. Empty library shows an import action.
3. User picks an EPUB from Files.
4. App imports the book and shows it in the library.
5. User taps the book.
6. Reader opens at the beginning, paused.
7. User taps to start autoscroll.

### Reopening a Book

1. User opens a previously read book.
2. Reader restores the last reading position.
3. Autoscroll starts automatically at the saved global speed.

### Reading With Autoscroll

1. User opens a book.
2. User taps to start scrolling.
3. User swipes up/down on right edge or opens the slider to adjust speed.
4. User taps to pause.
5. User manually scrolls or changes settings.
6. User taps again to resume.

### Saving an Excerpt

1. User notices text worth saving.
2. User taps to pause if needed, or long-presses directly.
3. User holds and drags across the text.
4. User releases.
5. App saves the excerpt.
6. Highlight remains visible.
7. App shows confirmation and optional haptic feedback.

### Exporting Excerpts

1. User opens book details or excerpts.
2. User taps "Export".
3. App generates one plain text file for that book.
4. iOS share sheet opens.
5. User chooses Copy, AirDrop, Save to Files, Mail, etc.

## Data Model

### Book

- id
- title
- authors
- fileURL
- coverImageURL
- importedAt
- lastOpenedAt
- readingProgress
- lastLocator
- language
- tableOfContents

### Excerpt

- id
- bookId
- bookTitle
- bookAuthors
- selectedText
- chapterTitle
- locator
- createdAt
- copiedToClipboard
- sourceBookAvailable

### ReaderPreferences

- theme
- fontFamily
- textSize
- lineSpacing
- margins
- autoscrollSpeed
- autoCopyHighlights
- hapticsEnabled

## Technical Direction

Recommended stack:

- Swift.
- SwiftUI for app shell, library, settings, excerpts, export views.
- UIKit bridge where needed for the EPUB reader component.
- Readium Swift Toolkit for EPUB parsing, metadata, locators, and possibly rendering.
- Local storage in JSON files for MVP, with a clean repository layer so SwiftData/Core Data can replace it later.

Early spike:

1. Import one DRM-free EPUB.
2. Render it in vertical scroll mode.
3. Confirm whether continuous cross-chapter autoscroll is possible with Readium as-is.
4. Confirm selection/highlight callbacks and saved locators.
5. Confirm smooth autoscroll performance on a real iPhone.

If Readium cannot deliver the core scroll behavior:

- Use Readium for parsing/publication metadata where possible.
- Build a custom WKWebView reader that serves sanitized EPUB XHTML resources through a local resource loader.
- Stack reading-order resources into a continuous vertical document or virtualized sequence.
- Implement autoscroll in JavaScript with native bridge events for progress and selection.

The custom renderer is more work, but ReaderFlow's central feature depends on scroll quality more than on having a generic ebook toolkit UI.

## Performance Requirements

- Open a typical novel EPUB in under 2 seconds after import on recent iPhones.
- Maintain 60 fps autoscroll for normal reflowable EPUB text.
- Avoid loading very large books into one unbounded DOM if using a custom web renderer.
- Persist reading progress frequently but not on every frame.
- Avoid network dependencies for imported books.

## Accessibility

- Support Dynamic Type if compatible with EPUB layout controls, or provide equivalent text scaling.
- Respect Reduce Motion by using non-animated control transitions while still allowing autoscroll as an explicit reading mode.
- Support VoiceOver for library, settings, and excerpt management.
- Ensure sufficient contrast in light and dark themes.
- Make speed controls reachable without precise gestures.

## Privacy

- Books and excerpts stay local in MVP.
- No analytics by default.
- No account required.
- Clipboard auto-copy is off by default unless we decide the onboarding makes it explicit enough.
- If clipboard auto-copy is enabled, confirmation text must make it clear that copying happened.

## App Store Positioning

Core description:

ReaderFlow is a focused EPUB reader that automatically scrolls through DRM-free books at your chosen speed and lets you save highlighted excerpts for later.

Avoid promising:

- Kobo/Kindle/Apple Books integration.
- DRM support.
- Cloud sync.

## Product Decisions

1. Minimum OS is iOS 18.
2. Reopened books start autoscrolling automatically.
3. MVP highlights use one color only.
4. Exports include a few words of surrounding context, separated from the excerpt with ellipses/dividers.
5. MVP has one global reader preference set, not per-book preferences.
6. Deleting a book keeps its saved excerpts separately.

## Proposed MVP Milestones

### Milestone 1: Technical Proof

- Minimal iOS project.
- Import one EPUB.
- Render continuous vertical text.
- Autoscroll smoothly.
- Save a selected excerpt with chapter/location metadata.

Exit criteria:

- The core reading loop works on device with a real EPUB.

### Milestone 2: Library and Persistence

- Library screen.
- Book metadata extraction.
- Reading progress.
- Local excerpt storage.
- Reopen book at last position with automatic autoscroll.

Exit criteria:

- A user can manage multiple imported books locally.

### Milestone 3: Reader Polish

- Theme controls.
- Text size and font controls.
- Speed controls.
- Pause/resume states.
- Highlight confirmation UI.

Exit criteria:

- Reader feels like the actual product, not a demo.

### Milestone 4: Excerpts and Export

- Per-book excerpts screen.
- Jump back to excerpt.
- Individual share/copy.
- Export all excerpts to `.txt`.

Exit criteria:

- Saved excerpts are useful outside the app.

### Milestone 5: App Store Readiness

- Error states.
- Accessibility pass.
- Privacy labels.
- App icon and metadata.
- TestFlight build.
- App Review notes explaining DRM-free EPUB import and autoscroll controls.

Exit criteria:

- Build is ready for external beta or App Store submission.
