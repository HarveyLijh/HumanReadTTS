#!/usr/bin/env bash
#
# Launch the latest dev build of Rhea from wherever Xcode stashed it.
#
# Xcode's DerivedData path has a scheme-specific hash in it
# (Rhea-<hash>/Build/Products/Debug/Rhea.app), which is tedious to
# type. This script asks xcodebuild for the canonical BUILT_PRODUCTS_DIR
# and launches the .app from there.
#
# Pass `--build` to rebuild first. Pass `--release` to target the
# Release configuration (you'll want that if you're sanity-checking the
# distribution bundle locally).
#
# Usage:
#   Scripts/run.sh                  # open the most recently built Debug
#   Scripts/run.sh --build          # xcodebuild Debug, then open
#   Scripts/run.sh --release        # open Release
#   Scripts/run.sh --build --release

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG="Debug"
SHOULD_BUILD=0
for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="Release" ;;
        --build)   SHOULD_BUILD=1   ;;
        -h|--help)
            sed -n '1,/^set /p' "$0" | sed 's/^# \{0,1\}//' | head -n -1
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "$SHOULD_BUILD" -eq 1 ]; then
    xcodebuild -project Rhea.xcodeproj -scheme Rhea \
               -configuration "$CONFIG" \
               -destination 'platform=macOS' \
               build | tail -3
fi

# Ask xcodebuild for the canonical build product path. -showBuildSettings
# reports BUILT_PRODUCTS_DIR which includes the DerivedData hash.
APP_PATH="$(xcodebuild -project Rhea.xcodeproj -scheme Rhea \
                       -configuration "$CONFIG" \
                       -destination 'platform=macOS' \
                       -showBuildSettings 2>/dev/null \
            | awk -F'= ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')/Rhea.app"

if [ ! -d "$APP_PATH" ]; then
    echo "Rhea.app not found at $APP_PATH — try --build first" >&2
    exit 1
fi

# Kill any running instance first so the freshly-built version launches
# rather than re-fronting a stale one.
pkill -9 -f "Rhea.app/Contents/MacOS/Rhea" 2>/dev/null || true
sleep 0.3
echo "Opening $APP_PATH"
open "$APP_PATH"
