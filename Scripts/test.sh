#!/usr/bin/env bash
#
# Run the ReadAloudTTS test suite via xcodebuild and summarise results.
# Requires full Xcode (the swiftc CLI fallback can't host XCTest).
#
# Usage:
#   Scripts/test.sh                  # run all tests
#   Scripts/test.sh --only <suite>   # run a single test class
#   Scripts/test.sh -h               # help
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
RESULTS_DIR="$BUILD_DIR/TestResults"

c_reset=$'\033[0m'
c_dim=$'\033[2m'
c_bold=$'\033[1m'
c_amber=$'\033[38;5;214m'
c_red=$'\033[31m'
c_green=$'\033[32m'

say()   { printf "%s→%s %s\n" "$c_amber" "$c_reset" "$1"; }
ok()    { printf "%s✓%s %s\n" "$c_green" "$c_reset" "$1"; }
fail()  { printf "%s✗%s %s\n" "$c_red" "$c_reset" "$1" >&2; exit 1; }

usage() {
    cat <<EOF
${c_bold}Run ReadAloudTTS tests${c_reset}

Usage: Scripts/test.sh [options]

Options:
  --only <suite>   Run a single test class (e.g. SentenceSegmenterTests)
  --network        Include opt-in network tests (model URL reachability)
  -h, --help       Show this help

Output:
  Per-suite pass/fail summary, total counts, and the path to the
  full .xcresult bundle for inspection in Xcode.
EOF
}

only=""
network=0
for arg in "$@"; do
    case "$arg" in
        --only)
            shift; only="${1:-}"; [[ -n "$only" ]] || fail "--only requires a suite name"
            ;;
        --network)
            network=1
            ;;
        -h|--help)
            usage; exit 0
            ;;
        *)  ;;
    esac
done

# Filesystem sentinel is how network tests opt in (env vars
# don't propagate into the xcodebuild-hosted test runner on macOS).
sentinel="/tmp/readaloudtts-run-network-tests"
if [[ $network -eq 1 ]]; then
    say "Enabling network tests (touching $sentinel)"
    touch "$sentinel"
    trap 'rm -f "$sentinel"' EXIT
fi

cd "$PROJECT_ROOT"

xcode_select_path="$(xcode-select -p 2>/dev/null || echo "")"
if [[ "$xcode_select_path" != *"Xcode.app"* ]] || ! command -v xcodebuild >/dev/null 2>&1; then
    fail "Full Xcode required (current developer dir: ${xcode_select_path:-<unset>}). Install Xcode and run 'sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'."
fi

mkdir -p "$BUILD_DIR"
rm -rf "$RESULTS_DIR"

say "Running tests via xcodebuild"

cmd=(
    xcodebuild
    -project ReadAloudTTS.xcodeproj
    -scheme ReadAloudTTS
    -destination 'platform=macOS'
    -derivedDataPath "$BUILD_DIR/DerivedData"
    -resultBundlePath "$RESULTS_DIR"
    CODE_SIGNING_ALLOWED=NO
    test
)

if [[ -n "$only" ]]; then
    cmd+=(-only-testing:"ReadAloudTTSTests/$only")
fi

# Run, capture all output for parsing, but stream a filtered subset
# to the terminal so the human can see progress.
tmplog="$(mktemp -t readaloudtts-test.XXXXXX)"
trap 'rm -f "$tmplog"' EXIT

set +e
"${cmd[@]}" >"$tmplog" 2>&1
status=$?
set -e

# Per-suite summary lines (Xcode prints "Test Suite '...' passed/failed").
printf "\n%s%sSummary%s\n" "$c_amber" "$c_bold" "$c_reset"
grep -E "Test Suite '[^']+' (passed|failed)" "$tmplog" \
    | grep -v "Selected tests\|All tests\|ReadAloudTTSTests.xctest" \
    | while IFS= read -r line; do
        if [[ "$line" == *"passed"* ]]; then
            suite="$(printf '%s' "$line" | sed -E "s/.*Test Suite '([^']+)'.*/\\1/")"
            printf "  %s✓%s %s\n" "$c_green" "$c_reset" "$suite"
        else
            suite="$(printf '%s' "$line" | sed -E "s/.*Test Suite '([^']+)'.*/\\1/")"
            printf "  %s✗%s %s\n" "$c_red" "$c_reset" "$suite"
        fi
    done

# Totals (last "Executed N tests" line is the grand total).
totals="$(grep -E "Executed [0-9]+ tests" "$tmplog" | tail -1 || true)"
[[ -n "$totals" ]] && printf "\n%s%s%s\n" "$c_dim" "$totals" "$c_reset"

# Surface any individual XCTAssert failure messages.
failures="$(grep -E "error: -\[" "$tmplog" || true)"
if [[ -n "$failures" ]]; then
    printf "\n%s%sFailures%s\n" "$c_red" "$c_bold" "$c_reset"
    printf '%s\n' "$failures" | sed 's/^/  /'
fi

if [[ $status -eq 0 ]]; then
    printf "\n"
    ok "All tests passed"
    printf "  %sresults: %s%s\n" "$c_dim" "$RESULTS_DIR" "$c_reset"
else
    printf "\n"
    fail "Tests failed (status $status). Full log: $tmplog (will not auto-delete due to failure)"
fi
