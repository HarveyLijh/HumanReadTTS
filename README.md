# Rhea — internal build notes

> Internal documentation for the maintainer. The public README will land
> when M1.3 ships and the repo goes public.

Rhea is a local-first, bilingual (English + Chinese) macOS TTS reader for
PDFs and Markdown. The full vision and milestone plan live in
[`docs/MILESTONES.md`](docs/MILESTONES.md). Architectural decisions live
in [`docs/decisions.md`](docs/decisions.md).

## Requirements

- macOS 15 Sequoia or newer (Apple Silicon)
- Xcode 16 or newer (Swift 6 toolchain)
- An Apple developer team for code signing in `Release` builds

## First-time setup

```sh
git clone git@github.com:harveylijh/rhea.git
cd rhea
cp Configs/Local.xcconfig.example Configs/Local.xcconfig
# Edit Configs/Local.xcconfig and set DEVELOPMENT_TEAM to your team ID.
# Local.xcconfig is gitignored.
open Rhea.xcodeproj
```

Xcode will pick the team automatically once `Local.xcconfig` is in place.
There is no Tuist, no XcodeGen, no `tuist generate` step. The
`Rhea.xcodeproj` file is hand-maintained and committed.

## Build & run

| Task | Command |
| --- | --- |
| Build + run (no Xcode required) | `Scripts/build.sh --run` |
| Build only (debug) | `Scripts/build.sh` |
| Build + run (release, optimized) | `Scripts/build.sh --release --run` |
| Wipe build/ first | `Scripts/build.sh --clean --run` |
| Build via xcodebuild (Debug) | `xcodebuild -project Rhea.xcodeproj -scheme Rhea -configuration Debug build CODE_SIGNING_ALLOWED=NO` |
| Run tests (requires full Xcode) | `xcodebuild -project Rhea.xcodeproj -scheme Rhea test` |
| Open in Xcode | `open Rhea.xcodeproj` |

`Scripts/build.sh` auto-detects whether you have full Xcode or only the
Command Line Tools. Without Xcode it compiles directly with `swiftc` and
assembles a minimal `.app` bundle in `build/Rhea.app`. With Xcode it
delegates to `xcodebuild` against the project file (canonical path).
Unit tests require full Xcode.

In Xcode: select the `Rhea` scheme, press ⌘R.

## Configuration model

Build settings live in three places, in priority order:

1. **`Configs/Local.xcconfig`** (gitignored) — your team ID and any
   per-machine overrides.
2. **`Configs/Rhea.xcconfig`** (committed) — shared base settings; falls
   through to `Local.xcconfig` via `#include?`.
3. **`Rhea.xcodeproj/project.pbxproj`** (committed) — target structure,
   file membership. Build settings here are minimised; prefer xcconfig.

The sandbox is **OFF in Debug** (faster iteration; helper-subprocess
work in Month 3 needs it off) and **ON in Release** (hardened-runtime
defense-in-depth for notarized .dmg distribution). See ADR-003.

## Repository layout

```
.
├── App/
│   ├── Sources/                     # SwiftUI app code (Rhea target)
│   │   ├── RheaApp.swift
│   │   ├── AppScene.swift
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   └── DropTarget/
│   │       ├── DropTargetView.swift
│   │       └── DroppedDocument.swift
│   ├── Resources/                   # Assets, app-bundle resources
│   └── Rhea.entitlements            # Used by Release config only
├── Tests/
│   └── AppTests/                    # XCTest unit + smoke tests
├── Packages/                        # Local SwiftPM packages (added per milestone)
├── Configs/
│   ├── Rhea.xcconfig                # Shared base (committed)
│   └── Local.xcconfig.example       # Template for per-machine overrides
├── Rhea.xcodeproj/                  # Hand-maintained Xcode project
├── docs/
│   ├── MILESTONES.md                # Vision + month-by-month plan (authoritative)
│   └── decisions.md                 # ADR log
├── LICENSE                          # Apache 2.0
├── NOTICE
└── README.md                        # This file
```

`Packages/` is empty in M1.1. The first local package (`RheaDocument`)
arrives in M1.4 when sentence segmentation lands.

## Distribution

Apache-2.0, OSS, .dmg via GitHub Releases + Homebrew Cask. **Not** going
to the Mac App Store. See ADR-001 and `docs/decisions.md` for context.

## Conventions

- **Commits**: Conventional Commits (`feat:`, `fix:`, `refactor:`,
  `chore:`, `docs:`, `test:`). One milestone per commit when possible.
  English. No `Co-Authored-By` trailers.
- **Branch**: trunk-based on `main`. Feature branches when a change
  spans more than one commit.
- **Swift**: strict concurrency, Swift 6 mode, deployment target macOS 15.
- **Style**: Apple's Swift API Design Guidelines. No external linter
  rule set yet (consider SwiftFormat if/when contributors arrive).
