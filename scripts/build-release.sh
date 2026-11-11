#!/usr/bin/env bash
# build-release.sh
# Build the FORTH/Sigma release executables on Linux and macOS, as
# build-release.ps1 does on Windows.
#
# Builds sigma with 'zig build -Doptimize=fast', once with the floating-point
# words and once without them (-Dfloat=false), and prints the path of each
# executable.
#
# Usage:
#   ./scripts/build-release.sh [options]
#
# Options:
#   --output DIR           Where the version with the floating-point words goes
#                          (default: dist/release)
#   --nofloat-output DIR   Where the version without them goes
#                          (default: dist/release-nofloat)
#   --target TRIPLE        Zig target, such as x86_64-linux-musl,
#                          aarch64-linux-musl, arm-linux-musleabihf or
#                          aarch64-macos (default: this machine, with the
#                          baseline CPU)
#   --variant VARIANT      both, float or nofloat (default: both)
#
# Output:
#   <output>/bin/sigma and <nofloat-output>/bin/sigma (sigma.exe for a Windows
#   target)

set -euo pipefail

OUTPUT=""
NOFLOAT_OUTPUT=""
TARGET=""
VARIANT=both

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|--nofloat-output|--target|--variant)
            if [[ $# -lt 2 ]]; then
                echo "Error: $1 needs a value." >&2
                exit 1
            fi
            case "$1" in
                --output)         OUTPUT="$2" ;;
                --nofloat-output) NOFLOAT_OUTPUT="$2" ;;
                --target)         TARGET="$2" ;;
                --variant)        VARIANT="$2" ;;
            esac
            shift 2 ;;
        -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

case "$VARIANT" in
    both|float|nofloat) ;;
    *) echo "Error: invalid --variant '$VARIANT'. Expected both, float or nofloat." >&2; exit 1 ;;
esac
if ! command -v zig > /dev/null; then
    echo "Error: zig not found in PATH." >&2
    exit 1
fi

# The output directories are as the caller gave them, from where the script was
# called; the build runs from the repository root.
absolute() {
    case "$1" in
        /*) printf '%s\n' "$1" ;;
        *)  printf '%s\n' "$PWD/$1" ;;
    esac
}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ -z "$OUTPUT" ]]; then OUTPUT="$ROOT/dist/release"; else OUTPUT=$(absolute "$OUTPUT"); fi
if [[ -z "$NOFLOAT_OUTPUT" ]]; then NOFLOAT_OUTPUT="$ROOT/dist/release-nofloat"; else NOFLOAT_OUTPUT=$(absolute "$NOFLOAT_OUTPUT"); fi
cd "$ROOT"

case "$TARGET" in
    *windows*) EXECUTABLE=sigma.exe ;;
    *)         EXECUTABLE=sigma ;;
esac

# Builds one version into the directory $1; $2 is float or nofloat.
build() {
    local arguments=(build -Doptimize=fast --prefix "$1")
    if [[ -n "$TARGET" ]]; then
        arguments+=("-Dtarget=$TARGET")
    else
        # Without a target, Zig builds for the CPU of this machine, and the program
        # can then fail on a CPU without the same instructions (AVX-512, for example).
        arguments+=(-Dcpu=baseline)
    fi
    if [[ "$2" == nofloat ]]; then
        # Leaves out the floating-point words and CORE-MATH.
        arguments+=(-Dfloat=false)
    fi
    # zig's own output goes to standard error, so that only the paths are printed.
    zig "${arguments[@]}" >&2
    if [[ ! -f "$1/bin/$EXECUTABLE" ]]; then
        echo "Error: the release executable was not produced: $1/bin/$EXECUTABLE" >&2
        exit 1
    fi
    printf '%s\n' "$1/bin/$EXECUTABLE"
}

if [[ "$VARIANT" != nofloat ]]; then build "$OUTPUT" float; fi
if [[ "$VARIANT" != float ]]; then build "$NOFLOAT_OUTPUT" nofloat; fi
