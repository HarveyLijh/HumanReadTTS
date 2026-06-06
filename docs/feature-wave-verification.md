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

### Current environment blockers

Two parts of the original request — a green XCTest run and screenshots/gifs —
are blocked by the machine state, not by the code:

- **XCTest runner wedged.** `xcodebuild test` fails with "The test runner hung
  before establishing connection" (~330s, 0 tests). Intermittent and
  environmental: it ran green earlier today (149 tests, 0 failures) then
  re-wedged. Clears on reboot or one `Product > Test` run in Xcode. Until then,
  each PR is gated on a clean build plus standalone logic checks, and the
  written XCTest cases run as soon as the runner recovers.
- **Display asleep → no screenshots.** With the Mac display asleep/locked,
  `CGGetActiveDisplayList` reports 0 active displays, screen capture returns
  "No displays available", and the menu-bar app composites no visible window.
  Screenshots/gifs of the new UI need the display awake and unlocked.

To capture the live screenshots once the display is awake, see
`docs/`-adjacent notes: seed a face with
`defaults write app.readaloudtts.mac app.readaloudtts.mac.reader.fontFace.v1 -string openDyslexic`,
`open <built app> <sample.md>`, capture the reader window, then delete the key.

## Status by feature

### Accessibility & Readability Aids

| PR | Scope | Build | Logic | XCTest written | Live |
| --- | --- | --- | --- | --- | --- |
| 1 — Highlight seam | `HighlightStyle` + palette/opacity, all 5 readers routed | ok | ok | `HighlightStyleTests` (5) | pending display |
| 2 — Typography | `ReaderTypography`, bundled OpenDyslexic + Atkinson Hyperlegible, Markdown/Text/Scratchpad threaded, launch registration | ok | ok (`/tmp/verify_typography.swift`, all pass) | `ReaderTypographyTests` (16) | pending display |
| 4a — Reading tab | Settings → Reading: font, size, spacing, highlight, live previews, OFL attribution | ok | n/a (binds tested `ReaderSettings`) | — | pending display |
| 3 — Line focus + leading bold | reading ruler + bionic emphasis | todo | | | |
| 4b — Reading themes | sepia/dark reading surface | todo | | | |

### Now Playing + media keys + sleep timer + queue

| PR | Scope | Build | Logic | XCTest written | Live |
| --- | --- | --- | --- | --- | --- |
| 1 — Now Playing | `NowPlayingController`, Control Center + media keys | ok | ok | `NowPlayingMappingTests` (5) | pending hardware |
| 3 — Sleep timer | `SleepTimer`, minute presets + end-of-sentence, menu | ok | ok | `SleepTimerTests` (8) | pending hardware |
| 2 — media/AirPods hardening | on-device only | n/a | | | handed to user |
| 4 — Reading queue | `ReadingQueue`, `onReachedEnd`, Playback Controls tab | todo | | | |

### Bilingual & Language-Learning — not started

### On-device OCR — not started

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
