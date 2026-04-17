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
| ⌘⇧S | Read Clipboard (global, works from any app) |
| ⌘, | Open Settings |

Services menu: any app's *Services → Read with Rhea* reads the current
selection aloud. Shortcut is user-configurable in System Settings →
Keyboard → Keyboard Shortcuts → Services.

## Milestone coverage

### Month 1 — complete
M1.1 skeleton · M1.2 PDF rendering · M1.3 PDFKit extraction ·
M1.4 sentence segmenter (NLTokenizer, EN+ZH) · M1.5 playback
(system voice, speed/pitch) · M1.6 sentence-level amber
highlight · M1.7 library sidebar with UserDefaults-backed
security-scoped bookmarks.

### Month 2 — complete
- M2.1 ✅ Kokoro on-device English TTS, downloadable model, voice picker
- M2.2 ✅ Neural-TTS prefetch-next-sentence (zero gap on sentence advance; Kokoro + Qwen)
- M2.3 ✅ WhisperKit forced alignment drives word-level highlight on Kokoro + Qwen paths
- M2.4 ✅ Word-level highlight via `willSpeakRange` (system voices)
- M2.5 ✅ Settings tabs, speed/pitch sliders, voice override
- M2.6 ✅ Services menu "Read with Rhea" + ⌘⇧S global hotkey (Carbon)
- M2.7 ✅ Markdown renderer with Preview/Source toggle, proper block separators

### Month 3 — mostly
- M3.1 ✅ Qwen3-TTS 0.6B bilingual engine via argmaxinc/WhisperKit TTSKit
- M3.2 ✅ Per-sentence language detection routes EN/ZH through Qwen's bilingual path
- M3.3 ✅ Prefetch-next-sentence parity for Qwen (reuses the M2.2 cache)
- M3.4 ✅ Voice picker + Settings footer surfaces Qwen when downloaded
- M3.5 ✅ Research-PDF heuristics (inline citation + figure/table caption stripping)
- M3.6 ✅ Scripts/package.sh builds signed .dmg (Developer-ID optional)
- M3.7 ⏳ Marketing site / Homebrew Cask — needs a hosted DMG URL

### Month 4 — mostly
- M4.1 ✅ Audiobook export (`.m4a`, all three engine paths: system / Kokoro / Qwen)
- M4.3 ✅ EPUB support (ZIPFoundation + NSAttributedString HTML render)
- M4.4 ✅ Menu-bar item, Read Clipboard
- M4.5 ✅ Local reading analytics (opt-in)
- M4.6 ✅ Pronunciation dictionary
- M4.2 ⏳ Voice cloning — blocked: no audio-reference voice-clone model with a Swift/MLX port ships today

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
signature when the bundle lives under `~/Documents`. Direct-exec
sidesteps it entirely — the stall only bites the `open` /
double-click path, which users of a released DMG won't hit
(they install to `/Applications`).

## Peekaboo E2E screenshots
Under `/tmp/rhea-e2e/`:
- `40-empty.png` / `99-final-state.png` — centred empty state
- `41-settings-playback.png` — Voice picker, speed/pitch, research toggles
- `42-settings-pronunciation.png` — dictionary empty state + add form
- `43-settings-analytics.png` — privacy toggle + off state
- `100-m26-m22-live*` — post-M2.2/M2.6 empty state smoke
- `101-qwen-whisper-live*` — post-M2.3/M3.1 empty state smoke
- `102-settings-qwen-whisper*` — Playback tab showing Qwen-aware footer
- `103-models-tab-qwen-whisper*` — Models tab with Kokoro / Qwen / Whisper entries

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
1. **Chapter markers (m4a → m4b)** — rewrite `AudioExporter` on `AVAssetWriter` with a chapter text-track that fires at each `DocumentBlock` boundary. Current export is one continuous AAC track.
2. **Streaming Whisper alignment** — today the aligner awaits the full transcription for each sentence before scheduling word highlights. Fine for ~3-5s Kokoro/Qwen clips, but on long sentences the first word lags the audio. Switch to the streaming `TranscriptionStream` in WhisperKit 0.18 so highlights start as soon as the first word is decoded.
3. **M3.7 Homebrew Cask tap** — point it at a GitHub-hosted unsigned DMG (shipping unsigned is fine for OSS; the README + release notes tell users how to right-click → Open on first run). Paid Developer-ID signing is optional polish, not a blocker.
4. **M4.2 voice cloning** — revisit once a Swift/MLX port of a modern voice-clone model (OpenVoice-v2, XTTS-v3) exists. Until then the Qwen speaker zoo is the ceiling.
5. **Integration test for bilingual playback** — live playback isn't tested end-to-end; needs a Peekaboo session that loads `chinese.md`, picks a Qwen voice, and confirms highlight advances. Requires the 1 GB Qwen model to be pre-downloaded on the CI machine.

Sleep well. Coffee works on me too.
