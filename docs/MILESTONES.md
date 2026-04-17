# Rhea — Milestone Plan & Technical Spec

> *Rhea* — Greek titaness, "mother of voices." Short, pronounceable in English and Chinese (瑞雅, ruì yǎ — "auspicious / elegant"), distinct from any existing TTS app, and sits cleanly alongside *Hearba*.

---

## 0. Context & thesis

**One-line pitch:** *Rhea is a local-first, bilingual (English + Chinese) Speechify for Apple Silicon. It reads your PDFs and Markdown aloud with studio-quality neural voices — and your papers never leave your Mac.*

**Positioning (from the market research):**

- The bilingual × offline × Apple-Silicon-native × research-paper-aware intersection is **completely unclaimed** as of April 2026.
- Qwen3-TTS opened-sourced 22 Jan 2026 (Apache-2.0); `AtomGradient/swift-qwen3-tts` already ships a native MLX Swift package for macOS 15+. The hardest risk is already de-risked.
- Speechify is the disliked incumbent (Spotsaas 2.2/5 across 1,353 reviews, BBB "F"); Voice Dream damaged itself with the 2024 subscription revolt; Zotero 9 Read Aloud (shipped 13 Apr 2026) is cloud-dependent and English-focused.
- iFlytek 有声 — the Chinese consumer gold standard — **has no Mac client**. The Chinese Mac academic market is effectively unserved.

**What makes this not "yet another TTS reader":**

1. **Seamless inline EN/ZH auto-switch.** No other app does this. Paste a paper with a Chinese abstract and English body, hit play, both voices sound great.
2. **Fully offline, zero setup.** Download .dmg → open → works. No Docker, no Python venv, no API key. Direct counter-positioning against Speechify's "we need access to your Google Drive."
3. **Research-paper aware.** Multi-column layouts, footnote/citation stripping, equation-as-prose, figure-caption-only reading — solved via Marker (or MinerU for Chinese scientific documents).
4. **Word-level highlighted synchronized scroll.** The Speechify interaction UX, but on a layout-preserving PDF view (not reflow).
5. **Native macOS citizenship.** Share Sheet, Shortcuts, system-wide hotkey, Spotlight, menu-bar playback control, m4b audiobook export with chapter markers.

**License & distribution strategy (fully open source):**

- **Apache-2.0**, end to end. The whole app, not just the Swift package building blocks. Source lives at `github.com/harveylijh/rhea`.
- **Distribution: notarized Developer-ID `.dmg` via GitHub Releases**, plus a Homebrew Cask once the release cadence stabilizes. **No Mac App Store submission**, at least for v1. The comparable unfunded-solo / small-team Mac apps in this segment ship outside MAS — Ollama, LM Studio, MacWhisper, Raycast, Rectangle, Stats, Transmission, VLC. Rationale and trade-offs are recorded in [`docs/decisions.md` ADR-001](../docs/decisions.md).
- **Funding (if/when traction warrants): GitHub Sponsors.** No subscription, no Pro unlock, no in-app purchase. Ever. This is the explicit counter-position against Speechify, Voice Dream, and the broader SaaS-ification of reading tools.
- **Practical knock-on effects** of dropping MAS: no embedded-Python sandbox gymnastics, no GPL-in-bundle worry (Apache-2.0 + GPL subprocess in a separate process is fine under the standard "mere aggregation" reading), no 30% Apple cut, no MAS review latency, full `CGEventTap`-based global hotkey on the table.

> **Downstream sections that still reference MAS-era assumptions (M3.7, §5 risk row "MAS review rejects embedded Python," §8 open question 1) are pending revision and will be updated in a follow-up pass.**

---

## 1. Design guideline (the "Rhea look")

### Visual identity

- **Core metaphor:** *a single beam of light that follows the voice.* The spoken word/sentence glows softly. Nothing else moves. The PDF is respected as a document, not reflowed.
- **Palette:**
  - Base: warm-neutral, system-adaptive. Light mode `#FAF9F6` (paper white). Dark mode `#17171A` (near-black, not pure).
  - Accent: a single warm-amber `#E8A033` (the "glow"). One color for the entire app. Used only for the active highlight, the play button, and focus states.
  - Text: `.primary` / `.secondary` semantic colors (respect accessibility).
  - **Never** use blue Electron-style accents. Never gradient buttons. Never drop shadows on cards.
- **Typography:**
  - UI: **SF Pro** (Apple system, everywhere). Never Inter, never Roboto.
  - Document reader: **New York** (serif) for prose, SF Pro Text for Markdown. **PingFang SC** for Chinese (system default on macOS — excellent quality).
  - Monospace: **SF Mono** for code blocks in Markdown.
- **Iconography:** **SF Symbols 6 only.** No custom icon library (Phosphor, Lucide, etc.). This is a deliberate constraint — it forces visual consistency with the OS and eliminates a category of design debt.
- **Motion:** springy but restrained. 0.25s ease-out for most transitions. The highlight tracker uses a 0.15s linear interpolation between word positions (not spring — spring looks jittery at word cadence).

### Interaction principles

1. **One primary action visible at a time.** The play button is the center of gravity. Everything else fades into the chrome.
2. **The document is the app.** The PDF/Markdown view occupies 80%+ of the window. Settings, library, voice picker are panels, not siblings.
3. **Keyboard-first.** Space = play/pause. ← → = prev/next sentence. ⇧← ⇧→ = prev/next paragraph. J/K = seek ±15s. ⌘⇧L = toggle library. ⌘, = settings. ⌘⇧S = read selection (system-wide, even from other apps).
4. **Progressive disclosure.** First launch shows exactly three things: "Open a PDF," "Paste text," "Open library." No onboarding carousel. No AI preview. Advanced features (voice cloning, figure description, custom dictionaries) live in Settings → Advanced.
5. **Never steal focus for notifications.** Processing a PDF happens in the background; the UI stays interactive.
6. **Respect the system.** Pointer-over scrollbars, trackpad gestures, native context menus, `NSHapticFeedbackManager` on important actions (play, chapter boundaries).

### Reference points (what to steal from)

- **Play/pause ergonomics:** Overcast, Castro 3.
- **Library view density:** Reeder 5, NetNewsWire.
- **PDF reading layout:** Highlights (by PSPDFKit team), Skim.
- **Settings information architecture:** Ivory, Tapbots apps.
- **Onboarding restraint:** MacWhisper (1 screen, "drop a file").
- **What NOT to look like:** Speechify (over-branded), ElevenReader (gamified purple), Voice Dream (skeuomorphic), any Electron reader.

---

## 2. Tech stack

| Layer | Choice | Why |
|---|---|---|
| Language | **Swift 6** | Native, Apple-Silicon-first, concurrency model fits audio streaming |
| UI | **SwiftUI** (primary) + **AppKit** (escape hatches for PDFKit interop, status bar, hotkeys) | SwiftUI is production-ready for macOS 14+; AppKit where needed |
| Target OS | **macOS 15 Sequoia minimum** | Required for `swift-qwen3-tts`; covers >85% of Apple Silicon installed base |
| PDF engine | **PDFKit** (view/selection) + **Marker** (parsing, subprocess) | PDFKit for native scroll/highlight; Marker for structured extraction |
| Markdown engine | **swift-markdown** (Apple's) + **Down** (GFM rendering) | Native, no JS runtime, no webview |
| TTS — English | **Kokoro-82M via `mlalma/kokoro-ios`** (MLX Swift) | #1 open-weights TTS arena, fast on M-series, 82M params |
| TTS — Chinese | **Qwen3-TTS via `AtomGradient/swift-qwen3-tts`** (MLX Swift) | SOTA open Mandarin, 10 dialects, Apache-2.0, native Swift port exists |
| TTS — fallback | **AVSpeechSynthesizer** (Apple system voices) | Day-one shipping when models aren't downloaded yet |
| Word alignment | **WhisperKit forced alignment** (reuse from Hearba) | Already in-house; word-level timestamps from generated audio |
| Language detection | **NSLinguisticTagger** (CoreML `NLLanguageRecognizer`) | Zero-dep, offline, per-paragraph zh/en detection |
| Audio engine | **AVAudioEngine** + **AVAudioPlayerNode** scheduling | Precise scheduling for seamless voice switching mid-stream |
| Persistence | **SwiftData** (library, positions, settings) + **file-backed** document store | SwiftData for metadata, files stay where the user put them |
| Sync (optional, Phase 3) | **CloudKit** (last-read position, library only) | First-party, no server cost, opt-in |
| m4b export | **AVAssetWriter** with chapter markers | Native, no ffmpeg dependency |
| Zotero integration | **Zotero local Web API** (`localhost:23119`) + direct SQLite read as fallback | Same approach as BetterBibTeX; works offline |
| Distribution | **Mac App Store** (primary) + **developer-ID .dmg** (secondary, for direct sales / pre-release) | Sandboxing for trust; non-MAS build for users who want library sync outside sandbox |
| Model delivery | **Hugging Face `hf-downloader`** on first launch, cached in `~/Library/Application Support/Rhea/models/` | Standard pattern; transparent; progress UI; resumable |
| Telemetry | **None.** No analytics SDK. Crash reporting via Apple's built-in only. | Positioning is "your data never leaves your Mac"; telemetry would be a reputation-bomb |

**Embedded helpers (subprocess, signed together):**
- `rhea-marker-helper` — Python 3.12 venv, bundled, runs Marker for PDF → structured Markdown. 300MB but one-time. Alternative: MinerU for Chinese-heavy PDFs (user toggle in Settings).
- `rhea-align-helper` — WhisperKit forced aligner (Swift, already in-house).

**Model sizes (user-visible):**
- Kokoro-82M MLX bf16: ~165 MB
- Qwen3-TTS 0.6B CustomVoice bf16: ~1.2 GB (default)
- Qwen3-TTS 1.7B VoiceDesign bf16: ~3.4 GB (optional, higher quality)
- CosyVoice 3 Instruct: ~1.0 GB (optional, alternative Chinese engine)
- Total first-run download at defaults: **~1.4 GB**

---

## 3. User interaction flows

### Flow A — First launch (the 60-second wow)

1. User double-clicks `Rhea.app` → opens directly to a single-window "Drop a PDF or Markdown file here" (MacWhisper-style).
2. Sidebar collapsed. No modal dialog. Status bar icon appears.
3. User drops a PDF. Rhea parses it (spinner on the sidebar entry; the rest of the UI stays live). For a 10-page paper, parsing completes in 3–8 seconds.
4. Document opens in the reader. Play button pulses gently.
5. User presses Space. First sentence highlights, audio plays from Apple system voice (zero-download default).
6. A small non-blocking banner appears: *"Get studio-quality voices (1.4 GB) · Download · Maybe later."*
7. If user clicks Download: progress in the banner, UI stays fully functional using system voices in the meantime. Switchover on next sentence boundary when the download completes.

### Flow B — Reading a bilingual paper

1. User opens a PDF with a Chinese abstract and English body.
2. Marker returns structured text with paragraph boundaries.
3. Rhea's language detector tags each paragraph `en` or `zh`.
4. Playback pipeline:
   - Segment synthesizer generates audio for the current paragraph in the matching voice.
   - At paragraph boundary, the voice switches. Pre-buffering ensures there is no audible gap (~200ms crossfade).
   - Highlight tracker follows the currently-speaking word using forced-alignment timestamps.
5. User can override per-paragraph: right-click → "Read this paragraph in [Voice X]."

### Flow C — Read selection from any app (system-wide hotkey)

1. User selects text in Safari/Mail/Notion/any app.
2. Presses `⌘⇧S` (or invokes Services menu → "Read with Rhea").
3. Rhea (running in menu bar) captures the pasteboard, detects language, opens a small floating reader window, starts playback.
4. Closing the window or pressing Escape stops playback.
5. This is the entry point that makes Rhea a *daily* tool, not just a document reader.

### Flow D — Library & resume

1. All opened documents appear in the library (sidebar).
2. Each shows: thumbnail (first page), title, % read, last-played timestamp, total estimated audio remaining.
3. Clicking resumes from last sentence. Position is retained per-document, per-voice.
4. Library supports: folders, tags, search (title + full-text), sort by recent / title / author.
5. No cloud sync in v1.0. CloudKit sync in v1.2 (opt-in).

### Flow E — Export to audiobook

1. User opens a document → File → Export as Audiobook…
2. Modal: voice picker (EN + ZH if bilingual), speed, "include figure captions" toggle, output format (m4b with chapters / mp3 / wav).
3. Background render with progress in status bar. User can keep reading other documents.
4. Output saved to Downloads (or a user-picked folder). Chapter markers match document headings.

### Flow F — Zotero integration (Phase 3)

1. Settings → Integrations → Enable Zotero.
2. Rhea detects the local Zotero DB at the standard path.
3. A new sidebar section shows Zotero collections and items.
4. Clicking an item opens its PDF directly from Zotero's storage.
5. Annotations created in Rhea (highlighted passages, the "last sentence heard" H-key feature) sync back to Zotero as annotations on the PDF.

---

## 4. Milestones (month-by-month)

The plan assumes **4–6 hours/week** (Jiahong has a dissertation and LEAI fellowship). For a full-time sprint, compress by ~2.5×.

### Month 1 — "It plays audio from a PDF"

**Goal:** a Mac app that opens a PDF, shows it, and plays Apple system voice audio with sentence highlighting. Proves the core architecture end-to-end with minimum risk.

**Milestones:**
- [ ] **M1.1** Xcode project set up. SwiftUI + AppKit shell. Menu bar, preferences window, single-document window. Developer ID signing configured.
- [ ] **M1.2** PDFKit document viewer embedded. Open a PDF. Scroll. Text selection works.
- [ ] **M1.3** PDFKit text extraction. Walk the loaded `PDFDocument` page by page, split on blank lines, produce a `[DocumentBlock]` model tagged with source page index. Zero dependencies, zero subprocesses — the day-one path per ADR-004. **Marker/MinerU integration (subprocess + first-PDF helper download) moves to M3.x** alongside the Chinese PDF cleanup work, where the download UI is needed anyway. Heading vs paragraph distinction is deferred to M4.1 (audiobook chapter markers) — M1.3 treats everything as a paragraph.
- [ ] **M1.4** Sentence segmenter (Swift, using `NSLinguisticTagger` with `.tokenType = .sentence`). Sentence index maps to character ranges in both the Markdown and the PDF annotation coordinates.
- [ ] **M1.5** AVSpeechSynthesizer playback. Play/pause/stop/seek-to-sentence.
- [ ] **M1.6** Sentence highlight overlay on the PDF view. PDFKit's annotation layer with an ephemeral `PDFAnnotationHighlight`. Sync with synthesizer's `didSpeakRangeOfSpeechString` delegate callback.
- [ ] **M1.7** Library sidebar (basic). Recent files list. Resume position.

**De-risks:** PDF-to-text round trip, highlight sync on the live PDF, Marker subprocess lifecycle, code signing + sandboxing.

**Shippable artifact:** internal TestFlight build to Jiahong + 2–3 PhD friends. Not public.

---

### Month 2 — "Kokoro English, with proper word-level sync"

**Goal:** swap Apple voices for Kokoro, and get word-level (not just sentence-level) highlighting working.

**Milestones:**
- [ ] **M2.1** `mlalma/kokoro-ios` integrated as a Swift package. Model downloads on first launch (~165 MB). Voice picker in Settings.
- [ ] **M2.2** Streaming synthesis: generate audio paragraph-by-paragraph, pre-buffer the next one. AVAudioEngine scheduling.
- [ ] **M2.3** WhisperKit forced alignment on the generated audio → word-level timestamps. (Reuse Hearba's WhisperKit integration.)
- [ ] **M2.4** Word-level highlight tracker. 0.15s linear interpolation between words. PDFKit annotation replaced each word.
- [ ] **M2.5** Playback controls polish: speed (0.5×–3×), pitch (±20%), per-voice memory.
- [ ] **M2.6** System-wide "Read Selection" via Services menu + global hotkey (`⌘⇧S`). Floating reader window.
- [ ] **M2.7** Markdown renderer + reader (not just PDF). `.md` files open in a prose view with the same interactions.

**De-risks:** Kokoro quality on academic text (test with real papers), forced-alignment accuracy, AVAudioEngine scheduling without pops at paragraph boundaries.

**Shippable artifact:** public TestFlight beta, English-only. Announce on HN / Show HN. Expected reaction: positive but "where's Chinese?"

---

### Month 3 — "The bilingual wedge. The launch."

**Goal:** Qwen3-TTS integrated, EN↔ZH auto-switch working, marketing site up, public launch.

**Milestones:**
- [ ] **M3.1** `AtomGradient/swift-qwen3-tts` integrated. Qwen3-TTS 0.6B CustomVoice downloads on first run for users who enable Chinese (opt-in to save disk).
- [ ] **M3.2** Per-paragraph language detection. `NLLanguageRecognizer` → `en`/`zh-Hans`/`zh-Hant` tag.
- [ ] **M3.3** Dual-voice orchestrator. Paragraph `i` synthesized with engine[lang[i]]. Crossfade at boundaries (200ms cosine fade). No audible click.
- [ ] **M3.4** Chinese-specific PDF cleanup (seal text, vertical-text runs, interline formula numbering — MinerU optional path).
- [ ] **M3.5** Research-PDF heuristics: footnote stripping, citation handling (`[23]` → skip / spoken as "reference 23" — user toggle), figure caption filtering.
- [ ] **M3.6** Marketing site (one page, bilingual). GitHub repo public. Demo video: 60 seconds, bilingual paper.
- [ ] **M3.7** Mac App Store submission. One-time purchase $29. Free tier (English system voices) + Pro unlock.

**De-risks:** Qwen3-TTS memory pressure on 8GB Macs (may need 0.6B-only path), audible quality of voice-switch crossfade, MAS review approval of embedded Python.

**Shippable artifact:** **Rhea 1.0**, public launch. Expected channel split: HN (~5K visits day 1), Reddit r/macapps + r/ObsidianMD, Chinese Twitter/微博 + zhihu article in Chinese. Target: 1,000 downloads week 1, 5% paid conversion.

---

### Month 4 — "Ship the features users asked for in week 1"

**Goal:** react to launch feedback. Prioritize from real user complaints, not from this plan.

**Likely milestones** (to be reprioritized based on actual feedback):
- [ ] **M4.1** m4b audiobook export with chapter markers (high demand, based on Speechify / Voice Dream complaints).
- [ ] **M4.2** Voice cloning from 3-sec sample (Qwen3-TTS supports it natively — low marginal work).
- [ ] **M4.3** EPUB support (via `FolioReaderKit` or custom epub-reader). This doubles the TAM.
- [ ] **M4.4** Read aloud from clipboard (menu bar icon → "Read clipboard").
- [ ] **M4.5** Reading analytics (local-only): words per minute, pages per session, streaks. Opt-in.
- [ ] **M4.6** Settings → Pronunciation dictionary. Map terms like "PDF" → "P D F," custom phonetics for author names.

**Shippable artifact:** Rhea 1.1.

---

### Month 5 — "The academic wedge"

**Goal:** own the PhD/researcher persona. This is where the "research-grade PDF reader" features land — but as add-ons to the already-working app, not as the core.

**Milestones:**
- [ ] **M5.1** Zotero integration (library browsing, PDF opening, annotation sync).
- [ ] **M5.2** Equation-as-prose: detect LaTeX/MathML, use Qwen-VL (local, MLX) or Florence-2 to describe equations in natural language. Optional. Slow. Worth it for blind researchers.
- [ ] **M5.3** Figure description: for figures with captions only, skip the figure body. For figures without captions, optional VLM description.
- [ ] **M5.4** Citation resolution: `[23]` → look up reference list → "reference 23: Smith et al., 2019, Nature."
- [ ] **M5.5** Obsidian plugin (optional): open `.md` notes in Rhea from Obsidian with one click.
- [ ] **M5.6** Annotate-as-you-listen: press H to highlight the sentence currently being read. Exports to standard PDF annotations.

**Shippable artifact:** Rhea 1.2 "Scholar." This is the "upgrade" moment for paid users.

---

### Month 6 — "Polish, stability, quiet months"

**Goal:** no new features. Kill bugs. Measure. Breathe.

- [ ] **M6.1** Crash-rate < 0.5% sessions.
- [ ] **M6.2** Performance: cold start < 2s, PDF open (10p) < 5s, first-word-audible < 1.5s after pressing play.
- [ ] **M6.3** Memory: idle < 300MB, playing Kokoro < 1GB, playing Qwen3-TTS 0.6B < 2.5GB.
- [ ] **M6.4** Accessibility pass: full VoiceOver support (ironic and important), Dynamic Type, reduced motion.
- [ ] **M6.5** Documentation site: user guide, keyboard shortcuts, privacy policy, FAQ.
- [ ] **M6.6** One design-quality review with an external Mac designer (paid, $1–2K). Kill anything that looks AI-generated.

**Shippable artifact:** Rhea 1.3. First feature-freeze. Assess: revenue run-rate, user love, whether to build 2.0 or move on.

---

## 5. Risks & mitigations

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Apple ships bilingual neural voices in macOS 27 | Low | High | Rhea's moat shifts to research-PDF + Zotero + polish. Not fatal. |
| iFlytek finally ships a Mac app | Medium | High | Ship within 6 months. Publish OSS Swift ports to establish community moat. |
| A funded competitor launches bilingual first | Medium | High | Monthly HN/Producthunt scan for "Chinese TTS Mac." Maintain 8-week shipping cadence. |
| Qwen3-TTS quality drops on long text | Low | Medium | Paragraph-level synthesis avoids context-window issues. Fallback to CosyVoice 3. |
| Marker is too slow / too big (300MB) | Medium | Medium | Lazy-download on first PDF. Offer pure-PDFKit text extraction as fallback (lower quality but works). |
| MAS review rejects embedded Python | Medium | Medium | Have a non-MAS .dmg build ready. Pre-validate by contacting DTS if needed. |
| Model download friction scares off first-run users | High | Medium | Use Apple system voices as day-1 default. Neural voices are an in-app upgrade. |
| 8GB M-chip Macs can't run Qwen3-TTS 0.6B | Medium | Medium | 8GB detection → disable Qwen3, suggest system Chinese voice. Display in settings. |
| Jiahong's dissertation advancement exam (late May 2026) | Certain | High | **Treat month 3 (May) as buffer.** Push launch to June if needed. Don't ship during exam prep. |

---

## 6. Success metrics (honest, not vanity)

**Month 3 launch week:**
- ≥ 1,000 downloads
- ≥ 50 paid conversions (Pro unlock)
- ≥ 100 GitHub stars on the Swift MLX ports
- ≥ 1 HN front-page moment

**Month 6:**
- ≥ 10,000 total downloads
- ≥ 500 paid conversions (≈ $14.5K gross, ≈ $10K after MAS cut — pays for year of Hugging Face + compute)
- ≥ 500 GitHub stars
- ≥ 1 feature / mention in an Anthropic, Simon Willison, or 阮一峰 weekly-style newsletter
- ≥ 20% of users are from China / Chinese diaspora (validates the wedge)

**Kill criteria (month 6):**
- < 100 paid conversions total: positioning is wrong or UX is off; consider sunsetting.
- > 2% refund rate: quality problem, pause and fix before more downloads.
- A direct competitor ships with > 90% feature overlap and better UX: fold into their ecosystem or pivot to a niche.

---

## 7. What gets deferred (explicit non-goals for v1)

- **Windows / Linux support.** Ever. This is a Mac app.
- **Cloud sync of documents.** Only last-read position, opt-in. Documents stay local.
- **AI chat over papers.** That's Unriddle/Anara territory. Stay in lane.
- **Podcast / web article ingestion.** v1 is PDF + Markdown + clipboard. EPUB in 1.1.
- **iOS app.** Maybe. After Mac is stable and profitable. Swift/MLX code ports mostly for free.
- **Voice cloning as a feature-pillar.** It's a bonus capability, not the story. Avoid brand confusion with Hearba.
- **Team/enterprise features, SSO, admin dashboards.** Not the customer.
- **Chat support.** Email + GitHub issues only. One person cannot run live chat.

---

## 8. Open questions (decide before month 1)

1. **MAS or direct-only at launch?** MAS gives trust and discovery but takes 30%. Direct .dmg takes 0% but requires Paddle/Stripe. *Tentative: MAS at launch, direct .dmg by month 4.*
2. **English-first TestFlight or bilingual from day one?** Waiting for bilingual delays the first user signal by a month. *Tentative: ship English TestFlight at end of month 2, bilingual public at month 3.*
3. **Marker vs MinerU as default parser.** Marker is faster and more mature; MinerU is better for Chinese scientific documents. *Tentative: Marker default, MinerU as opt-in for Chinese-heavy users.*
4. **Qwen3-TTS 0.6B vs 1.7B as default download?** 0.6B saves 2.2 GB and runs on 8GB Macs but quality is lower. *Tentative: 0.6B default, 1.7B as "Studio Quality" opt-in in Settings.*
5. **App icon design.** Needs to work at 16pt and 1024pt, render in both light/dark, and not look like a podcast app. *Action: commission or use a placeholder for M1, finalize by M3.*

---

## 9. Appendix A — Why "Rhea"

- **Meaning:** Greek titaness, mother of Zeus / "mother of voices" in ancient sources. Fits the "birth of voice from silence" metaphor without being on-the-nose.
- **Pronunciation:** REE-uh (English), ruì yǎ 瑞雅 (Chinese — "auspicious / elegant"). Clean bilingual alignment, which is rare.
- **Availability:**
  - `.app`: not taken on Mac App Store as a reader
  - `rhea.audio` / `rhea.app` / `readrhea.com`: worth checking availability
  - npm / pip / brew: minor conflicts, but this is a GUI app, not a package
- **No cultural baggage.** Not a cartoon character, not a real person's name (mostly), not a drug brand.
- **Sibling to Hearba:** both are 5 letters, both evoke a natural origin (herb, titaness), both feel "local and organic" rather than "tech platform-y."

Alternatives considered and rejected:
- *Liro* — too close to existing startup brands
- *Paperback* — genre-constrained, mobile-app taken
- *Orator* — correct meaning, dated feel
- *Koro* — too close to Kokoro (engine) and a medical condition
- *Caden* — Celtic name but feels boy-baby-name

---

## 10. Appendix B — Reference links for Claude Code to verify

- `AtomGradient/swift-qwen3-tts` — Qwen3-TTS MLX Swift package
- `mlalma/kokoro-ios` — Kokoro MLX Swift
- `Blaizzy/mlx-audio` — Python reference
- `VikParuchuri/marker` — Marker PDF parser
- `opendatalab/MinerU` — Chinese-scientific-PDF parser (alternative)
- `apple/swift-markdown` — native Markdown AST
- WhisperKit — forced alignment (already in Hearba)
- Apple docs: `PDFKit`, `AVSpeechSynthesizer`, `AVAudioEngine`, `NSLinguisticTagger`, `NLLanguageRecognizer`, SF Symbols 6

---

*End of milestone plan.*
