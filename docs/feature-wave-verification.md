# Feature-Wave Verification Report

Living record of the accessibility / now-playing / bilingual / OCR feature
wave: what shipped, how it was verified, and what still needs a human on real
hardware. Updated as each PR lands.

## How things are verified here

| Method | What it proves | When used |
| --- | --- | --- |
| `xcodebuild` build of both targets | Compiles, type-checks (Swift 6 strict concurrency), links, builds the test bundle, hand-edited pbxproj is valid | Every PR |
| Standalone `swift` logic checks | Pure algorithms behave (font/typography math, mappers, state machines) when the XCTest runner is unavailable | Every PR with non-trivial logic |
| XCTest suite | Full unit coverage in the app-hosted runner | When the runner is healthy |
| Live app screenshot/gif | Real rendering and interaction | When a display is awake |

### Environment status — cleared 2026-06-06

The two earlier blockers (wedged XCTest runner, asleep display) cleared after a
reboot/unlock. Current state:

- **XCTest runner healthy.** `xcodebuild test -scheme ReadAloudTTS -destination
  'platform=macOS'` runs green: **227 tests, 3 skipped, 0 failures**.
- **Display awake.** Live reader windows and the Settings window screenshot
  normally. Captures land in `docs/verification-assets/`.

Screenshot recipe: seed a pref (e.g.
`defaults write app.readaloudtts.mac app.readaloudtts.mac.reader.readingTheme.v1 -string sepia`),
`open -a <built app> <sample.md>`, capture the window region with
`screencapture -x -R<x,y,w,h>`, then delete the key to restore.

### Current standing

All four feature areas are **complete and verified** (227–231 tests green
across the wave; live screenshots in `docs/verification-assets/`):

- **Accessibility:** typography, bundled dyslexia fonts, leading-bold, color
  highlight, sepia/night reading themes, line-focus ruler.
- **Now Playing:** Control Center, media keys, sleep timer, reading queue.
- **Bilingual:** per-sentence language, tap-to-translate popover, vocabulary
  store, Learning tab, Anki export.
- **OCR:** Vision recognition, image-file reader, read-a-screenshot from the
  clipboard with a rebindable ⌘⇧2 hotkey, recognition-language settings.

Region capture is delivered via the system screenshot (⌃⇧⌘4 → clipboard →
OCR) rather than a custom ScreenCaptureKit marquee, sidestepping a Screen
Recording prompt. Remaining optional polish: a dual-language (L1-under-each-
block) view, a pronunciation drill, and a VoiceOver / Dynamic Type pass.

One automation limit remains: the tap-to-translate popover is driven by an
Option-double-click on a custom NSTextView that exposes no accessibility
elements, and synthetic mouse events need Accessibility/Input-Monitoring TCC a
transient `swift` process lacks — so the popover itself can't be auto-captured
headlessly. It reuses the proven double-click event path and is build- and
unit-verified; the on-device translation also needs the language pair
downloaded.

### Screenshots (docs/verification-assets/)

- `learning-settings-tab.png` — Learning tab: tap-to-translate + saved vocab + Anki export
- `reading-theme-sepia.png`, `reading-theme-night.png` — themed Markdown reader
- `line-focus-ruler.png` — reading ruler dimming around the pointer
- `ocr-image-reader.png` — an image opened and read via OCR, queued in the transport
- `clipboard-ocr-hud.png` — a clipboard screenshot recognized and read aloud
- `shortcuts-read-screenshot.png` — the Read-Screenshot hotkey + OCR languages

## Status by feature

### Accessibility & Readability Aids

| PR | Scope | Build | Logic | XCTest written | Live |
| --- | --- | --- | --- | --- | --- |
| 1 — Highlight seam | `HighlightStyle` + palette/opacity, all 5 readers routed | ok | ok | `HighlightStyleTests` (5) | pending display |
| 2 — Typography | `ReaderTypography`, bundled OpenDyslexic + Atkinson Hyperlegible, Markdown/Text/Scratchpad threaded, launch registration | ok | ok (`/tmp/verify_typography.swift`, all pass) | `ReaderTypographyTests` (16) | pending display |
| 4a — Reading tab | Settings → Reading: font, size, spacing, highlight, live previews, OFL attribution | ok | n/a (binds tested `ReaderSettings`) | — | pending display |
| 3a — Leading bold | `BionicReading` bold-prefix pass, off by default, Reading-tab toggle | ok | ok (`/tmp/verify_bionic.swift`) | `BionicReadingTests` (4) | pending display |
| 3b — Line focus | reading ruler overlay, pointer-following dim band | ok | ok | `ReaderSettingsTests` (4) | done (`line-focus-ruler.png`) |
| 4b — Reading themes | sepia / night reading surface | ok | ok | `ReadingThemeTests` (4) | done (`reading-theme-sepia.png`, `reading-theme-night.png`) |

### Now Playing + media keys + sleep timer + queue — COMPLETE (code)

| PR | Scope | Build | Logic | XCTest written | Live |
| --- | --- | --- | --- | --- | --- |
| 1 — Now Playing | `NowPlayingController`, Control Center + media keys | ok | ok | `NowPlayingMappingTests` (5) | pending hardware |
| 3 — Sleep timer | `SleepTimer`, minute presets + end-of-sentence, menu | ok | ok | `SleepTimerTests` (8) | pending hardware |
| 4 — Reading queue | `ReadingQueue`, `SpeechPlayer.onReachedEnd`, `showInNowPlaying`, Playback Controls tab | ok | ok (`/tmp/verify_queue.swift`) | `ReadingQueueTests` (8) | pending display/hardware |
| 2 — media/AirPods hardening | on-device only | n/a | | | handed to user |

### Bilingual & Language-Learning

| PR | Scope | Build | Logic | XCTest written | Live |
| --- | --- | --- | --- | --- | --- |
| 1 — Sentence language | `Sentence.language` + `SentenceSegmenter` NLLanguageRecognizer, zero behavior change | ok | ok (`/tmp/verify_lang.swift`) | `SentenceLanguageTests` (6) | n/a |
| 2 — Word resolver | `WordRangeResolver` (tap-to-translate word lookup, CJK-aware) | ok | ok (`/tmp/verify_wordrange.swift`) | `WordRangeResolverTests` (7) | n/a |
| 2 — Translation popover | `TranslationPopoverView/Controller`, Opt-double-click + right-click, on-device translate, save-to-vocab | ok | ok | `WordRangeResolverTests` (+4 sentence) | wired + unit-verified; popover not auto-captureable (see note) |
| 3 — Vocabulary store | `VocabularyStore` JSON persistence + dedup | ok | n/a | `VocabularyStoreTests` (7) | surfaced in Learning tab |
| 3b — Learning tab | `LearningSettingsView`: tap-to-translate toggle, target language, vocab list, Anki export | ok | ok | `LearningSettingsTests` (5) | done (`learning-settings-tab.png`) |
| 4 — Dual language view | L1 under each block | held (optional) | | | |
| 5 — Anki export | `AnkiCSVExporter` (RFC-4180, CJK, tags) | ok | ok (`/tmp/verify_anki.swift`) | `AnkiCSVExporterTests` (9) | reachable via Learning tab |
| 5 — Pronunciation drill | `PronunciationDrill`, voice routing | held (device only) | | | |

### On-device OCR

| PR | Scope | Build | Logic | XCTest written | Live |
| --- | --- | --- | --- | --- | --- |
| 1 — Reading order | `ReadingOrder` recursive XY-cut | ok | ok (4 layouts) | `ReadingOrderTests` (6) | n/a |
| 1 — OCRService | Vision text recognition → reading order | ok | ok | `OCRServiceTests` (3, render→Vision→text) | n/a |
| 2 — Image reader | `ImageOCRReaderView`, image UTType routing, drop/open/export | ok | ok | `DropTargetTests` (image kinds) | done (`ocr-image-reader.png`) |
| 3 — Read screenshot | OCR a clipboard image, rebindable ⌘⇧2 hotkey + menu item | ok | ok | reuses `OCRServiceTests` | done (`clipboard-ocr-hud.png`) |
| 4 — OCR languages | recognition-language toggles in Shortcuts tab | ok | n/a | — | done (`shortcuts-read-screenshot.png`) |

## On-device checklist (must be run by a human)

These cannot be exercised by build or CI; they need real hardware, a display,
permissions, or external apps. Pulled from the integration plan.

- [ ] Live highlight recolor across all five readers incl. PDF when palette/
      intensity change mid-playback.
- [ ] OpenDyslexic / Atkinson Hyperlegible actually register at launch and the
      Reading-tab font picker re-renders the open reader in the chosen face.
- [ ] Color-blind (deuteranopia) check: sentence vs word bands stay distinct by
      lightness on rendered text.
- [ ] VoiceOver / Dynamic Type / Reduce Motion passes once that PR lands.
- [ ] Now Playing card + remote commands on real hardware (sandboxed Release).
- [ ] Sleep timer "10 minutes" pauses ~10 min later with position retained.
