<div align="center">

<img src="Resources/readaloudtts_v6c.png" alt="ReadAloudTTS" width="160" />

# ReadAloudTTS

**The local-first, bilingual TTS reader for macOS.**

Drop a PDF, Markdown, or EPUB. Hear it read aloud with studio-quality
on-device neural voices — in English, Chinese, or both. Your papers
never leave your Mac.

[![version](https://img.shields.io/badge/version-0.7.1-e8a033.svg?style=flat-square)](https://github.com/HarveyLijh/ReadAloudTTS/releases)
[![license](https://img.shields.io/badge/license-Apache%202.0-blue.svg?style=flat-square)](LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg?style=flat-square)](https://www.apple.com/macos/)
[![swift](https://img.shields.io/badge/swift-6.0-orange.svg?style=flat-square)](https://swift.org)
[![arch](https://img.shields.io/badge/arch-Apple%20Silicon-222222.svg?style=flat-square)](https://www.apple.com/mac/)

</div>

---

## Why ReadAloudTTS

The commercial TTS reader market is broken. Speechify ships a disliked
subscription. Voice Dream torched its user trust with the 2024 paywall
revolt. Every "AI reader" wants to upload your PDF to their servers.
Meanwhile the Chinese-language Mac academic market is **completely
unserved** — iFlytek has no Mac client, Speechify's Chinese voices are
an afterthought.

ReadAloudTTS is the counter. **Fully offline. Fully open source.
Apache-2.0, forever. No account, no subscription, no cloud.**

- **Bilingual by default** — EN + ZH auto-switch per sentence via
  on-device language detection. No other reader does this.
- **Neural voices locally** — Kokoro (English, 28 voices) and
  Qwen3-TTS (bilingual, 6 voices) run on your M-series chip via MLX.
- **Research-paper aware** — multi-column layouts, citation
  stripping, figure/table skipping, user-defined regex skip rules.
- **Word-level highlighting** — Whisper-based forced alignment
  paints the exact word being spoken, synchronized to audio.
- **Zero setup** — download the DMG, open it, drop a PDF. No Docker,
  no Python venv, no API keys, no onboarding.

## Screenshots

> _Hero screenshots land in v0.8.0 once the visual polish pass ships.
> For now, here's the shape of the app:_

A single reader window with the library sidebar on the left and the
document in the middle. A capsule transport HUD at the bottom carries
every playback control — skip, play, scrub, speed, voice, skip-rules,
settings — and collapses progressively on narrow windows. Right-click
any word: "Read from here."

## Install

### One-line download

Grab the latest `.dmg` from
[Releases](https://github.com/HarveyLijh/ReadAloudTTS/releases), mount it,
drag ReadAloudTTS into **/Applications**. First launch: right-click → **Open**
(Gatekeeper asks once; afterwards plain double-click works).

Or drop the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/ReadAloudTTS.app
```

### Homebrew

_Planned for v0.8.x once the release cadence stabilises._

### Build from source

```sh
git clone https://github.com/HarveyLijh/ReadAloudTTS.git
cd ReadAloudTTS
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
# edit Local.xcconfig to set DEVELOPMENT_TEAM if you have one
open ReadAloudTTS.xcodeproj
```

No Tuist, no XcodeGen, no code-gen step — the `.xcodeproj` is
hand-maintained. Xcode 16+, macOS 15 SDK, Swift 6 toolchain.
`Scripts/build.sh` runs without Xcode if all you have is the
Command Line Tools.

After building, `Scripts/run.sh` launches the last Debug build from
DerivedData (no more typing the long Xcode-hashed path).
`Scripts/run.sh --build` rebuilds first; `--release` opens the
Release bundle if you need to sanity-check distribution output.

## What's Inside

### 🎯 The transport HUD
Capsule at the bottom of the window with every playback control at
arm's length. Skip prev / play / skip next, sentence-granular
scrubber with live drag preview, time readout, skip-rules counter,
speed chip (0.5×–4.0×), voice chip (with engine-fallback icon),
settings gear. Progressively collapses on narrow windows: drops the
time, then voice label, then speed chip — transport and scrubber
are always visible.

### 📚 Three document formats
**PDF** via PDFKit, **Markdown** via Foundation's attributed-string
parser (preview + source views), **EPUB** via ZIPFoundation + your
XHTML chapters. Sentence segmentation uses `NLTokenizer`; UTF-16
offsets throughout, so click-to-start-from-word works natively.

### 🎙 Three voice engines
- **System** — any AVSpeechSynthesis voice on your Mac. Bilingual
  auto-switch on by default.
- **Kokoro** (650 MB download) — 28 studio-quality English voices
  via MLX on Apple Silicon.
- **Qwen3-TTS** (~1 GB download) — 6 bilingual EN+ZH speakers via
  TTSKit / WhisperKit. Downloaded on demand from Settings → Models.

Switch voices mid-read — ReadAloudTTS restarts the current sentence on the
new voice and flashes an undo toast with a 4-second timer. Neural
engine failed? The chip flips to a system-voice icon, a banner
appears for 2 seconds, and the stale event auto-clears so the chip
heals when the next synth succeeds.

### ✨ Highlighting
Soft amber wash on the active sentence; brighter sub-highlight on
the word currently being spoken (driven by AVSpeechSynthesizer's
`willSpeakRange` for system voices, or a Whisper forced-alignment
pass for neural). Auto-scroll follows the sentence — manual scroll
is honored (we only scroll on sentence change, never word-tick).

### 🎵 Audiobook export
File → Export Audiobook… (⌘⇧E). Format picker in the save panel —
**M4A** (AAC, universal) or **WAV** (uncompressed, for external
MP3 conversion or editing). A proper background queue (⌘⇧J to open)
tracks multiple jobs with per-row progress, Show in Finder, and
Play buttons.

### 🖱 Click-to-start-from-word
Double-click any word in any viewer to jump playback there.
Right-click for a contextual **Read from here** / **Read from here
to end** menu.

### ⏮ Resume position
Close mid-read, reopen — ReadAloudTTS restores the paused cursor at the
sentence you left off. Press space to continue.

### 🔇 Skip rules
Regex patterns stripped from speech before the synthesizer sees the
text. Ships with three enabled-by-default built-ins:

- Numeric citations: `[12]`, `[12, 13]`, `[12–15]`
- LaTeX: `\cite{…}`, `\citep{…}`, `\ref{…}`, `\label{…}`
- Inline cite markers: `cite:smith2019`

Add your own in **Settings → Skip Rules** with live preview on a
sample sentence. The HUD's `Skip: N` chip shows the active count at a
glance; toggling mid-read takes effect on the next sentence.

### 🌐 System integration
- **Services menu** — highlight text in any app, choose
  **Services → Read with ReadAloudTTS**.
- **Global hotkey** — ⌘⇧S reads your clipboard from anywhere.
- **MenuBarExtra** — transport controls in the menu bar while a
  document plays.
- **URL handlers** — `open -a ReadAloudTTS paper.pdf` and Finder
  double-click both route to the single existing reader window
  instead of spawning duplicates.

### 📖 Pronunciation dictionary
Your voice mispronounces a technical term? Add a pronunciation
override in **Settings → Pronunciation**. Applies to every engine.

### 📊 Reading stats
Local-only WPM tracking that feeds the transport's time estimates.
Opt-out in **Settings → Analytics**; nothing ever leaves the
device.

## Keyboard Shortcuts

| Key | Action |
| --- | --- |
| `Space` | Play / Pause |
| `←` / `→` | Previous / Next sentence |
| `⌘ ]` / `⌘ [` | Speed up / slow down (0.1 step) |
| `⌘ O` | Open File… |
| `⌘ ⇧ E` | Export Audiobook… |
| `⌘ ⇧ J` | Show Exports queue |
| `⌘ ⇧ S` | Read Clipboard (global, from any app) |
| `⌘ ⇧ R` | Read Clipboard (from the menubar item) |
| `⌘ ,` | Open Settings |

## Roadmap

Versioning tracks feature milestones — ReadAloudTTS is at **v0.7.1**: all
core reading, playback, and export flows work end-to-end on real
documents. What's left is polish, distribution, and the
nice-to-haves that turn a working reader into a product people
recommend.

### ✅ Shipped through v0.7.1

- Transport HUD with live voice/model switching, undo toast,
  engine-fallback transparency
- Click/double-click to start reading from any word (all 3 viewers)
- Word-level highlighting via `willSpeakRange` + Whisper alignment
- Sentence-granular scrubber with live drag preview
- Custom regex skip rules (3 built-ins + user-defined) + dedicated
  Settings tab with live preview
- Audiobook export queue — M4A / WAV with a proper Exports window
- Resume last reading position across relaunches
- Research-PDF cleanup (author-year citations, figure/table
  captions, multi-column layouts)
- Bilingual system + Kokoro + Qwen3-TTS engines with language
  auto-switch
- Services menu "Read with ReadAloudTTS" + global ⌘⇧S clipboard hotkey
- Pronunciation dictionary + local reading stats
- Sandboxed + hardened Release builds; unsigned DMG distribution
  path works without the paid Apple Developer Program

### 🚧 v0.8.x — Public-ready polish + the critical UX gaps

Closing the most-visible deltas vs. Voice Dream / NaturalReader while
the app walks to v1.

- **Document outline / chapter navigator** — sidebar that lists
  detected PDF outlines, EPUB chapters, and Markdown headings with
  click-to-jump
- **Bookmarks with notes** — name and save any number of positions
  per document (resume is one automatic bookmark; this adds manual
  ones), inline highlights on selected text, export to Markdown
- **Sleep timer** — auto-pause after N minutes or at end of the
  current chapter
- **Per-document voice + speed memory** — remember which voice and
  speed you used on each document so a dense paper opens at 1.0×
  and a novel at 1.6× without re-setting
- **Voice preview buttons** — ▶︎ on every row in the voice picker
  plays a sample sentence in that voice
- **Share Extension** — Safari / Preview / Notes → Share → "Read
  with ReadAloudTTS" without the global hotkey
- **MP3 export** — via a bundled LAME encoder (complements the
  existing M4A / WAV paths)
- **Per-document rule scopes** for skip patterns
- **Homebrew Cask** (`brew install --cask readaloudtts`)
- **Signed + notarised DMG** via GitHub Releases automation
- Hero screenshots, app icon through every Asset Catalog slot, DMG
  background art

### 🔮 v0.9.x — Beyond the baseline

- **Playback queue / listen-later library** — chain documents and
  chapters like an audiobook playlist; next item auto-plays on
  completion
- **Web / URL article import** — paste a URL or share from Safari;
  ReadAloudTTS fetches, strips chrome via Reader-mode extraction, and
  queues the body
- **OCR for image-only PDFs** — detect and re-run scanned pages
  through Apple's Vision framework so pre-2000 papers become
  readable
- **Continuous-listening folder / tag queues** — "listen through
  my 'unread papers' tag"
- **Shortcuts app integration** — `Read with ReadAloudTTS` action scriptable
  from Shortcuts and Automator
- **Spotlight-indexable library** — your library searchable from
  system Spotlight
- **Chapter markers in exported .m4b audiobooks**
- **Voice cloning** — Qwen3-TTS supports this upstream; bring your
  own reference audio

### 🌌 v1.0+ — The bigger bets

The features cloud competitors lean on for AI parity, re-implemented
fully on-device so ReadAloudTTS keeps its privacy wedge. All share a single
piece of infrastructure: a locally-hosted small LLM (MLX Qwen2.5-3B
or Llama-3.2-3B) running in the same process space as the TTS
engines.

- **Chat-with-PDF / document Q&A** — "Summarize Section 3"; "What
  does the author conclude?"; fully local retrieval over the active
  document
- **AI summaries + listening quizzes** — 10-bullet recap and 5-question
  comprehension check you can answer by ear
- **Dual-host podcast generation** — ElevenReader's GenFM, but
  on-device: ReadAloudTTS scripts a two-voice conversation about your PDF
  and exports it as an .m4b
- **Math-aware reading** — detect LaTeX / MathML in research PDFs
  and read equations as natural English ("the integral from zero
  to infinity of…") instead of skipping them
- **RSVP / speed-reading modes** — Voice Dream's signature one-word-at-a-time
  pacer, reused on top of ReadAloudTTS's Whisper word-level alignment
- **Figure caption-only mode** — read what the figures show, not
  the body
- **Web extension** for Chrome / Safari — read any page via ReadAloudTTS
- **iOS companion app** — sync the document queue across devices
  (CloudKit — end-to-end encrypted, stays out of ReadAloudTTS's servers
  because there are none)

_The roadmap keeps moving. Suggestions and priority feedback welcome
in [Issues](https://github.com/HarveyLijh/ReadAloudTTS/issues)._

## Tech Stack

- **UI** — SwiftUI, macOS 15 SDK, Swift 6 strict concurrency
- **TTS engines** — AVSpeechSynthesizer (system),
  [`kokoro-ios`](https://github.com/mlalma/kokoro-ios) via MLX
  (Kokoro), [`TTSKit`](https://github.com/argmaxinc/WhisperKit) via
  MLX (Qwen3-TTS)
- **Alignment** — WhisperKit forced alignment for word-level
  highlights under neural voices
- **PDF** — PDFKit
- **Markdown** — Foundation's `AttributedString(markdown:)`
- **EPUB** — ZIPFoundation + custom XHTML loader
- **Storage** — `UserDefaults` for settings, security-scoped
  bookmarks for the document library

## Project Conventions

- **Commits** — Conventional Commits (`feat:`, `fix:`, `perf:`,
  `refactor:`, `chore:`, `docs:`, `test:`). English, imperative
  mood, no `Co-Authored-By` trailers.
- **Branching** — trunk-based on `main`; feature branches when a
  change spans more than one commit.
- **Style** — Apple's Swift API Design Guidelines; no external
  linter rules.
- **Architecture** — ADRs live in [`docs/decisions.md`](docs/decisions.md).

## Contributing

ReadAloudTTS is pre-v1 and the feature surface is still moving. The fastest
way to contribute right now is by **using it on real documents** —
filing issues when it mispronounces, misreads columns, or drops
sentences on your particular PDFs gets the product to v1 faster
than any code PR. Reproduction PDFs make fixes tractable.

For code PRs, pick something from the **🚧 Next up** list above,
comment on the matching issue, and open a small PR. One milestone
per PR when possible.

## License

Apache 2.0. See [LICENSE](LICENSE). Bundled third-party components
keep their own licenses; see [NOTICE](NOTICE).

## Releasing

Releases are built and published by GitHub Actions
(`.github/workflows/release.yml`). Pushing an annotated semver tag
fires the workflow, which runs `Scripts/package.sh` on a macOS arm64
runner, attaches the resulting `.dmg` + `.sha256` to a new GitHub
Release, and generates notes from the commit log since the previous
tag.

```sh
# 1. Bump MARKETING_VERSION in Configs/ReadAloudTTS.xcconfig (or wherever the
#    Info.plist's CFBundleShortVersionString is set) to match the tag.
# 2. Commit the bump, then:
git tag v0.8.0
git push origin v0.8.0          # or: git push --tags
```

- The tag name becomes the Release title. Tags containing `-`
  (e.g. `v0.8.0-rc1`) are auto-marked as **pre-release**.
- **Signing is optional.** Without the signing secrets the workflow
  still ships an unsigned DMG and the release notes include the
  standard first-launch right-click → **Open** instructions.
- To sign + notarise, add these Actions secrets under
  Settings → Secrets and variables → Actions:
  `APPLE_TEAM_ID`, `DEVELOPER_ID_APPLICATION`, `NOTARY_APPLE_ID`,
  `NOTARY_PASSWORD`, `BUILD_CERTIFICATE_BASE64` (base64-encoded
  Developer ID `.p12`), `BUILD_CERTIFICATE_PASSWORD`,
  `KEYCHAIN_PASSWORD`.
- **Dry run**: the workflow also supports `workflow_dispatch`
  (Actions → Release → *Run workflow*). That path uploads the DMG as
  a workflow **artifact** instead of publishing a Release — useful
  for smoke-testing the pipeline before committing to a public
  version number.
- **First build** takes ~15–25 min (cold SPM cache). Subsequent
  builds reuse `~/Library/Developer/Xcode/DerivedData/**/SourcePackages`
  via `actions/cache@v4`.

If something goes wrong after publishing, delete the tag + release to
retry:

```sh
git push origin :refs/tags/v0.8.0   # delete remote tag
git tag -d v0.8.0                   # delete local tag
# delete the Release in the GitHub UI, or:
gh release delete v0.8.0 --yes
```

---

<div align="center">

Made on an M-series Mac · No cloud, no account, no subscription, ever.

</div>
