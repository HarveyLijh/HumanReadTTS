#!/usr/bin/env bash
#
# Build (and optionally run) Rhea.app from the command line.
#
# Two paths, auto-detected:
#   1. If full Xcode is installed (xcode-select -p points inside Xcode.app),
#      build via xcodebuild against the project file. This is canonical.
#   2. Otherwise, fall back to compiling the Swift sources directly with
#      swiftc and assembling a minimal .app bundle by hand. Works with
#      just the Command Line Tools.
#
# The fallback path is intentionally narrow — it's for fast local iteration
# until Xcode is installed. It does not run unit tests; for that, install
# Xcode and use `xcodebuild test`.
#
# Usage:
#   Scripts/build.sh                  # Debug build, do not launch
#   Scripts/build.sh --run            # Debug build + open Rhea.app
#   Scripts/build.sh --release --run  # Release build + open
#   Scripts/build.sh --clean          # Wipe build/ first
#   Scripts/build.sh -h               # Help
#

set -euo pipefail

# ─── Constants ──────────────────────────────────────────────────────────────

APP_NAME="Rhea"
BUNDLE_ID="app.rhea.mac"
DEPLOYMENT_TARGET="15.0"
SWIFT_VERSION="6"
MARKETING_VERSION="0.1.0"
BUILD_NUMBER="1"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# ─── Helpers ────────────────────────────────────────────────────────────────

c_reset=$'\033[0m'
c_dim=$'\033[2m'
c_bold=$'\033[1m'
c_amber=$'\033[38;5;214m'
c_red=$'\033[31m'

say()   { printf "%s→%s %s\n" "$c_amber" "$c_reset" "$1"; }
ok()    { printf "%s✓%s %s\n" "$c_amber" "$c_reset" "$1"; }
fail()  { printf "%s✗%s %s\n" "$c_red" "$c_reset" "$1" >&2; exit 1; }
note()  { printf "  %s%s%s\n" "$c_dim" "$1" "$c_reset"; }

usage() {
    cat <<EOF
${c_bold}Build Rhea.app${c_reset}

Usage: Scripts/build.sh [options]

Options:
  --run        Open Rhea.app after building
  --clean      Remove build/ before building
  --release    Build with optimizations (default: debug)
  -h, --help   Show this help

The script prefers xcodebuild if full Xcode is installed, otherwise
falls back to swiftc + a hand-assembled .app bundle.
EOF
}

# ─── Argument parsing ───────────────────────────────────────────────────────

run=0
clean=0
config="debug"

for arg in "$@"; do
    case "$arg" in
        --run)     run=1 ;;
        --clean)   clean=1 ;;
        --release) config="release" ;;
        -h|--help) usage; exit 0 ;;
        *) printf "Unknown argument: %s\n\n" "$arg" >&2; usage; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT"

if [[ $clean -eq 1 ]]; then
    say "Cleaning $BUILD_DIR"
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

# ─── Path selection ─────────────────────────────────────────────────────────

xcode_select_path="$(xcode-select -p 2>/dev/null || echo "")"
use_xcodebuild=0
if [[ "$xcode_select_path" == *"Xcode.app"* ]] && command -v xcodebuild >/dev/null 2>&1; then
    use_xcodebuild=1
fi

# ─── Build ──────────────────────────────────────────────────────────────────

if [[ $use_xcodebuild -eq 1 ]]; then
    say "Building with xcodebuild ($config)"
    note "developer dir: $xcode_select_path"

    xc_config="Debug"
    [[ "$config" == "release" ]] && xc_config="Release"

    derived_data="$BUILD_DIR/DerivedData"

    set -o pipefail
    if command -v xcbeautify >/dev/null 2>&1; then
        xcodebuild \
            -project Rhea.xcodeproj \
            -scheme Rhea \
            -configuration "$xc_config" \
            -derivedDataPath "$derived_data" \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO \
            CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
            build | xcbeautify
    else
        xcodebuild \
            -project Rhea.xcodeproj \
            -scheme Rhea \
            -configuration "$xc_config" \
            -derivedDataPath "$derived_data" \
            -destination 'platform=macOS' \
            CODE_SIGNING_ALLOWED=NO \
            CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
            build
    fi

    [[ -d "$APP_BUNDLE" ]] || fail "xcodebuild reported success but $APP_BUNDLE is missing"
    ok "Built $APP_BUNDLE"
else
    say "Full Xcode not detected — building with swiftc + Command Line Tools ($config)"
    note "developer dir: ${xcode_select_path:-<unset>}"

    sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
    [[ -d "$sdk_path" ]] || fail "Could not locate macOS SDK via xcrun"

    sources=(
        "App/Sources/RheaApp.swift"
        "App/Sources/AppScene.swift"
        "App/Sources/Colors.swift"
        "App/Sources/Typography.swift"
        "App/Sources/DropTarget/DroppedDocument.swift"
        "App/Sources/DropTarget/DropTargetView.swift"
    )

    rm -rf "$APP_BUNDLE"
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    swift_flags=(
        -sdk "$sdk_path"
        -target "arm64-apple-macos${DEPLOYMENT_TARGET}"
        -swift-version "$SWIFT_VERSION"
        -strict-concurrency=complete
        -D RHEA_CLI_BUILD
        -module-name "$APP_NAME"
        -emit-executable
        -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    )
    if [[ "$config" == "release" ]]; then
        swift_flags+=(-O)
    else
        swift_flags+=(-Onone -g -D DEBUG)
    fi

    say "Compiling ${#sources[@]} source files"
    swiftc "${swift_flags[@]}" "${sources[@]}"

    say "Writing Info.plist"
    cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${DEPLOYMENT_TARGET}</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleSupportedPlatforms</key>
    <array><string>MacOSX</string></array>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Harvey Li</string>
</dict>
</plist>
PLIST

    plutil -lint "$APP_BUNDLE/Contents/Info.plist" >/dev/null \
        || fail "Info.plist failed plutil -lint"

    say "Ad-hoc codesigning"
    codesign --force --sign - --timestamp=none "$APP_BUNDLE" >/dev/null 2>&1 \
        || fail "codesign failed"

    ok "Built $APP_BUNDLE"
fi

# ─── Launch (optional) ──────────────────────────────────────────────────────

if [[ $run -eq 1 ]]; then
    say "Launching Rhea.app"
    open "$APP_BUNDLE"
    note "Quit the app or close the window to return."
fi

printf "\n%s%sNext:%s drop a .pdf or .md file onto the Rhea window — the path appears.\n" \
    "$c_amber" "$c_bold" "$c_reset"
