# Manual Scroll + Jump-to-Current ("Spotify lyrics" follow)

Date: 2026-06-06
Status: Approved (design)

## Problem

While a document is being read aloud, every reader auto-scrolls to keep the
currently-spoken sentence in view. The scroll fires on each sentence-index
change, so even though a user can scroll *within* a sentence, the next sentence
boundary (a few seconds later) yanks the viewport back to the highlight. A user
who scrolls ahead or back to read another part of a long article gets pulled
back within seconds.

Desired behavior, modeled on Spotify's lyrics view:

1. When the user manually scrolls, the reader stops following the highlight and
   stays exactly where the user put it. Playback and the highlight keep going.
2. A floating "jump to current" button appears. Tapping it scrolls back to the
   current highlight and resumes auto-follow.

Decision (confirmed with user): **manual button only** — once the user scrolls
away, the viewport never moves on its own again until the button is tapped (no
idle auto-re-engage). Applies to **all five formats**: Text, Markdown, EPUB,
PDF, DOCX.

## Current mechanism (as built)

All readers gate auto-scroll on sentence-index change inside their
NSViewRepresentable coordinators:

| Format   | Scroll call                       | File / line                       |
|----------|-----------------------------------|-----------------------------------|
| Text     | `textView.scrollRangeToVisible`   | `App/Sources/Text/TextReaderView.swift:368` |
| EPUB     | `textView.scrollRangeToVisible`   | `App/Sources/EPUB/EPUBReaderView.swift:293` |
| Markdown | `textView.scrollRangeToVisible`   | `App/Sources/Markdown/MarkdownReaderView.swift:1628` |
| PDF      | `view.go(to: sentenceSelection)`  | `App/Sources/PDFViewer/PDFViewerView.swift:340` |
| DOCX     | `textView.scrollRangeToVisible`   | `App/Sources/DOCX/DOCXReaderView.swift` (same pattern) |

Each coordinator stores `lastScrolledSentenceIndex` and scrolls only when the
index changes. Playback state comes from `SpeechPlayer` (`@Observable`,
`App/Sources/Playback/SpeechPlayer.swift`): `state.sentenceIndex` is the active
sentence; `spokenSubRange` is the word-level highlight (never triggers scroll).

## Design

### 1. Core state — `ReaderFollowState`

New `@Observable @MainActor` class (shared component, one file under
`App/Sources/Reader/`). Owned per reader view as `@State`, passed into the
NSViewRepresentable and read by the overlay.

```swift
@Observable
@MainActor
final class ReaderFollowState {
    private(set) var isFollowing: Bool = true
    private(set) var jumpToken: Int = 0          // bumped to request one scroll-to-highlight

    func userDidScroll() {                        // called from live-scroll detection
        if isFollowing { isFollowing = false }
    }

    func jumpToCurrent() {                         // called by the button
        isFollowing = true
        jumpToken &+= 1
    }

    func resumeFollowing() {                       // new doc / read-from-here / play
        isFollowing = true
    }
}
```

`jumpToken` is the bridge from a SwiftUI tap to an imperative AppKit scroll:
mutating it re-invokes `updateNSView`, which performs the scroll exactly once.

### 2. Detecting manual scroll — `ReaderScrollObserver`

Shared helper that observes `NSScrollView.willStartLiveScrollNotification` on a
given scroll view and calls a closure. This notification fires for trackpad,
scroll-wheel, and scrollbar-knob drags, and is **not** emitted by programmatic
`scrollRangeToVisible` / `go(to:)`, so no "is this my own scroll?" guard is
needed.

- Text / Markdown / EPUB / DOCX: observe `textView.enclosingScrollView`.
- PDF: `PDFView` keeps its scroll view internal; the helper recursively walks
  `pdfView.subviews` to find the inner `NSScrollView`, then observes it. If the
  scroll view is not yet present at setup time (PDFKit builds it lazily), retry
  on first `updateNSView`.

On notification → `followState.userDidScroll()`.

**Known v1 limitation:** keyboard-only scrolling (Page Up/Down, arrows) does not
post live-scroll notifications, so it will not enter manual mode in v1.
Trackpad/wheel/knob is the dominant case on macOS; a `boundsDidChange` +
programmatic-guard fallback can be added later if needed.

### 3. Gating existing auto-scroll

Each of the five call sites changes from:

```swift
if coordinator.lastScrolledSentenceIndex != currentIndex { … scroll … }
```

to:

```swift
if followState.isFollowing,
   coordinator.lastScrolledSentenceIndex != currentIndex {
    coordinator.lastScrolledSentenceIndex = currentIndex
    … scroll …
}
```

During manual mode `lastScrolledSentenceIndex` is left frozen and no scroll
fires; the sentence/word highlight keeps repainting in place (off-screen is
fine). Audio is unaffected.

### 4. Handling the jump request

In `updateNSView`, after the normal highlight pass, compare
`followState.jumpToken` to a coordinator-stored `lastHandledJumpToken`. If they
differ, scroll to the current sentence range (reuse the existing scroll call),
set `lastScrolledSentenceIndex` to the current index, and store the new token.
Because `jumpToCurrent()` also set `isFollowing = true`, subsequent
sentence-change ticks resume normal following.

### 5. The button — `JumpToCurrentButton`

Shared SwiftUI view placed in each reader's ZStack overlay.

```
   ┌────────────────────────────────────┐
   │  ...text where you scrolled...      │
   │                                     │
   │          ╭──────────────────╮       │
   │          │ ↓  Jump to current│      │   ← floating pill, bottom-center
   │          ╰──────────────────╯       │
   └────────────────────────────────────┘
```

- **Visible when** `!followState.isFollowing && player.state.sentenceIndex != nil`.
  Hidden when following, or when nothing is loaded/playing to follow.
- **Placement:** bottom-center, floating, `.regularMaterial` (or equivalent)
  background, rounded pill, subtle shadow; `.transition(.opacity)` fade.
- **Label:** "Jump to current". Leading SF Symbol; if the highlight's vertical
  position relative to the viewport is cheaply known, show `arrow.down`/
  `arrow.up` accordingly, else a neutral `scope`/`location` symbol.
- **Action:** `followState.jumpToCurrent()`.
- **Accessibility:** button label "Jump to current line"; respects the app's
  existing reduce-motion / theme conventions.

### 6. When follow auto-resets to ON (no button needed)

- A new document is loaded → fresh `ReaderFollowState` (default `isFollowing =
  true`). Also call `resumeFollowing()` on document-id change as a safety net.
- "Read from here" (double-click / right-click) → `resumeFollowing()` before/at
  `playFromSentence`, so the view scrolls to and tracks that point.
- Pressing Play/Resume from the transport → `resumeFollowing()`. Rationale:
  resuming means "carry on reading along." (Confirmed acceptable by user.)

Pausing does **not** change follow mode.

## Components / files

New (shared, under `App/Sources/Reader/`):
- `ReaderFollowState.swift` — the `@Observable` state object.
- `ReaderScrollObserver.swift` — live-scroll notification helper (+ PDF inner
  scroll-view finder).
- `JumpToCurrentButton.swift` — the floating SwiftUI pill.

Modified (wire-in, 5 readers):
- `TextReaderView.swift`, `MarkdownReaderView.swift`, `EPUBReaderView.swift`,
  `DOCXReaderView.swift`, `PDFViewerView.swift` — own a `ReaderFollowState`,
  attach the scroll observer in `makeNSView`, gate the scroll on `isFollowing`,
  handle `jumpToken` in `updateNSView`, overlay `JumpToCurrentButton`, and call
  `resumeFollowing()` on the reset triggers in §6.

## Testing

- **Unit (logic, runnable without the wedged app-hosted runner):**
  `ReaderFollowState` behavior — default is following; `userDidScroll()` flips to
  not-following (idempotent); `jumpToCurrent()` sets following + increments
  token; `resumeFollowing()` restores following. Button-visibility predicate
  (`!isFollowing && sentenceIndex != nil`) as a small pure function.
- **Build:** full `xcodebuild` of the app target (per the build-verify memory,
  the app-hosted XCTest runner hangs this session — verify via build + the logic
  tests above).
- **Live verification (screenshot-and-verify env):** play a long markdown
  article; scroll up mid-playback → confirm viewport stays put across a sentence
  boundary and the pill appears; tap the pill → confirm snap to highlight and
  pill disappears; repeat for PDF (real multi-page) and one of EPUB/DOCX/Text.
  Capture screenshots into `docs/verification-assets/`.

## Out of scope (YAGNI)

- Idle auto-re-engage (explicitly rejected in favor of manual button).
- Keyboard-scroll detection (v1 limitation noted above).
- Per-format button styling variations — one shared button for all.
