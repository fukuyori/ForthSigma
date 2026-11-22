#!/usr/bin/env bash
# verify-default-fpath.sh
# Checks FPATH's default at start-up on Linux and macOS (tque 1250, 1252): that the
# libraries in `include` beside the executable load from another directory, however
# Sigma is started.
#
# Usage:
#   tests/scripts/verify-default-fpath.sh SIGMA
#
# SIGMA is the executable, with its `include` directory beside it (as in the ZIPs and in
# zig-out/bin). Nothing is changed there: the script makes a temporary directory, with
# symbolic links to SIGMA in it, starts Sigma in six ways from an empty working
# directory, and removes the directory. It prints the system, each way's FPATH, and
# PASS or FAIL; it ends with 1 when a way failed.

set -uo pipefail

if [[ $# -ne 1 ]]; then
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
case "$1" in
    /*) SIGMA="$1" ;;
    *)  SIGMA="$PWD/$1" ;;
esac
APP=$(cd "$(dirname "$SIGMA")" && pwd)
NAME=$(basename "$SIGMA")
if [[ ! -x "$APP/$NAME" ]]; then echo "Error: not an executable: $APP/$NAME" >&2; exit 2; fi
if [[ ! -d "$APP/include" ]]; then echo "Error: no include directory beside it: $APP/include" >&2; exit 2; fi

TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
mkdir "$TEMP/work" "$TEMP/link" "$TEMP/parent"
ln -s "$APP/$NAME" "$TEMP/link/$NAME"
ln -s "$APP" "$TEMP/parent/app"
printf 'FPATH .PATH CR\nREQUIRE ym2149-levels.fs .( LOADED-PLAIN) CR\nREQUIRE msx-sound.fs .( LOADED-CHAINED) CR\nBYE\n' > "$TEMP/work/t.fs"

echo "system: $(uname -srm)"
if [[ -r /etc/os-release ]]; then
    sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | sed 's/^/os: /'
elif command -v sw_vers > /dev/null; then
    echo "os: $(sw_vers -productName) $(sw_vers -productVersion)"
fi
if grep -qi microsoft /proc/version 2> /dev/null; then echo "note: this is WSL, not a Linux machine"; fi
echo "executable: $APP/$NAME"

failed=0
# $1 is the way's name; the rest is the command that starts Sigma (PATH= as its first
# word sets the search path for that start only).
check() {
    local label="$1"; shift
    local out
    out=$(cd "$TEMP/work" && env "$@" t.fs 2>&1)
    if [[ "$out" == *LOADED-PLAIN* && "$out" == *LOADED-CHAINED* ]]; then
        echo "PASS  $label"
    else
        echo "FAIL  $label"
        failed=1
    fi
    printf '%s\n' "$out" | head -1 | sed 's/^/      FPATH: /'
    if [[ "$out" != *LOADED-CHAINED* ]]; then printf '%s\n' "$out" | tail -2 | sed 's/^/      /'; fi
}

# The path from the working directory to the executable's, for the relative start.
relative=$(python3 -c 'import os,sys; print(os.path.relpath(os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])))' "$APP" "$TEMP/work" 2> /dev/null || true)

check "1 absolute path" "$APP/$NAME"
if [[ -n "$relative" ]]; then check "2 relative path" "$relative/$NAME"; else echo "SKIP  2 relative path (python3 is needed for it)"; fi
check "3 found by PATH" "PATH=$APP:$PATH" "$NAME"
check "4 symbolic link to the executable" "$TEMP/link/$NAME"
check "5 symbolic link to its directory" "$TEMP/parent/app/$NAME"
check "6 symbolic link found by PATH" "PATH=$TEMP/link:$PATH" "$NAME"

if [[ $failed -ne 0 ]]; then echo "RESULT: FAILED"; exit 1; fi
echo "RESULT: all passed"
