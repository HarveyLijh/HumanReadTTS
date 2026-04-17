# Sleep-Session Handoff

Status snapshot — delete or rewrite when back.

## What works end-to-end

### Month 1 (full)
- Drop PDFs / Markdown onto window; sidebar library with persistence
- PDF rendering (PDFKit), text extraction, sentence segmentation (EN+ZH via NLTokenizer)
- Markdown rendering with block separators + view-mode toggle (Preview/Source)
- Sentence-level highlight during playback (PDF via `PDFAnnotationHighlight`, Markdown via `NSTextStorage` background)

### Month 2 (mostly)
- **M2.1** Kokoro on-device English TTS — downloadable model (650 MB), voice picker, full engine wiring via MLX
- **M2.5** Settings window (⌘,) with Playback / Models / Pronunciation / Analytics tabs; per-utterance speed + pitch; voice override
- **M2.7** Proper Markdown reader with NSAttributedString rendering + Preview/Source toggle

- **M2.4** Word-level highlight via `willSpeakRange` for system voices — two-layer amber (soft sentence wash + brighter word). Kokoro path still sentence-level (needs WhisperKit for word timing).

Not yet in Month 2:
- **M2.2** Proper streaming synthesis / pre-buffering (current one-shot-per-sentence is fine for real-time, but paragraph pre-buffering is a polish item)
- **M2.3** WhisperKit forced alignment for precise Kokoro word timestamps (word highlight would drop to Kokoro voices too)
- **M2.6** Services menu "Read with Rhea" + global hotkey

### Month 3 (partial)
- **M3.5** Research-PDF heuristics — inline citation stripping `[12]` / `(Smith 2019)` + figure/table caption skip (opt-in toggles)

Not yet in Month 3:
- **M3.1–M3.4** Qwen3-TTS bilingual orchestrator (needs another SwiftPM package + ~1 GB model)
- **M3.6, M3.7** Marketing site + MAS/DMG distribution

### Month 4 (mostly)
- **M4.1** Audiobook export to `.m4a` (AAC) via `AVAudioFile`, both Kokoro and system-voice paths
- **M4.3** EPUB support — opens `.epub` via ZIPFoundation + NSAttributedString HTML render, plays via same sentence pipeline
- **M4.4** Menu-bar Rhea item with "Read Clipboard" (⌘⇧R), pause/resume, stop
- **M4.5** Reading analytics — local-only, opt-in, per-sentence accumulate, daily + all-time counters + streak
- **M4.6** Pronunciation dictionary — case-insensitive whole-word substitution pre-synth

Not yet in Month 4:
- **M4.2** Voice cloning
- Small polish items (reader navigation, chapter markers in m4b)

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

## Tests
- **75 tests passing** under `Scripts/test.sh`
- Suites: DroppedDocument, Library, MarkdownRenderer, ModelCatalogReachability, ModelStorage, PDFDocumentLoader, PDFTextExtractor, PronunciationDictionary, ReadingStats, ResearchCleanup, SentenceSegmenter
- `Scripts/test.sh --network` runs the opt-in live-URL check against the Kokoro catalog (currently 3/3 pass — URLs verified)

## Build / run / test
```sh
Scripts/build.sh --clean --run    # compile + launch (direct-exec, not `open`)
Scripts/test.sh                   # 75-test offline run
Scripts/test.sh --network         # + 3 live URL checks
```

### Known bug + workaround
`open Rhea.app` (via Finder or `open -a`) routes through LaunchServices,
which stalls for 30+ seconds while TCC decides whether to trust an
ad-hoc-signed bundle under `~/Documents`. `Scripts/build.sh --run`
uses direct-exec instead, which bypasses LaunchServices. Proper fix
= stable Developer-ID signing; will adopt with notarised .dmg.

## Peekaboo E2E screenshots
Under `/tmp/rhea-e2e/`. Most recent run:
- `40-empty.png` — centred empty state, "Drop a PDF, Markdown, or EPUB file"
- `41-settings-playback.png` — Voice picker + Speed/Pitch + Research toggles + Reset
- `42-settings-pronunciation.png` — Empty dictionary + Add-term inputs
- `43-settings-analytics.png` — Privacy toggle + "Analytics are off" empty state

## Fixture paths
Left alone as requested. If you replace files, the library sidebar
entries pointing at them stay pointed.

| Path | Size | Content |
| --- | --- | --- |
| `~/rhea-fixtures/short-english.md` | 112 B | H1 + paragraph + H2 + inline bold/italic/code |
| `~/rhea-fixtures/short-english.pdf` | 83 KB | "15-Week Plan for E-commerce Data Platform Project" |
| `~/rhea-fixtures/chinese.pdf` | 197 KB | Liu Cixin collection (Chinese) |
| `~/rhea-fixtures/chinese.md` | 19 KB | Liu Cixin collection (Chinese) |

## Commit trail this session
Ordered oldest → newest:
1. `fix: library click loads document; open -a Rhea routes file URLs`
2. `fix(tcc+library): path-based dedup avoids filesystem hits`
3. `feat: menu bar + pronunciation dictionary (M4.4, M4.6)`
4. `feat: research-PDF citation stripping + figure skipping (M3.5)`
5. `feat: local reading analytics (M4.5)`
6. `feat: audiobook export to .m4a via AVAudioFile (M4.1)`
7. `fix(build): embed any PackageFrameworks missing from the app bundle`
8. `fix(build): --run direct-execs instead of using LaunchServices`
9. `feat: EPUB support (M4.3)`

## Next steps I'd pick up when you wake me
In priority order:
1. **M2.6 Services menu + global hotkey** — NSServices registration + NSEvent monitor. Needs Info.plist surgery (custom plist file to get NSServices).
2. **Integration tests for SpeechPlayer routing** — we have logic-level coverage; a test that verifies kokoro:-prefixed voice id does NOT hit AVSpeechSynthesizer would close the loop.
3. **Stable signing identity** — kills the LaunchServices hang permanently, makes `open` work normally.
4. **M2.3 WhisperKit forced alignment** — so Kokoro also gets word-level highlight and pronunciation/citation-transformed text still highlights correctly.
5. **Chapter markers in exported m4a** — promote to proper `.m4b` with per-block chapter metadata.
6. **M3.1 Qwen3-TTS bilingual** — adds `swift-qwen3-tts` SwiftPM dep, another model entry in the catalog, engine routing by detected language per sentence.

## Test fixture requests (still optional)
Only needed if you want real-world content to show up in the
Peekaboo screenshots. Current synthetic/user-provided fixtures
are sufficient for automated E2E.

| Path | Purpose |
| --- | --- |
| `~/rhea-fixtures/long-english.md` | Scroll-perf test for large markdown |
| `~/rhea-fixtures/long-english.pdf` | 10+ page research PDF for extraction + highlight scale |
| `~/rhea-fixtures/mixed.md` | Paragraphs alternating EN + ZH for bilingual auto-switch |
| `~/rhea-fixtures/book.epub` | Any small EPUB for that reader path |
