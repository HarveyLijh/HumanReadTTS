<img src="Resources/humanreadtts_v6c.png" alt="HumanReadTTS" width="120" />

# HumanReadTTS

**The local-first, bilingual TTS reader for macOS.**

Drop in a PDF, Word file, EPUB or Markdown document and hear it read aloud with
on-device neural voices, in English, Chinese, or both. Your papers never leave
your Mac.

[![version](https://img.shields.io/badge/version-0.7.2-e8a033.svg?style=flat-square)](https://github.com/HarveyLijh/HumanReadTTS/releases)
[![license](https://img.shields.io/badge/license-Apache%202.0-blue.svg?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg?style=flat-square)](https://www.apple.com/macos/)
[![swift](https://img.shields.io/badge/swift-6.0-orange.svg?style=flat-square)](https://swift.org)
[![arch](https://img.shields.io/badge/arch-Apple%20Silicon-222222.svg?style=flat-square)](https://www.apple.com/mac/)

**[Download](https://github.com/HarveyLijh/HumanReadTTS/releases/latest)** &middot;
**[Website](https://harveylijh.github.io/HumanReadTTS/)** &middot;
**[User manual](https://harveylijh.github.io/HumanReadTTS/docs/manual/)**

> Not a developer? The [user manual](https://harveylijh.github.io/HumanReadTTS/docs/manual/)
> walks through installing and using the app with screenshots and no jargon.
> This README is for people working on the code.

---

## Why

The commercial TTS reader market is broken. Speechify ships a disliked
subscription. Voice Dream torched its user trust with the 2024 paywall revolt.
Every "AI reader" wants to upload your PDF to their servers. Meanwhile the
Chinese-language Mac academic market is completely unserved: iFlytek has no Mac
client, and Speechify's Chinese voices are an afterthought.

HumanReadTTS is the counter. Fully offline, fully open source, Apache-2.0
forever. No account, no subscription, no cloud.

- **Bilingual by default.** EN and ZH auto-switch per sentence via on-device
  language detection. No other reader does this.
- **Neural voices locally.** Kokoro (English, 28 voices) and Qwen3-TTS
  (bilingual, 6 voices) run on your M-series chip via MLX.
- **Research-paper aware.** Multi-column layouts, citation stripping,
  figure/table skipping, user-defined regex skip rules.
- **Word-level highlighting.** Whisper-based forced alignment paints the exact
  word being spoken, synchronised to audio.
- **Zero setup.** Download the DMG, open it, drop in a PDF. No Docker, no Python
  venv, no API keys.

## Install

Grab the latest `.dmg` from
[Releases](https://github.com/HarveyLijh/HumanReadTTS/releases/latest), mount it,
and drag HumanReadTTS into **/Applications**. On first launch, right-click the
app and choose **Open** (Gatekeeper asks once; afterwards a plain double-click
works).

If Gatekeeper refuses outright, drop the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/HumanReadTTS.app
```

Homebrew is planned for v0.8.x once the release cadence stabilises.

## Build from source

```sh
git clone https://github.com/HarveyLijh/HumanReadTTS.git
cd HumanReadTTS
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
# edit Local.xcconfig to set DEVELOPMENT_TEAM if you have one
open HumanReadTTS.xcodeproj
```

No Tuist, no XcodeGen, no code-gen step; the `.xcodeproj` is hand-maintained.
Requires Xcode 16+, the macOS 15 SDK, and a Swift 6 toolchain.

`Scripts/build.sh` has a fallback that compiles with `swiftc` when full Xcode is
missing, but it cannot resolve the Swift Package dependencies on its own, so it
only works once Xcode has populated `build/` with matching module versions. It
also deletes the existing app bundle before compiling, so a failed run leaves
you with no app.

After building, `Scripts/run.sh` launches the last Debug build from DerivedData.
`Scripts/run.sh --build` rebuilds first; `--release` opens the Release bundle.

## What's inside

### The transport HUD
A capsule at the bottom of the window with every playback control: skip
previous / play / skip next, a sentence-granular scrubber with live drag
preview, time readout, skip-rules counter, speed chip (0.5x to 4.0x), voice chip
with engine-fallback icon, and a settings gear. It collapses progressively on
narrow windows, dropping the time, then the voice label, then the speed chip.
Transport and scrubber stay visible.

### Six document formats
**PDF** via PDFKit, **Markdown** via Foundation's attributed-string parser
(preview and source views), **EPUB** via ZIPFoundation plus a custom XHTML
loader, **DOCX** via a built-in OOXML reader, **plain text**, and **images**
(PNG, JPG, HEIC, TIFF) read through on-device OCR. Sentence segmentation uses
`NLTokenizer`, with UTF-16 offsets throughout so click-to-start-from-word works
natively.

### Three voice engines
- **System** — any AVSpeechSynthesis voice on the Mac. Bilingual auto-switch on
  by default.
- **Kokoro** (650 MB download) — 28 English voices via MLX on Apple Silicon.
- **Qwen3-TTS** (~1 GB download) — 6 bilingual EN+ZH speakers via TTSKit and
  WhisperKit. Downloaded on demand from Settings, Models tab.

Voices switch mid-read: the app restarts the current sentence on the new voice
and flashes an undo toast with a 4-second timer. If a neural engine fails, the
chip flips to a system-voice icon, a banner appears for 2 seconds, and the stale
event auto-clears so the chip heals on the next successful synth.

### Highlighting
A soft amber wash on the active sentence, with a brighter sub-highlight on the
word being spoken, driven by `willSpeakRange` for system voices or a Whisper
forced-alignment pass for neural ones. Auto-scroll follows the sentence; manual
scroll is honoured, and a jump-to-current button returns you to the read
position.

### Reading comfort and accessibility
**Settings, Reading tab**, with live previews. Body typeface (serif, system,
sans, monospaced, or the bundled OpenDyslexic and Atkinson Hyperlegible), plus
size, line spacing and letter spacing. Optional leading-bold ("bionic") reading.
A colour-blind-aware highlight palette. Two reading surfaces beyond System,
Sepia and Night, plus a line-focus reading ruler that dims everything except the
line under the pointer.

### Bilingual study tools
Option-double-click (or right-click, Translate) any word to open a translator:
on-device Apple Translation into the target language, spoken playback, and
save-to-vocabulary with the surrounding sentence as context. **Settings,
Learning tab** lists saved words and exports them to Anki as CSV with Front,
Back, Context and a language tag. Defaults are tuned for English and Simplified
Chinese.

### On-device OCR
Open an **image** and the text is recognised on-device with Vision, in proper
reading order so multi-column and title-over-body layouts do not zig-zag, then
read like any other document. Recognition languages are configurable in
**Settings, Shortcuts tab**.

### System integration
- **Services menu** — highlight text in any app, choose **Services, Read with
  HumanReadTTS**.
- **Global hotkey** — `⌘⇧E` reads the selection in any app, falling back to the
  clipboard. Rebindable in Settings.
- **MenuBarExtra** — transport controls in the menu bar while a document plays,
  plus Read Selection.
- **URL handlers** — `open -a HumanReadTTS paper.pdf` and Finder double-click
  both route to the single existing reader window instead of spawning
  duplicates.

### Now Playing, sleep timer and reading queue
Reads publish to Control Center and the Now Playing widget, and the hardware
media keys (F7/F8/F9) plus AirPods controls drive playback. A sleep timer
auto-pauses after a set number of minutes or at the end of the current sentence,
and a reading queue chains items with auto-advance. All in **Settings, Playback
Controls tab**.

### Skip rules
Regex patterns stripped from speech before the synthesiser sees the text. Three
built-ins ship enabled: numeric citations (`[12]`, `[12, 13]`, `[12-15]`), LaTeX
residue (`\cite{}`, `\citep{}`, `\ref{}`, `\label{}`), and inline cite markers
(`cite:smith2019`). Add your own in **Settings, Skip Rules tab** with live
preview. The HUD's `Skip: N` chip shows the active count; toggling mid-read
takes effect on the next sentence.

### Audiobook export
File, Export Audiobook (`⌘⇧E`). The save panel offers **M4A** (AAC, universal)
or **WAV** (uncompressed). A background queue (`⌘⇧J`) tracks multiple jobs with
per-row progress, Show in Finder, and Play buttons.

### Pronunciation dictionary and reading stats
Pronunciation overrides in **Settings, Pronunciation tab** apply to every
engine. Local-only WPM tracking feeds the transport's time estimates; opt out in
**Settings, Analytics tab**. Nothing leaves the device.

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `Space` | Play / pause |
| `←` / `→` | Previous / next sentence |
| `⌘ ]` / `⌘ [` | Speed up / slow down (0.1 step) |
| `⌘ O` | Open file |
| `⌘ F` | Find in document |
| `⌘ G` / `⌘ ⇧ G` | Next / previous match |
| `⌘ +` / `⌘ -` / `⌘ 0` | Zoom in / out / reset |
| `Esc Esc` | Fit page to window |
| `⌘ ⇧ E` | Export audiobook |
| `⌘ ⇧ J` | Show exports queue |
| `⌘ ,` | Open Settings |

Global, fires from any app, rebindable in **Settings, Shortcuts tab**:

| Key | Action |
| --- | --- |
| `⌘ ⇧ E` | Read the selection in the frontmost app (falls back to the clipboard) |

## Roadmap

Versioning tracks feature milestones. HumanReadTTS is at **v0.7.2**: all core
reading, playback and export flows work end-to-end on real documents. What is
left is polish, distribution, and the nice-to-haves that turn a working reader
into a product people recommend.

### Shipped through v0.7.2

- Transport HUD with live voice/model switching, undo toast, engine-fallback
  transparency
- Click and double-click to start reading from any word, in all viewers
- Word-level highlighting via `willSpeakRange` and Whisper alignment
- Sentence-granular scrubber with live drag preview
- Custom regex skip rules (3 built-ins plus user-defined) with a dedicated
  Settings tab and live preview
- Audiobook export queue, M4A and WAV, with an Exports window
- Resume last reading position across relaunches
- Research-PDF cleanup: author-year citations, figure and table captions,
  multi-column layouts
- Bilingual system, Kokoro and Qwen3-TTS engines with language auto-switch
- Services menu integration and a global read-selection hotkey
- Pronunciation dictionary and local reading stats
- Reading comfort: typeface picker with bundled OpenDyslexic and Atkinson
  Hyperlegible, size / line / letter spacing, leading-bold reading,
  colour-blind-aware highlight palette
- Reading themes: Sepia and Night surfaces, plus a line-focus reading ruler
- Tap-to-translate with on-device translation, pronunciation and
  save-to-vocabulary
- Vocabulary list with Anki CSV export
- On-device OCR for image documents, with configurable languages
- Now Playing, media keys, sleep timer and reading queue
- DOCX and plain-text reading
- Persistent per-document PDF zoom, double-tap Esc to fit, in-file search
- Line reflow that rejoins wrapped lines into whole sentences

### v0.8.x, public-ready polish

Closing the most visible gaps against Voice Dream and NaturalReader.

- **Document outline / chapter navigator** — a sidebar listing detected PDF
  outlines, EPUB chapters and Markdown headings, with click-to-jump
- **Bookmarks with notes** — name and save any number of positions per document,
  inline highlights on selected text, export to Markdown
- **Per-document voice and speed memory** — so a dense paper opens at 1.0x and a
  novel at 1.6x without re-setting
- **Voice preview buttons** — play a sample sentence from every row in the voice
  picker
- **Share Extension** — Safari, Preview and Notes share sheet, without the
  global hotkey
- **MP3 export** via a bundled LAME encoder
- **Per-document rule scopes** for skip patterns
- **Homebrew Cask**
- **Signed and notarised DMG** via GitHub Releases automation
- Hero screenshots, app icon in every Asset Catalog slot, DMG background art

### v0.9.x, beyond the baseline

- **Playback queue / listen-later library** — chain documents and chapters like
  an audiobook playlist
- **Web and URL article import** — paste a URL or share from Safari; the app
  fetches, strips chrome via Reader-mode extraction, and queues the body
- **OCR for image-only PDFs** — detect and re-run scanned pages through Vision so
  pre-2000 papers become readable
- **Continuous-listening folder and tag queues**
- **Shortcuts app integration**, scriptable from Shortcuts and Automator
- **Spotlight-indexable library**
- **Chapter markers in exported .m4b audiobooks**
- **Voice cloning** — Qwen3-TTS supports this upstream; bring your own reference
  audio

### v1.0+, the bigger bets

The features cloud competitors lean on for AI parity, re-implemented fully
on-device so HumanReadTTS keeps its privacy wedge. All share one piece of
infrastructure: a locally-hosted small LLM (MLX Qwen2.5-3B or Llama-3.2-3B)
running in the same process space as the TTS engines.

- **Chat-with-PDF / document Q&A** — fully local retrieval over the active
  document
- **AI summaries and listening quizzes** — a 10-bullet recap and a 5-question
  comprehension check you can answer by ear
- **Dual-host podcast generation** — a two-voice conversation about your PDF,
  exported as .m4b
- **Math-aware reading** — detect LaTeX and MathML and read equations as natural
  English instead of skipping them
- **RSVP / speed-reading modes** on top of the Whisper word-level alignment
- **Figure caption-only mode**
- **Web extension** for Chrome and Safari
- **iOS companion app** — sync the document queue across devices via CloudKit

The roadmap keeps moving. Suggestions and priority feedback are welcome in
[Issues](https://github.com/HarveyLijh/HumanReadTTS/issues).

## Tech stack

- **UI** — SwiftUI, macOS 15 SDK, Swift 6 strict concurrency
- **TTS engines** — AVSpeechSynthesizer (system),
  [`kokoro-ios`](https://github.com/mlalma/kokoro-ios) via MLX,
  [`TTSKit`](https://github.com/argmaxinc/WhisperKit) via MLX (Qwen3-TTS)
- **Alignment** — WhisperKit forced alignment for word-level highlights under
  neural voices
- **PDF** — PDFKit
- **Markdown** — Foundation's `AttributedString(markdown:)`
- **EPUB** — ZIPFoundation plus a custom XHTML loader
- **OCR and translation** — Vision and Apple Translation, both on-device
- **Storage** — `UserDefaults` for settings, security-scoped bookmarks for the
  document library

## Documentation

- [`index.html`](index.html) — the landing page published at
  [harveylijh.github.io/HumanReadTTS](https://harveylijh.github.io/HumanReadTTS/)
- [`docs/manual/index.html`](docs/manual/index.html) — the end-user manual
- [`docs/decisions.md`](docs/decisions.md) — architecture decision records
- [`docs/MILESTONES.md`](docs/MILESTONES.md) — milestone tracking

The site is served by GitHub Pages from the `main` branch root. A `.nojekyll`
file disables Jekyll so the HTML is published verbatim.

## Project conventions

- **Commits** — Conventional Commits (`feat:`, `fix:`, `perf:`, `refactor:`,
  `chore:`, `docs:`, `test:`). English, imperative mood, no `Co-Authored-By`
  trailers.
- **Branching** — trunk-based on `main`; feature branches when a change spans
  more than one commit.
- **Style** — Apple's Swift API Design Guidelines; no external linter rules.
- **Architecture** — ADRs live in [`docs/decisions.md`](docs/decisions.md).

## Contributing

HumanReadTTS is pre-v1 and the feature surface is still moving. The fastest way
to contribute right now is by **using it on real documents**: filing issues when
it mispronounces, misreads columns, or drops sentences on your particular PDFs
gets the product to v1 faster than any code PR. Reproduction PDFs make fixes
tractable.

For code PRs, pick something from the v0.8.x list above, comment on the matching
issue, and open a small PR. One milestone per PR where possible.

## License

Apache 2.0. See [LICENSE](LICENSE). Bundled third-party components keep their own
licenses; see [NOTICE](NOTICE).

## Releasing

Releases are built and published by GitHub Actions
(`.github/workflows/release.yml`). Pushing an annotated semver tag fires the
workflow, which runs `Scripts/package.sh` on a macOS arm64 runner, attaches the
resulting `.dmg` and `.sha256` to a new GitHub Release, and generates notes from
the commit log since the previous tag.

```sh
# 1. Bump MARKETING_VERSION in Configs/HumanReadTTS.xcconfig to match the tag.
# 2. Commit the bump, then:
git tag v0.8.0
git push origin v0.8.0          # or: git push --tags
```

- The tag name becomes the Release title. Tags containing `-` (for example
  `v0.8.0-rc1`) are auto-marked as pre-release.
- **Signing is optional.** Without the signing secrets the workflow still ships
  an unsigned DMG, and the release notes include the first-launch right-click
  and Open instructions.
- To sign and notarise, add these Actions secrets under Settings, Secrets and
  variables, Actions: `APPLE_TEAM_ID`, `DEVELOPER_ID_APPLICATION`,
  `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`, `BUILD_CERTIFICATE_BASE64`
  (base64-encoded Developer ID `.p12`), `BUILD_CERTIFICATE_PASSWORD`,
  `KEYCHAIN_PASSWORD`.
- **Dry run**: the workflow supports `workflow_dispatch` (Actions, Release, Run
  workflow). That path uploads the DMG as a workflow artifact instead of
  publishing a Release, which is useful for smoke-testing the pipeline before
  committing to a public version number.
- **First build** takes 15 to 25 minutes on a cold SPM cache. Later builds reuse
  `~/Library/Developer/Xcode/DerivedData/**/SourcePackages` via
  `actions/cache@v4`.

If something goes wrong after publishing, delete the tag and release to retry:

```sh
git push origin :refs/tags/v0.8.0   # delete remote tag
git tag -d v0.8.0                   # delete local tag
gh release delete v0.8.0 --yes
```

---

Made on an M-series Mac. No cloud, no account, no subscription, ever.
