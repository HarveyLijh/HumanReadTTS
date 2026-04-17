# Good-morning handoff

State at wake-up. Delete or rewrite when back.

## What Rhea does now

Drop a PDF, Markdown, or EPUB (or ⌘O, or `open -a Rhea file.pdf`).
It renders the doc, extracts text, segments into sentences,
plays them aloud with an amber highlight that follows the voice
through the page. Sentence-wide wash + brighter word-level
sub-highlight on the currently-spoken word (system voices;
Kokoro is sentence-level until M2.3).

Library sidebar remembers what you opened; click to reopen.
Menubar Rhea item reads whatever's in your clipboard on ⌘⇧R.
Settings (⌘,) has four tabs: Playback, Models, Pronunciation,
Analytics. Pick Kokoro voices once the model is downloaded from
the Models tab. Export the current doc as an `.m4a` audiobook
via File → Export Audiobook… (⌘⇧E).

## Keyboard shortcuts
| Key | Action |
| --- | --- |
| Space | Play / Pause |
| ← | Previous sentence |
| → | Next sentence |
| ⌘O | Open File… |
| ⌘⇧E | Export Audiobook… |
| ⌘⇧R | Read Clipboard (from menubar) |
| ⌘, | Open Settings |

## Milestone coverage

### Month 1 — complete
M1.1 skeleton · M1.2 PDF rendering · M1.3 PDFKit extraction ·
M1.4 sentence segmenter (NLTokenizer, EN+ZH) · M1.5 playback
(system voice, speed/pitch) · M1.6 sentence-level amber
highlight · M1.7 library sidebar with UserDefaults-backed
security-scoped bookmarks.

### Month 2
- M2.1 ✅ Kokoro on-device English TTS, downloadable model, voice picker
- M2.4 ✅ Word-level highlight via `willSpeakRange` (system voices; Kokoro sentence-level)
- M2.5 ✅ Settings tabs, speed/pitch sliders, voice override
- M2.7 ✅ Markdown renderer with Preview/Source toggle, proper block separators
- M2.2 ⏳ pre-buffering polish (one-shot-per-sentence ships live)
- M2.3 ⏳ WhisperKit forced alignment (Kokoro word timestamps)
- M2.6 ⏳ Services menu + ⌘⇧S global hotkey

### Month 3 — partial
- M3.5 ✅ Research-PDF heuristics (inline citation + figure/table caption stripping)
- M3.1–M3.4 ⏳ Qwen3-TTS bilingual orchestrator
- M3.6, M3.7 ⏳ marketing + distribution

### Month 4 — mostly
- M4.1 ✅ Audiobook export (`.m4a`, both engine paths)
- M4.3 ✅ EPUB support (ZIPFoundation + NSAttributedString HTML render)
- M4.4 ✅ Menu-bar item, Read Clipboard
- M4.5 ✅ Local reading analytics (opt-in)
- M4.6 ✅ Pronunciation dictionary
- M4.2 ⏳ voice cloning

## Tests
- **75 tests passing** under `Scripts/test.sh`
- Suites: DroppedDocument, Library, MarkdownRenderer, ModelCatalogReachability, ModelStorage, PDFDocumentLoader, PDFTextExtractor, PronunciationDictionary, ReadingStats, ResearchCleanup, SentenceSegmenter
- `Scripts/test.sh --network` — opt-in live-URL check against the Kokoro catalog (3/3 pass)

## Build / run / test
```sh
Scripts/build.sh --clean --run    # compile + launch
Scripts/test.sh                   # 75-test offline run
Scripts/test.sh --network         # + 3 live URL checks
```

### Launch note
`Scripts/build.sh --run` uses direct-exec instead of `open`.
LaunchServices stalls for 30+ seconds on every fresh ad-hoc
signature when the bundle lives under `~/Documents`. Proper fix
is a stable Developer-ID signing identity — will adopt when we
sign for notarised .dmg distribution per MILESTONES §0.

## Peekaboo E2E screenshots
Under `/tmp/rhea-e2e/`:
- `40-empty.png` / `99-final-state.png` — centred empty state
- `41-settings-playback.png` — Voice picker, speed/pitch, research toggles
- `42-settings-pronunciation.png` — dictionary empty state + add form
- `43-settings-analytics.png` — privacy toggle + off state

## Fixture paths (left alone)
| Path | Size | Content |
| --- | --- | --- |
| `~/rhea-fixtures/short-english.md` | 112 B | H1 + paragraph + H2 + bold/italic/code |
| `~/rhea-fixtures/short-english.pdf` | 83 KB | 15-Week Plan — research PDF |
| `~/rhea-fixtures/chinese.pdf` | 197 KB | Liu Cixin collection |
| `~/rhea-fixtures/chinese.md` | 19 KB | Liu Cixin collection |

## Commit trail this session (34 commits)
```
73a70d6 feat(pdf): word-level highlight via willSpeakRange (M2.4, PDF)
5e64b24 docs(handoff): add keyboard shortcut reference
616eee4 feat: File → Open File… menu (⌘O)
ff96ce7 feat(playback): keyboard shortcuts — Space, ←, → (M1.5 polish)
aad6267 docs(handoff): M2.4 word highlight shipped
f77f437 feat(playback): word-level highlight via willSpeakRange (M2.4, system voices)
2960158 docs(handoff): full status after overnight build push
9952a06 feat: EPUB support (M4.3)
7f2f64e fix(build): --run direct-execs instead of using LaunchServices
9766148 fix(build): embed any PackageFrameworks missing from the app bundle
9a327e3 feat: audiobook export to .m4a via AVAudioFile (M4.1)
aedc758 feat: local reading analytics (M4.5)
0e65271 feat: research-PDF citation stripping + figure skipping (M3.5)
ac2692a feat: menu bar + pronunciation dictionary (M4.4, M4.6)
3ce8258 fix(tcc+library): path-based dedup avoids filesystem hits
f6d639e fix: library click loads document; open -a Rhea routes file URLs
f761cb9 test: e2e integration suite + Scripts/test.sh + Kokoro URL fix
9eb564b feat(kokoro): on-device English TTS via Kokoro v1.0 (M2.1 part 2)
...
```

Full log: `git log --oneline`.

## What I'd pick up next
1. **M2.6 Services menu + global hotkey** — NSServices registration (needs a custom Info.plist, moderate pbxproj work).
2. **Stable Developer-ID signing** — kills the LaunchServices hang permanently.
3. **M2.3 WhisperKit forced alignment** — Kokoro word timestamps; also fixes word-highlight drift under Pronunciation / Research transformations.
4. **Chapter markers in m4a** — promote to proper `.m4b`; needs AVAssetWriter rewrite of AudioExporter.
5. **M3.1 Qwen3-TTS bilingual** — another SwiftPM dep + model catalog entry + per-sentence engine routing.
6. **M2.2 streaming synthesis** — paragraph pre-buffering for zero-gap playback boundaries.

Sleep well. Coffee works on me too.
