#!/usr/bin/env bash
# build-release.sh
# Build the FORTH/Sigma release executables on Linux and macOS, as
# build-release.ps1 does on Windows.
#
# Builds the full Sigma and the Forth 2012 profile. The Forth 2012 profile keeps
# standard word sets, including floating point and files, while leaving out
# graphics, audio, and Sigma's extension vocabulary.
#
# Usage:
#   ./scripts/build-release.sh [options]
#
# Options:
#   --output DIR           Where the full version goes (default: dist/release)
#   --forth2012-output DIR Where the Forth 2012 profile goes
#                          (default: dist/release-forth2012)
#   --target TRIPLE        Zig target, such as x86_64-linux-musl,
#                          aarch64-linux-musl or aarch64-macos (default: on Linux, the musl target of
#                          this machine's CPU, as the released executables
#                          are built; elsewhere this machine, with the
#                          baseline CPU)
#   --variant VARIANT      both, full or forth2012 (default: both)
#
# Output:
#   <output>/bin/sigma and <forth2012-output>/bin/sigma (sigma.exe for a Windows
#   target)

set -euo pipefail

OUTPUT=""
FORTH2012_OUTPUT=""
TARGET=""
VARIANT=both

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output|--forth2012-output|--target|--variant)
            if [[ $# -lt 2 ]]; then
                echo "Error: $1 needs a value." >&2
                exit 1
            fi
            case "$1" in
                --output)         OUTPUT="$2" ;;
                --forth2012-output) FORTH2012_OUTPUT="$2" ;;
                --target)         TARGET="$2" ;;
                --variant)        VARIANT="$2" ;;
            esac
            shift 2 ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

case "$VARIANT" in
    both|full|forth2012) ;;
    *) echo "Error: invalid --variant '$VARIANT'. Expected both, full or forth2012." >&2; exit 1 ;;
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
if [[ -z "$FORTH2012_OUTPUT" ]]; then FORTH2012_OUTPUT="$ROOT/dist/release-forth2012"; else FORTH2012_OUTPUT=$(absolute "$FORTH2012_OUTPUT"); fi
cd "$ROOT"

# In WSL, a repository in a Windows folder (/mnt/c and the like, a 9p or drvfs mount)
# cannot hold Zig's local cache: Zig renames a directory into it, which fails there
# with AccessDenied. The cache then goes to the Linux file system; the output
# directories can stay in the Windows folder. ZIG_LOCAL_CACHE_DIR, when set, is kept.
if [[ -z "${ZIG_LOCAL_CACHE_DIR:-}" && "$(uname -s)" == Linux ]]; then
    filesystem=$(findmnt -n -o FSTYPE -T "$ROOT" 2> /dev/null || stat -f -c %T "$ROOT" 2> /dev/null || true)
    case "$filesystem" in
        9p|v9fs|drvfs|wslfs)
            export ZIG_LOCAL_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/forth-sigma/zig-cache"
            echo "Zig's local cache: $ZIG_LOCAL_CACHE_DIR (the repository is on a $filesystem mount)" >&2 ;;
    esac
fi

# On Linux the default is the static musl build of this machine's CPU, the form the
# released executables have. It uses the C headers that come with Zig, so the build
# does not depend on the C library's headers of the distribution (a build for the
# machine itself failed on them: 'gnu/stubs-32.h' not found).
if [[ -z "$TARGET" && "$(uname -s)" == Linux ]]; then
    case "$(uname -m)" in
        x86_64)        TARGET=x86_64-linux-musl ;;
        aarch64|arm64) TARGET=aarch64-linux-musl ;;
    esac
fi

case "$TARGET" in
    *windows*) EXECUTABLE=sigma.exe ;;
    *)         EXECUTABLE=sigma ;;
esac

# Builds one profile into the directory $1; $2 is full or forth2012.
build() {
    local arguments=(build -Doptimize=fast --prefix "$1")
    if [[ -n "$TARGET" ]]; then
        arguments+=("-Dtarget=$TARGET")
    else
        # Without a target, Zig builds for the CPU of this machine, and the program
        # can then fail on a CPU without the same instructions (AVX-512, for example).
        arguments+=(-Dcpu=baseline)
    fi
    if [[ "$2" == forth2012 ]]; then
        arguments+=(-Dgraphics=false -Daudio=false -Dextension=false)
    fi
    # zig's own output goes to standard error, so that only the paths are printed.
    zig "${arguments[@]}" >&2
    if [[ ! -f "$1/bin/$EXECUTABLE" ]]; then
        echo "Error: the release executable was not produced: $1/bin/$EXECUTABLE" >&2
        exit 1
    fi
    printf '%s\n' "$1/bin/$EXECUTABLE"
}

if [[ "$VARIANT" != forth2012 ]]; then build "$OUTPUT" full; fi
if [[ "$VARIANT" != full ]]; then build "$FORTH2012_OUTPUT" forth2012; fi
