# Speechify-class Playback Transport + Live Voice/Model Switching

## Goal

Upgrade Rhea's reader from a single circular play button to a Speechify-class transport HUD that makes every playback control intuitive and transparent, so users can pick a voice, change speed, skip sentences, scrub progress, start reading from any clicked word, and switch voice/model mid-playback — all without opening Settings.

## What I already know

**Current state (from source inspection):**

- `RootView.swift:101-106` — bottom-right floating button is the only transport UI; no progress, speed, voice, or skip controls.
- `PlaybackControlsView.swift` — single `togglePlayPause` button.
- `SpeechPlayer.swift` — already has `nextSentence()`/`previousSentence()` public APIs, private `seek(to:)`, state exposes `sentenceIndex`; prefetch caches both Kokoro and Qwen PCM; alignment task drives word-level `spokenSubRange`.
- `SettingsView.swift:40-66` — voice picker lives in Settings only. Grouped by Kokoro / Qwen / System-language.
- `KokoroEngine.shared.voices` — **empty until `loadIfNeeded()` runs.** Settings picker hides Kokoro section when the list is empty, so a fresh launch shows no Kokoro section even when the model is on disk. Root cause of "only Apple default voice" bug #1.
- `SpeechSettings.voiceIdentifier` defaults to `nil` → system voice path. Root cause of "only Apple default voice" bug #2.
- `LibrarySidebarView.swift:41` uses `Text(entry.lastOpened, style: .relative)` — the "2 min, 32 sec" auto-ticking timestamps.
- `MarkdownReaderView` + `EPUBReaderView` both use `NSTextView` with `isSelectable = true` — subclassable for mouseDown/menu overrides.
- `PDFViewerView` uses PDFKit's `PDFView`; `PDFPage.characterIndex(at:)` and `block.offsetInPage` math already present for highlight path — reversible for hit-to-sentence lookup.
- `ReadingStats` tracks wordsPerMinute — usable for elapsed/remaining estimate.
- `MenuBarCommand` owns a **separate** `SpeechPlayer` for menubar clipboard reads. Transport HUD only needs to bind to the window-scoped `player` in `RootView`.

**Competitive research (verified via web, 2025-2026 sources):**

- Speechify desktop reader uses **sentence-snap skip**, not seconds (help.speechify.com).
- Speechify speed range: **0.5× – 4.5×** (100–900 wpm); vertical slider with +/− buttons in left toolbar popover.
- Speechify voice picker lives in left toolbar; premium marked with yellow diamond; scrollable list.
- Speechify supports **click-any-word-to-start-reading** (confirmed).
- ElevenReader: speed 0.25×–4×, 800+ voices, bookmarks + sleep timer.
- Speechify keyboard shortcuts: Alt+A start, Alt+Q pause, Alt+D faster, Alt+S slower (customizable).

## Requirements

### R1 — Transport HUD

Replace bottom-right button with a capsule-shaped transport bar anchored **bottom-center** on document views, `.ultraThinMaterial` background, auto-hides 3s after mouse-leave + playback paused. Layout left→right:

1. Skip-previous-sentence button (⏮, tooltip: "Previous sentence (≈15s)")
2. Play/pause button (44pt, `Color.rheaAccent` filled, matches current style)
3. Skip-next-sentence button (⏭, tooltip: "Next sentence (≈15s)")
4. Scrubber: `Slider(value: sentenceIndex, in: 0...total-1, step: 1)` — sentence-snap, drag-preview shows target sentence text tooltip, release commits + resumes play if previously playing
5. Time readout: `elapsed / total` estimate from ReadingStats WPM (fallback 165 wpm × rate); tooltip notes "estimated"
6. Speed chip: shows `1.0×`, opens popover — preset row (0.75 / 1.0 / 1.25 / 1.5 / 2.0) + vertical slider (0.5×–4.0×) + "−" / "+" 0.1-step buttons; footer "Applies at next sentence"
7. Voice chip: shows current voice name + engine badge (`System` / `Kokoro` / `Qwen`); opens menu grouped by engine; each row has ▶︎ preview button (short pre-recorded sample if bundled, otherwise speaks "The quick brown fox…" via that voice); premium-style inline download CTA for any model not yet on disk
8. Settings gear (opens existing Settings window for pronunciation/analytics)

### R2 — `SpeechPlayer` API extensions

- `func setVoice(_ id: String?)` — live voice swap. If playing, stops current engine + clears prefetch caches + restarts **current** sentence on new engine. Emits a one-shot `lastSwitchEvent: SwitchEvent?` so the UI can show an undo toast.
- `func setRate(_ rate: Double)` — persists via `SpeechSettings.rate`; applies at next sentence for all engines (AVSpeech is immutable mid-utterance, neural engines synthesize per-sentence).
- `func playFromSentence(_ index: Int)` — public wrapper over existing private `seek` that **forces playing state** (existing `seek` preserves idle/paused). Used by scrubber release and click-to-start.
- `var progress: Progress` — `(currentIndex, total, estimatedElapsed, estimatedRemaining)`. Recomputed on state change; time estimate uses ReadingStats WPM × rate.

### R3 — Eager voice catalogs

`PlaybackTransportView` `.task` kicks `KokoroEngine.shared.loadIfNeeded()` and `QwenEngine.shared.loadIfNeeded()` concurrently at first mount. Same in `SettingsView.playbackTab` `.task`. Fixes the "Kokoro section invisible on fresh launch" bug.

### R4 — Click-to-start-from-word (all three viewers)

- **Markdown + EPUB:** subclass `ClickableReaderTextView : NSTextView`. Override:
  - `mouseDown(with:)` — if modifier flags == `[]` and click count == 2: translate char index → sentence index (binary search over `sentence.offsetInBlock..<offsetInBlock+lengthInBlock`), call `player.playFromSentence(i)`. Click count == 1 still selects (preserves copy behavior).
  - `menu(for:)` — append "Read from here" + "Read from here to end" items. "To end" uses existing `player.sentences` slicing + load.
- **PDF:** gesture recognizer on `PDFView` for double-click; `view.page(for: point, nearest: true)` + `page.characterIndex(at: pointInPage)` + reverse `block.offsetInPage` → sentence binary search → `player.playFromSentence(i)`. Context menu via `menuForEvent` override.

### R5 — Keyboard shortcuts

Extend `AppScene` commands:

- `⌘]` / `⌘[` — speed +/− 0.1
- `⌘→` / `⌘←` — already wired; keep semantics (next/prev sentence)
- `⌘↑` / `⌘↓` — volume quick-adjust (future, not in MVP)
- `⌘⇧V` — open voice menu
- `Space` — play/pause when reader has focus and the scroll view is not consuming it

### R6 — Sidebar timestamp fix

`LibrarySidebarView.swift:41` — replace `Text(entry.lastOpened, style: .relative)` with a cached `RelativeDateTimeFormatter`-produced string at render time, or a DateFormatter-based "Today 3:42 PM" / "Yesterday" / "Apr 11" rule. Stops the per-second re-render.

### R7 — User-defined regex skip patterns

Extend `ResearchCleanup` from hardcoded academic patterns to a user-editable rule list. A "skip rule" is:

```
SkipRule {
  id: UUID
  label: String          // human-readable ("Bracketed footnotes")
  pattern: String        // ICU regex string
  replacement: String    // default "" (strip). Can be literal like "citation" or "figure"
  isEnabled: Bool
  appliesTo: .allDocs | .currentDoc(URL)   // MVP = allDocs only; per-doc deferred
}
```

**Storage:** `SpeechSettings.customSkipRules: [SkipRule]` persisted to UserDefaults as JSON. Ships with three built-in rules **enabled by default** so research-PDF users get immediate value with no setup:

- `\[\d+\]` — "Bracketed footnotes" (e.g., `[1]`, `[12]`)
- `cite:\S+` — "cite: references" (e.g., `cite:smith2019`)
- `\\cite\{[^}]+\}` — "LaTeX citations" (e.g., `\cite{smith2019}`)

Users can disable or delete any of these from the dedicated Settings tab.

**Apply point:** new method `ResearchCleanup.applyCustomRules(_:rules:) -> String` chained inside `clean(_:stripCitations:customRules:)`. Called from all three engine paths in `SpeechPlayer` (already the case for `ResearchCleanup.clean`). Spoken text only — visible document unchanged.

**Settings UI** — **new dedicated tab** `Settings → Skip Rules` (sibling of Playback, Models, Pronunciation, Analytics):
- Table editor: columns `[✓ enabled] | Label | Pattern | Replacement | Matches: N` where N is live match count against the currently-loaded document.
- Buttons: Add / Remove / Duplicate / Test…
- "Test…" opens an inline sheet with a text field; user pastes sample text, gets live preview of the cleaned output with matched ranges highlighted.
- Invalid regex: row shows red error badge with localized NSRegularExpression error; the rule is auto-disabled at apply time (never crashes playback).

**Transport HUD integration:**
- Small "Skip rules" chip shows count of active rules: `Skip: 3`.
- Click opens popover listing rules with per-rule toggles — mid-reading changes apply to **next sentence** (not current, since current sentence's text is already being spoken). Prefetch cache invalidated on any toggle (same pattern as voice switch) so pre-synthesized next sentence reflects the new rules.
- Tooltip on chip: "Text patterns stripped from speech. Visible document unchanged."

**Safety & transparency:**
- Each rule has a regex-compile check on save; invalid rules can't be saved as enabled.
- Match count is computed in background and reported per-doc (non-blocking) so user sees impact before enabling.
- If a rule matches so aggressively that an entire sentence becomes empty after cleanup, that sentence is skipped entirely (warning in journal log on first occurrence per session).

### R8 — Transparency of side effects

Every control surfaces its consequence before or immediately after the user commits:

- **Voice switch while playing** — immediate switch + undo toast bottom-right: "Voice changed to Sky. Sentence restarted. ⟲ Undo" (3s dismiss).
- **Speed change while playing** — inline footer on the popover: "Applies at next sentence."
- **Skip ±1 sentence** — tooltip "Next sentence (≈15s)". The "≈15s" comes from current sentence word count × WPM.
- **Click-to-start** — on double-click, cursor briefly pulses at the word; transport scrubber animates to new position.
- **Scrubber drag** — live tooltip shows first 40 chars of target sentence; release auto-resumes play state (was playing → keeps playing).

## Acceptance Criteria

- [ ] Bottom-center transport HUD visible whenever a document is loaded, hides 3s after mouse-leave while paused/idle.
- [ ] Voice chip in transport lists all Kokoro + Qwen voices on fresh launch with no prior Settings visit (R3).
- [ ] Switching voice mid-playback restarts the current sentence within 1s on Kokoro; undo toast appears and, if clicked within 3s, restores prior voice + restarts sentence again.
- [ ] Speed popover changes take effect at next sentence boundary, confirmed by WPM change in ReadingStats over 3+ sentences.
- [ ] Scrubber drag shows tooltip with next sentence preview; release commits `playFromSentence`.
- [ ] `⌘]` / `⌘[` change speed by 0.1 steps; value visible in speed chip.
- [ ] Double-click on a word in Markdown / EPUB / PDF starts reading from that word's sentence within 500ms (system voice) or neural-engine synth time (cached after first pass).
- [ ] Right-click menu in all three viewers contains "Read from here" + "Read from here to end".
- [ ] Sidebar library timestamps render as "Today 3:42 PM" / "Yesterday" / "Apr 11" and do not re-render every second (visually verified + confirmed via SwiftUI instrumentation).
- [ ] Custom skip-rule list round-trips through UserDefaults; built-in examples ship disabled; invalid regex can't be saved as enabled.
- [ ] Transport HUD "Skip: N" chip reflects the active rule count; toggling a rule mid-playback invalidates prefetch and takes effect at next sentence.
- [ ] A user-added rule `\[\d+\]` strips `[1]`, `[23]` etc. from spoken output; the rendered document still shows them.
- [ ] "Test…" sheet in Settings previews regex matches on pasted sample text with highlighted ranges.
- [ ] All existing tests still pass; new unit tests for `setVoice` cache-clear, `playFromSentence` state transitions, sentence-index binary search correctness, and `applyCustomRules` (including malformed-regex safety, fully-empty-sentence handling).
- [ ] No regression in `KokoroEngine` / `QwenEngine` prefetch behavior (M4.x export path still works).
- [ ] Export audiobook respects enabled skip rules — export path runs text through the same cleanup pipeline.

## Definition of Done

- Unit tests: `SpeechPlayer` live-voice-switch, `playFromSentence` behavior in all three states (idle/playing/paused), sentence-index binary-search correctness (edge: empty string, single sentence, index at block boundary).
- Manual QA matrix run and logged in `.trellis/workspace/Harvey/journal-1.md`: 3 engines (System/Kokoro/Qwen) × 3 viewers (PDF/Markdown/EPUB) × 5 controls (play, skip, scrub, speed, voice-switch) × 2 states (playing/paused).
- Swift build green on `scheme Rhea -configuration Release`.
- `Scripts/package.sh` still produces a working DMG with the new HUD.
- Journal entry documents the Speechify parity decisions (sentence-snap scrubber, 4.0× cap, immediate-switch+undo vs confirm-dialog).
- `docs/design/` (or equivalent) updated with a one-page transport HUD layout doc if any additional rendering rules beyond this PRD emerge.

## Technical Approach

### New files

- `App/Sources/Playback/PlaybackTransportView.swift` — the capsule HUD; owns voice-menu + speed-popover sub-views as nested structs.
- `App/Sources/Playback/PlaybackProgress.swift` — pure struct computing `(elapsed, remaining)` from sentences + WPM + current index.
- `App/Sources/Playback/ClickableReaderTextView.swift` — NSTextView subclass for Markdown + EPUB click/right-click handling.
- `App/Sources/Playback/ReaderHitTester.swift` — pure helpers: char-index → sentence binary search; PDF-point → char offset.
- `App/Sources/Document/SkipRule.swift` — `SkipRule` model + JSON codable + regex-compile validation.
- `App/Sources/Settings/SkipRulesEditor.swift` — Settings-tab table editor + test sheet.

### Modified files

- `App/Sources/Playback/SpeechPlayer.swift` — expose `setVoice`, `setRate`, `playFromSentence`, `progress`, `lastSwitchEvent`.
- `App/Sources/Playback/PlaybackControlsView.swift` — delete, absorbed into `PlaybackTransportView`.
- `App/Sources/RootView.swift` — swap `PlaybackControlsView` for `PlaybackTransportView`; anchor change corner→bottom-center.
- `App/Sources/Markdown/MarkdownReaderView.swift` — `MarkdownTextView` uses `ClickableReaderTextView` and passes `player` + `sentences`.
- `App/Sources/EPUB/EPUBReaderView.swift` — same treatment for `EPUBTextView`.
- `App/Sources/PDFViewer/PDFViewerView.swift` — add double-click gesture + context menu to `PDFViewRepresentable`.
- `App/Sources/Library/LibrarySidebarView.swift` — replace `style: .relative` (line 41).
- `App/Sources/AppScene.swift` — add `⌘]` / `⌘[` / `⌘⇧V` commands + notifications.
- `App/Sources/Settings/SettingsView.swift` — add `.task` that calls `KokoroEngine.loadIfNeeded()` + `QwenEngine.loadIfNeeded()` on first appear; extend Research PDFs tab with Skip Rules section.
- `App/Sources/Document/ResearchCleanup.swift` — extend `clean(_:stripCitations:)` → `clean(_:stripCitations:customRules:)`; add `applyCustomRules` helper.
- `App/Sources/Settings/SpeechSettings.swift` — add `customSkipRules: [SkipRule]` with UserDefaults JSON persistence.
- `App/Sources/Playback/SpeechPlayer.swift` — pass `SpeechSettings.shared.customSkipRules` into all three engine paths; invalidate prefetch caches when rule list changes (observe via `didSet` notification).
- `App/Sources/Export/AudioExporter.swift` — apply same `customSkipRules` when preparing text for batch synthesis (parity with live playback).

### Tests

- `Tests/AppTests/SpeechPlayerVoiceSwitchTests.swift` (new) — live-switch clears prefetch, restarts current sentence, emits switch event.
- `Tests/AppTests/PlaybackProgressTests.swift` (new) — elapsed/remaining math under edge cases (empty, single sentence, mid-sentence).
- `Tests/AppTests/ReaderHitTesterTests.swift` (new) — binary search over sentence ranges, edge cases at boundaries.
- `Tests/AppTests/SkipRuleTests.swift` (new) — JSON round-trip, regex-compile validation (valid + malformed patterns), `applyCustomRules` correctness across built-in example patterns, empty-sentence-after-cleanup handling.
- Manual checklist in journal (see DoD).

## Decision (ADR-lite)

**Context:** Playback UI is a make-or-break piece of user trust in a TTS reader. Current single-button UI shows the app reads, but hides every control that lets the user steer (voice, speed, position). Speechify's polish is the market benchmark; users expect parity.

**Decision:**

1. **Sentence-snap scrubber, labeled "≈N seconds"** rather than fake seconds-scrubbing. Matches Speechify's desktop behavior (verified) and respects neural-engine reality (can't mid-sentence resume).
2. **Speed cap at 4.0×** vs Speechify's 4.5×. Intelligibility on Kokoro and Apple voices degrades past 3.5×; 4.0× leaves headroom without promising a useless extreme.
3. **Immediate voice switch + undo toast** rather than pre-switch confirm dialog. One click matches Speechify's flow, undo covers mis-clicks, sentence-restart cost is ≤1s on cached sentences.
4. **Click-to-start on double-click**, single-click preserves text selection. Matches macOS text conventions; users expect single-click to set cursor/selection, not trigger audio.

**Consequences:**

- Slight departure from Speechify's "tap any word" (single-click) to respect macOS conventions. Mitigation: right-click "Read from here" also exists; double-click is conventional for "activate" across macOS.
- Time display labeled "estimated" is honest but slightly less polished than Speechify's exact-timestamp feel (they can afford exact because streaming synthesis lets them know total duration ahead of time; we don't).
- Sentence restart on voice switch is visible to user as a 0.3–1s gap. Acceptable because the alternative (complete the current sentence on old voice, switch for next) is confusing when the user picked the new voice *because* they didn't like the one currently reading.

## Out of Scope

- Sleep timer (Speechify 5/10/15/30/45/60m presets) — defer to future task.
- Bookmarks / notes attached to positions — defer.
- Auto-scroll toggle during playback — defer; existing scroll-to-active-sentence already handles common case.
- Voice preview **recorded samples** — MVP uses on-the-fly synthesis of "The quick brown fox jumps over the lazy dog" via the target voice. Recorded samples are a content-production task.
- Chapter navigation — no sentence-to-chapter mapping in current data model.
- Volume control inside HUD (system volume suffices for MVP).
- Customizable keyboard shortcut editor — use Speechify-style defaults only.
- Progress position persistence across app restarts — existing library only tracks last-opened, not read position.
- PDF page-level scrubber (separate from sentence scrubber) — defer; sentence scrubber is enough for MVP.
- **Per-document skip rule scopes** — MVP is global only (all docs). Per-doc scoping deferred.
- **Regex-based pronunciation substitution with match groups** — existing `PronunciationDictionary` handles literal substitutions; full regex-with-backrefs for pronunciation is a separate task.
- **Skip-rule sharing / import-export** — deferred; users can copy JSON manually if needed.

## Technical Notes

- `SpeechPlayer` is `@MainActor`-isolated. All new APIs stay on main actor. No concurrency refactors needed.
- Prefetch-cache invalidation on `setVoice` is critical: failing to clear would replay the previous voice's PCM for sentence N+1. Test covers this explicitly.
- `AVSpeechSynthesisVoice.speechVoices()` is synchronous + cached — safe to call from main actor at settings-open time.
- `PDFView.page(for:nearest:)` returns `PDFPage?`; must handle nil on clicks outside page bounds (e.g., gutter).
- `NSTextView.characterIndexForInsertion(at:)` returns `Int` in UTF-16 units; matches `NSAttributedString.length` so binary search indices align.
- Sentence binary search: `sentence.offsetInBlock..<(offsetInBlock + lengthInBlock)` — use `partitioningIndex` or manual binary search over sorted `offsetInBlock` values. Sentences are pre-sorted by the segmenter.
- `ReadingStats.wordsPerMinute` returns 0 when disabled — transport falls back to `165 wpm × rate` default.
- Voice-menu preview must not interrupt the currently-playing sentence. Previews run on a separate ephemeral `AVSpeechSynthesizer` / `PCMAudioPlayer` instance to avoid clobbering main playback state.
- The undo toast reuses `RootView`'s existing `.overlay(alignment: .top)` export-banner pattern — consistent placement.

## Implementation Plan (staged PRs)

**PR1 — Foundation + hotfixes (small, mergeable alone)**

- Sidebar timestamp fix (R6).
- `SpeechPlayer` API extensions: `setVoice`, `setRate`, `playFromSentence`, `progress`, `lastSwitchEvent` (R2).
- Unit tests for new `SpeechPlayer` APIs.
- Eager voice catalog load in `SettingsView` (R3, partial).

**PR2 — Transport HUD core**

- `PlaybackTransportView.swift` with all 8 control groups (R1).
- `PlaybackProgress.swift` (progress math).
- Voice-menu sub-view with eager load (R3 complete).
- Speed popover sub-view.
- Keyboard shortcuts: `⌘]` / `⌘[` / `⌘⇧V` (R5 partial).
- Swap in `RootView`, delete old `PlaybackControlsView`.

**PR3 — Click-to-start across viewers**

- `ClickableReaderTextView` subclass (R4 Markdown + EPUB).
- PDF double-click + context menu.
- `ReaderHitTester` helpers + unit tests.

**PR4 — Custom skip patterns**

- `SkipRule` model + JSON persistence in `SpeechSettings` (R7).
- `ResearchCleanup.applyCustomRules` + wire through `SpeechPlayer` + `AudioExporter`.
- Settings → Research PDFs "Custom skip patterns" editor + Test sheet.
- Transport HUD "Skip: N" chip + popover.
- Prefetch invalidation on rule toggle.
- Unit tests for rules.

**PR5 — Transparency polish**

- Undo toast for voice switch (R8).
- Scrubber drag preview tooltip.
- Skip-button ≈N-seconds tooltip.
- Speed popover footer.
- Final QA matrix run + journal entry.
