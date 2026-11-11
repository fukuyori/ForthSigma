#!/usr/bin/env bash
# build-zip.sh
# Build the FORTH/Sigma ZIPs for Linux and macOS, as build-zip.ps1 does for
# Windows.
#
# Makes the ZIPs that .github/workflows/release.yml makes,
# sigma-VERSION-PLATFORM.zip and sigma-VERSION-PLATFORM-nofloat.zip. Each holds
# one folder with the executable, LICENSE, THIRD_PARTY_NOTICES.md and README.md;
# the ZIP of the version with the floating-point words also holds the example
# programs (examples/*.fs), some of which need those words.
#
# Usage:
#   ./scripts/build-zip.sh [options]
#
# Options:
#   --platform PLATFORM   linux-x86_64, linux-arm32, linux-arm64, macos-arm64,
#                         or all (default: the platform of this machine)
#   --version X.Y.Z       Version in the names of the ZIPs (default: VERSION)
#   --output DIR          Where the ZIPs go (default: dist/zip)
#   --variant VARIANT     both, float or nofloat (default: both)
#
# Zig builds for the other platforms too, so any of them can be made on any
# machine. The macOS executable is not signed with a Developer ID; the signed
# installer package comes from sign-and-notarize-macos.sh.
#
# Output:
#   <output>/sigma-<version>-<platform>[-nofloat].zip, each followed by its SHA256

set -euo pipefail

PLATFORM=""
VERSION=""
OUTPUT=""
VARIANT=both

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform|--version|--output|--variant)
            if [[ $# -lt 2 ]]; then
                echo "Error: $1 needs a value." >&2
                exit 1
            fi
            case "$1" in
                --platform) PLATFORM="$2" ;;
                --version)  VERSION="$2" ;;
                --output)   OUTPUT="$2" ;;
                --variant)  VARIANT="$2" ;;
            esac
            shift 2 ;;
        -h|--help) sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

case "$OUTPUT" in
    "") ;;
    /*) ;;
    *)  OUTPUT="$PWD/$OUTPUT" ;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ -z "$OUTPUT" ]]; then OUTPUT="$ROOT/dist/zip"; fi

if [[ -z "$VERSION" ]]; then
    VERSION=$(tr -d '\r\n' < VERSION)
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid version '$VERSION'. Expected MAJOR.MINOR.PATCH." >&2
    exit 1
fi
case "$VARIANT" in
    both)    VARIANTS="float nofloat" ;;
    float)   VARIANTS="float" ;;
    nofloat) VARIANTS="nofloat" ;;
    *) echo "Error: invalid --variant '$VARIANT'. Expected both, float or nofloat." >&2; exit 1 ;;
esac

# The platform of this machine, when it is one that has a ZIP.
if [[ -z "$PLATFORM" ]]; then
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)             PLATFORM=linux-x86_64 ;;
        Linux-aarch64)            PLATFORM=linux-arm64 ;;
        Linux-armv6l|Linux-armv7l) PLATFORM=linux-arm32 ;;
        Darwin-arm64)             PLATFORM=macos-arm64 ;;
        *) echo "Error: no ZIP is made for $(uname -s) $(uname -m). Give --platform." >&2; exit 1 ;;
    esac
fi
if [[ "$PLATFORM" == all ]]; then
    PLATFORMS="linux-x86_64 linux-arm32 linux-arm64 macos-arm64"
else
    PLATFORMS="$PLATFORM"
fi

# The same targets as the CI build.
target_of() {
    case "$1" in
        linux-x86_64) echo x86_64-linux-musl ;;
        linux-arm32)  echo arm-linux-musleabihf ;;
        linux-arm64)  echo aarch64-linux-musl ;;
        macos-arm64)  echo aarch64-macos ;;
        *) echo "Error: invalid --platform '$1'. Expected linux-x86_64, linux-arm32, linux-arm64, macos-arm64 or all." >&2; exit 1 ;;
    esac
}
for platform in $PLATFORMS; do
    target_of "$platform" > /dev/null
done

for tool in zig zip; do
    if ! command -v "$tool" > /dev/null; then
        echo "Error: $tool not found in PATH." >&2
        exit 1
    fi
done
if command -v sha256sum > /dev/null; then
    sha256() { sha256sum "$1" | cut -d ' ' -f 1; }
else
    sha256() { shasum -a 256 "$1" | cut -d ' ' -f 1; }
fi
if ! ls examples/*.fs > /dev/null 2>&1; then
    echo "Error: no example programs in $ROOT/examples" >&2
    exit 1
fi

mkdir -p "$OUTPUT"
STAGING="$ROOT/.work/zip-staging"
for platform in $PLATFORMS; do
    target=$(target_of "$platform")
    release="$ROOT/.work/zip-release-$platform"
    nofloat_release="$ROOT/.work/zip-release-$platform-nofloat"
    "$ROOT/scripts/build-release.sh" --output "$release" --nofloat-output "$nofloat_release" \
        --target "$target" --variant "$VARIANT" > /dev/null

    for variant in $VARIANTS; do
        if [[ "$variant" == float ]]; then
            name="sigma-$VERSION-$platform"
            directory="$release"
        else
            name="sigma-$VERSION-$platform-nofloat"
            directory="$nofloat_release"
        fi

        # The ZIP holds one folder with the executable and the same documents as
        # the CI ZIP.
        rm -rf "$STAGING"
        mkdir -p "$STAGING/$name"
        cp "$directory/bin/sigma" LICENSE THIRD_PARTY_NOTICES.md README.md "$STAGING/$name/"
        # The example programs go in a folder examples, as README.md names them
        # (sigma examples/demo.fs).
        if [[ "$variant" == float ]]; then
            mkdir "$STAGING/$name/examples"
            cp examples/*.fs "$STAGING/$name/examples/"
        fi

        rm -f "$OUTPUT/$name.zip"
        (cd "$STAGING" && zip -q -r "$OUTPUT/$name.zip" "$name")
        rm -rf "$STAGING"

        printf '%s\n' "$OUTPUT/$name.zip"
        printf 'SHA256 %s\n' "$(sha256 "$OUTPUT/$name.zip")"
    done
done
