#!/usr/bin/env bash
#
# Build a Release Rhea.app, sign it, and pack it into a .dmg.
#
# Signing / notarisation is optional: if DEVELOPER_ID_APPLICATION
# is set we Developer-ID-sign + (optionally) notarise. Otherwise
# we leave the ad-hoc signature in place — the .dmg still opens,
# Gatekeeper just shows the first-run warning and users have to
# right-click → Open.
#
# Required env vars for full notarisation:
#   DEVELOPER_ID_APPLICATION   e.g. "Developer ID Application: Harvey Li (XXXXXXXXXX)"
#   NOTARY_APPLE_ID            Apple ID used for notarytool (email)
#   NOTARY_TEAM_ID             e.g. "XXXXXXXXXX"
#   NOTARY_PASSWORD            app-specific password (create at appleid.apple.com)
#
# For an OSS project that doesn't want the $99/yr paid program, the
# unsigned path is fine — just ship the DMG and tell users to
# right-click → Open on first launch (the script prints the exact
# text to include in the release notes).
#
# Usage:
#   Scripts/package.sh             # build + sign (if creds) + DMG
#   Scripts/package.sh --notarize  # + submit to Apple + staple
#   Scripts/package.sh -h          # help

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DIST_DIR="$PROJECT_ROOT/dist"
APP_NAME="Rhea"
SCHEME="Rhea"
CONFIG="Release"

c_reset=$'\033[0m'
c_amber=$'\033[38;5;214m'
c_dim=$'\033[2m'
c_red=$'\033[31m'

say()  { printf "%s→%s %s\n" "$c_amber" "$c_reset" "$1"; }
ok()   { printf "%s✓%s %s\n" "$c_amber" "$c_reset" "$1"; }
fail() { printf "%s✗%s %s\n" "$c_red" "$c_reset" "$1" >&2; exit 1; }
note() { printf "  %s%s%s\n" "$c_dim" "$1" "$c_reset"; }

usage() {
    cat <<EOF
Build a signed Rhea.dmg.

  --notarize    Submit to Apple notarytool and staple. Requires
                NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD.
  --clean       Wipe build/ and dist/ before packaging.
  -h, --help    Show this help.

Without DEVELOPER_ID_APPLICATION set the .app is left ad-hoc signed
and the DMG is unsigned. Works for local use / self-hosted sharing
but Gatekeeper will warn the first time a downloader opens it.
EOF
}

notarize=0
clean=0
for arg in "$@"; do
    case "$arg" in
        --notarize) notarize=1 ;;
        --clean)    clean=1 ;;
        -h|--help)  usage; exit 0 ;;
        *)          fail "unknown flag: $arg" ;;
    esac
done

if [[ "$clean" == "1" ]]; then
    say "Cleaning build/ and dist/"
    rm -rf "$BUILD_DIR" "$DIST_DIR"
fi

mkdir -p "$DIST_DIR"

# ── Build Release ────────────────────────────────────────────────
say "xcodebuild $CONFIG"
xcodebuild \
    -project "$PROJECT_ROOT/Rhea.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -destination 'platform=macOS' \
    build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    >/dev/null
ok "Release build complete"

SRC_APP="$BUILD_DIR/DerivedData/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$SRC_APP" ]] || fail "$APP_NAME.app not at expected path: $SRC_APP"

STAGE="$DIST_DIR/staging"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$SRC_APP" "$STAGE/"

# ── Sign ─────────────────────────────────────────────────────────
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    say "Codesigning with $DEVELOPER_ID_APPLICATION"
    # Sign every embedded framework/bundle first, then the outer app.
    find "$STAGE/$APP_NAME.app/Contents/Frameworks" -type d \( -name "*.framework" -o -name "*.bundle" \) 2>/dev/null | while read bundle; do
        codesign --force --timestamp --options runtime \
            --sign "$DEVELOPER_ID_APPLICATION" "$bundle"
    done
    codesign --force --deep --timestamp --options runtime \
        --sign "$DEVELOPER_ID_APPLICATION" "$STAGE/$APP_NAME.app"
    ok "Developer-ID signed"
else
    note "DEVELOPER_ID_APPLICATION not set — leaving ad-hoc signature"
fi

# ── Build DMG ────────────────────────────────────────────────────
DMG_NAME="$APP_NAME-$(defaults read "$SRC_APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 0.1.0).dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

say "hdiutil create $DMG_NAME"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG_PATH" >/dev/null
ok "DMG built: $DMG_PATH"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    say "Signing DMG"
    codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
    ok "DMG signed"
fi

# ── Notarise (optional) ──────────────────────────────────────────
if [[ "$notarize" == "1" ]]; then
    : "${NOTARY_APPLE_ID:?NOTARY_APPLE_ID must be set}"
    : "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID must be set}"
    : "${NOTARY_PASSWORD:?NOTARY_PASSWORD must be set}"

    say "Submitting $DMG_NAME to Apple notarytool…"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$NOTARY_APPLE_ID" \
        --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" \
        --wait
    ok "Notarisation accepted"

    say "Stapling ticket"
    xcrun stapler staple "$DMG_PATH"
    ok "Stapled"
fi

printf "\n%s%s%s\n" "$c_amber" "Ready: $DMG_PATH" "$c_reset"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    cat <<EOF

${c_dim}# Unsigned DMG — ship it as-is. Include this note with the download:
#
#   First-run instructions for users:
#     1. Download and mount the DMG, drag Rhea to /Applications.
#     2. First launch: right-click Rhea.app → Open → click "Open" in
#        the Gatekeeper dialog. (Double-clicking shows a blocked
#        dialog with no "Open" button — that's macOS's quirk.)
#     3. Works normally every time after that.
#
#   Or paste this one-liner in Terminal to remove the quarantine flag:
#     xattr -dr com.apple.quarantine /Applications/Rhea.app${c_reset}
EOF
fi
