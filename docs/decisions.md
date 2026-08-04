# Architectural Decision Records

Each ADR is a short note about a decision that's expensive to reverse
and worth explaining to a future maintainer (or a future me). Format
adapted from Michael Nygard's original ADR template.

Status values: `Proposed`, `Accepted`, `Superseded by ADR-NNN`,
`Deprecated`.

---

## ADR-001 — Distribute as Apache-2.0 OSS, not via the Mac App Store

**Date:** 2026-04-17
**Status:** Accepted

### Context

`docs/MILESTONES.md` §0 originally proposed a dual-license MacWhisper
playbook: Apache-2.0 OSS Swift packages for the building blocks plus a
commercial Mac App Store app with a $29 one-time Pro unlock.

While drafting M1.1 we hit two collisions with that plan:

- **Marker (the planned PDF parser) is GPL-3.0**, with model weights
  under a custom AI Pubs Open Rail-M license that caps commercial use
  at $2M revenue. Apple's Licensed Application End User License
  Agreement is widely understood to forbid GPL-family code in MAS
  binaries (the canonical example is VLC being pulled from MAS).
- **Embedding a Python interpreter inside a sandboxed MAS bundle**
  remains painful per Apple Developer Forums threads through 2024–2026.
  Doable, but consumes Month 3 budget on plumbing that ships no
  user-visible feature.

The unfunded-solo-developer comparable apps in this segment — Ollama,
LM Studio, MacWhisper, Raycast, Rectangle, Stats, Transmission, VLC —
ship outside MAS. The OSS posture is also more credible to the
research/PhD audience the project is aimed at.

### Decision

HumanReadTTS is licensed under **Apache 2.0**, distributed as a **notarized
Developer-ID `.dmg`** via GitHub Releases and (later) a Homebrew Cask.
Funding, if any, comes from GitHub Sponsors. There is no MAS build, no
Pro tier, no subscription, and no in-app purchase infrastructure.

### Consequences

- The GPL-in-bundle problem dissolves under the standard "mere
  aggregation" reading: an Apache-2.0 app shipping a GPL subprocess in
  a separate process boundary is acceptable.
- Sandbox entitlement gymnastics for embedded Python become unnecessary.
- Global hotkey via `CGEventTap` + user-granted Accessibility permission
  is back on the table (MAS sandbox forbids it; Developer-ID does not).
- We owe no 30% to Apple, and there is no MAS review latency on the
  release path.
- `MILESTONES.md` §0 will be updated in a follow-up commit so the
  authoritative spec matches reality.

---

## ADR-002 — Hand-maintained `HumanReadTTS.xcodeproj` + SwiftPM `Packages/`, not Tuist

**Date:** 2026-04-17
**Status:** Accepted

### Context

Tuist (4.178.1, actively maintained) was the initial proposal. It gives
a Swift-DSL manifest, modularization helpers, and built-in caching.

The audience we actually have is one developer plus eventual OSS
contributors. The pbxproj-merge-conflict problem Tuist solves does not
exist for one developer. Hearba (Harvey's other macOS app) uses plain
Xcode + SwiftPM, and consistency across the two apps matters more than
theoretical wins.

OSS contributor friction is the deciding factor. "Clone and open
`HumanReadTTS.xcodeproj`" is a zero-step onboarding. "Install Tuist, run
`tuist generate`, then open" is the kind of step where contributors
bounce. Every dependency we plan to pull in (WhisperKit, MLX-Swift,
mlalma/kokoro-ios, AtomGradient/swift-qwen3-tts, swift-markdown) ships
as a SwiftPM package, so the SwiftPM path is friction-free.

### Decision

A single `HumanReadTTS.xcodeproj` lives at the repo root, hand-maintained and
committed. Extractable logic goes into local SwiftPM packages under
`Packages/`. Packages are referenced from the Xcode project as local
package dependencies (added milestone-by-milestone, not ahead of need).

Per-machine settings (developer team ID) live in `Configs/Local.xcconfig`,
which is gitignored. `Configs/HumanReadTTS.xcconfig` is the committed shared
base and `#include?`s the local override.

### Consequences

- No new tooling for contributors to install.
- Xcode-driven changes to project settings will appear as pbxproj
  diffs, which we accept.
- We will revisit if the project ever grows beyond ~5 packages or
  beyond a single developer; until then the simpler tooling wins.

---

## ADR-003 — Sandbox OFF in Debug, ON in Release

**Date:** 2026-04-17
**Status:** Accepted

### Context

The original draft of this ADR proposed sandbox-on in Debug to avoid
release-day entitlement surprises. After ADR-001 (no MAS) the sandbox
is no longer a ship-blocker and trading some safety for development
ergonomics is reasonable — especially for the Marker subprocess work
in Month 3, which is harder to iterate on inside a sandbox.

Comparable Developer-ID-distributed Mac apps (Ollama, MacWhisper,
Raycast) ship unsandboxed. Users install via `.dmg` or `brew` and
authenticate the developer signature.

### Decision

- **Debug**: `CODE_SIGN_ENTITLEMENTS` is empty. The app runs without
  the sandbox.
- **Release**: `CODE_SIGN_ENTITLEMENTS = App/HumanReadTTS.entitlements`, which
  enables the sandbox plus user-selected file read access. Hardened
  runtime is on. This config is what gets notarized for the .dmg.

If we ever revisit MAS we will re-evaluate; the entitlements file is
already in place to make that transition cheaper.

### Consequences

- Faster iteration in Debug; we touch the filesystem and spawn helper
  subprocesses without sandbox friction.
- Release builds remain hardened. We discover any sandbox-related
  regressions during release-candidate testing rather than at ship time.

---

## ADR-004 — Marker is never bundled; user downloads on first PDF

**Date:** 2026-04-17
**Status:** Accepted

### Context

Marker is the planned structured-PDF parser. It is a Python package
roughly 300 MB unpacked, plus model weights. Two reasons against
bundling it inside `HumanReadTTS.app`:

1. **Bundle size**: a 300 MB+ application download for a launch where
   the user has not yet decided to keep the app is bad UX.
2. **Licensing**: even with ADR-001 (no MAS) shipping GPL code inside a
   permissively-licensed bundle creates avoidable license-compatibility
   conversations. Keeping Marker in a separate process and a separate
   filesystem location keeps the boundary unambiguous.

### Decision

HumanReadTTS ships with **PDFKit's built-in text extraction** as the day-one
default. Marker is offered as an opt-in enhancer, downloaded on demand
into `~/Library/Application Support/HumanReadTTS/helpers/` when the user opens
their first PDF (or via Settings → Document Parsing). The download is
visible, cancellable, and cached.

The same pattern will apply to all neural model weights (Kokoro,
Qwen3-TTS, optional CosyVoice) per MILESTONES §2.

### Consequences

- `HumanReadTTS.app` itself is small (single-digit MB at launch).
- The first-PDF flow needs a graceful "downloading parser…" state that
  doesn't block the rest of the UI. This is a Month 3 design item, not
  a Month 1 item.
- For users who never want to download Marker, the PDFKit-only path
  must remain a usable fallback with degraded but acceptable parsing
  for simple PDFs. We will document the quality difference.

---

## ADR-005 — Strict Swift 6 concurrency from day one

**Date:** 2026-04-17
**Status:** Accepted

### Context

Swift 6 ships strict concurrency checking. Starting in `complete`
mode means we eat any migration pain as it arises rather than
retrofitting later. The audio pipeline (M2.2 onwards) is concurrency-
heavy and benefits from the compiler enforcing isolation up front.

### Decision

`SWIFT_STRICT_CONCURRENCY = complete` is set in
`Configs/HumanReadTTS.xcconfig`. All targets inherit it.

### Consequences

- Some early friction in Debug builds when wiring up the AV stack.
- Simpler reasoning about main-actor boundaries when the app grows.
- If a third-party SwiftPM dependency is incompatible with strict
  concurrency we will lower the setting for that specific package only,
  not project-wide.
