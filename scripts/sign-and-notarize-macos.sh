#!/usr/bin/env bash
# sign-and-notarize-macos.sh
# Build, code-sign, notarize and staple the FORTH/Sigma macOS .pkg installer.
#
# Builds sigma with 'zig build -Doptimize=fast' for each architecture, joins the
# builds into one executable with lipo, signs it (Developer ID Application,
# hardened runtime), wraps it into a signed .pkg (Developer ID Installer) that
# installs /usr/local/bin/sigma and /usr/local/share/doc/sigma, submits the .pkg
# for notarization and staples the ticket.
#
# Usage:
#   ./scripts/sign-and-notarize-macos.sh [options]
#
# Options:
#   --version X.Y.Z          Version of the package (default: VERSION)
#   --arch ARCH              universal, arm64 or x86_64 (default: universal)
#   --variant VARIANT        float, nofloat or both (default: float); nofloat
#                            leaves out the floating-point words (-Dfloat=false)
#   --identity ID            "Developer ID Application: ..." identity
#                            (default: $SIGMA_SIGN_IDENTITY, else auto-detect)
#   --installer-identity ID  "Developer ID Installer: ..." identity
#                            (default: $SIGMA_INSTALLER_IDENTITY, else auto-detect)
#   --profile NAME           notarytool keychain profile
#                            (default: $SIGMA_NOTARY_PROFILE, else auto-detect
#                            by probing common profile names)
#   --apple-id ID            Apple ID          (default: $SIGMA_APPLE_ID)
#   --team-id ID             Team ID           (default: $SIGMA_TEAM_ID)
#   --password PW            App-specific pass (default: $SIGMA_APP_PASSWORD)
#   --skip-notarize          Sign only, skip notarization and stapling
#
# Credentials: either store a keychain profile once:
#   xcrun notarytool store-credentials notarytool --apple-id <id> --team-id <team> --password <app-pw>
# (profiles named 'notarytool', 'sigma' or 'notary' are auto-detected; other
# names need --profile), or pass --apple-id/--team-id/--password directly.
#
# The oldest macOS the program runs on is $SIGMA_MACOS_MIN (default: 11.0).
#
# Output:
#   dist/pkg/sigma-<version>-macos-<arch>[-nofloat].pkg  (signed, notarized, stapled)

set -euo pipefail
# Keep an absolute script path so --help also works from scripts/ or another cwd.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
cd "$SCRIPT_DIR/.."

VERSION=""
ARCH=universal
VARIANT=float
IDENTITY="${SIGMA_SIGN_IDENTITY:-}"
INSTALLER_IDENTITY="${SIGMA_INSTALLER_IDENTITY:-}"
PROFILE="${SIGMA_NOTARY_PROFILE:-}"
APPLE_ID="${SIGMA_APPLE_ID:-}"
TEAM_ID="${SIGMA_TEAM_ID:-}"
APP_PASSWORD="${SIGMA_APP_PASSWORD:-}"
MACOS_MIN="${SIGMA_MACOS_MIN:-11.0}"
SKIP_NOTARIZE=0
PKG_IDENTIFIER=io.github.fukuyori.sigma
OUTPUT_DIR=dist/pkg
WORK_DIR=.work/pkg

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|--arch|--variant|--identity|--installer-identity|--profile|--apple-id|--team-id|--password)
            if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
                echo "Error: $1 needs a value." >&2
                exit 1
            fi
            case "$1" in
                --version)            VERSION="$2" ;;
                --arch)               ARCH="$2" ;;
                --variant)            VARIANT="$2" ;;
                --identity)           IDENTITY="$2" ;;
                --installer-identity) INSTALLER_IDENTITY="$2" ;;
                --profile)            PROFILE="$2" ;;
                --apple-id)           APPLE_ID="$2" ;;
                --team-id)            TEAM_ID="$2" ;;
                --password)           APP_PASSWORD="$2" ;;
            esac
            shift 2 ;;
        --skip-notarize)      SKIP_NOTARIZE=1; shift ;;
        -h|--help)            sed -n '2,/^set -euo pipefail/{ /^set -euo pipefail/d; p; }' "$SCRIPT_PATH" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Error: unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "=== FORTH/Sigma macOS Sign & Notarize ==="

if [[ -z "$VERSION" ]]; then
    VERSION=$(tr -d '\r\n' < VERSION)
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid version '$VERSION'. Expected MAJOR.MINOR.PATCH." >&2
    exit 1
fi
if ! [[ "$MACOS_MIN" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    echo "Error: invalid SIGMA_MACOS_MIN '$MACOS_MIN'. Expected a macOS version such as 11.0." >&2
    exit 1
fi
case "$ARCH" in
    universal) ZIG_ARCHS="aarch64 x86_64"; HOST_ARCHS="arm64,x86_64" ;;
    arm64)     ZIG_ARCHS="aarch64";        HOST_ARCHS="arm64" ;;
    x86_64)    ZIG_ARCHS="x86_64";         HOST_ARCHS="x86_64" ;;
    *) echo "Error: invalid --arch '$ARCH'. Expected universal, arm64 or x86_64." >&2; exit 1 ;;
esac
case "$VARIANT" in
    float)   VARIANTS="float" ;;
    nofloat) VARIANTS="nofloat" ;;
    both)    VARIANTS="float nofloat" ;;
    *) echo "Error: invalid --variant '$VARIANT'. Expected float, nofloat or both." >&2; exit 1 ;;
esac
required_tools=(zig lipo pkgbuild productbuild codesign pkgutil xattr shasum)
if [[ -z "$IDENTITY" || -z "$INSTALLER_IDENTITY" ]]; then required_tools+=(security); fi
if [[ $SKIP_NOTARIZE -eq 0 ]]; then required_tools+=(xcrun spctl /usr/bin/python3); fi
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" > /dev/null; then
        echo "Error: $tool not found in PATH." >&2
        exit 1
    fi
done
echo "Version: $VERSION ($ARCH, $VARIANT, macOS $MACOS_MIN or later)"

# ── Resolve signing identities ───────────────────────────────────────────
if [[ -z "$IDENTITY" ]]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
    if [[ -z "$IDENTITY" ]]; then
        echo "Error: no 'Developer ID Application' identity found in keychain." >&2
        echo "Specify one with --identity or \$SIGMA_SIGN_IDENTITY." >&2
        exit 1
    fi
    echo "Auto-detected identity: $IDENTITY"
fi

if [[ -z "$INSTALLER_IDENTITY" ]]; then
    INSTALLER_IDENTITY=$(security find-identity -v 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)
    if [[ -z "$INSTALLER_IDENTITY" ]]; then
        echo "Error: no 'Developer ID Installer' identity found in keychain." >&2
        echo "Specify one with --installer-identity or \$SIGMA_INSTALLER_IDENTITY." >&2
        exit 1
    fi
    echo "Auto-detected installer identity: $INSTALLER_IDENTITY"
fi

# ── Notary credential check (before doing any work) ──────────────────────
notary_args=()
if [[ $SKIP_NOTARIZE -eq 0 ]]; then
    if [[ -z "$PROFILE" && -z "$APPLE_ID" && -z "$TEAM_ID" && -z "$APP_PASSWORD" ]]; then
        # Only select a profile when the credential check succeeds. Network or
        # authentication failures must not be treated as evidence of a valid profile.
        for candidate in notarytool sigma notary; do
            if xcrun notarytool history --keychain-profile "$candidate" > /dev/null 2>&1; then
                PROFILE="$candidate"
                echo "Auto-detected notary profile: $PROFILE"
                break
            fi
        done
    fi
    if [[ -n "$PROFILE" ]]; then
        notary_args=(--keychain-profile "$PROFILE")
    elif [[ -n "$APPLE_ID" && -n "$TEAM_ID" && -n "$APP_PASSWORD" ]]; then
        notary_args=(--apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD")
    else
        echo "Error: no notarization credentials." >&2
        echo "Use --profile NAME (see 'xcrun notarytool store-credentials')" >&2
        echo "or --apple-id/--team-id/--password." >&2
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
PKG_FILES=()
PKG_ROOT=""
cleanup() {
    if [[ -n "$PKG_ROOT" ]]; then rm -rf "$PKG_ROOT"; fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for this_variant in $VARIANTS; do
    if [[ "$this_variant" == float ]]; then
        FLOAT=true; SUFFIX=""
    else
        FLOAT=false; SUFFIX="-nofloat"
    fi
    NAME="sigma-$VERSION-macos-$ARCH$SUFFIX"
    echo ""
    echo "=== $NAME ==="

    # ── 1. Build each architecture and join them ─────────────────────────
    echo "Building ..."
    slices=()
    for zig_arch in $ZIG_ARCHS; do
        prefix="$WORK_DIR/build-$zig_arch$SUFFIX"
        rm -rf "$prefix"
        # An explicit target builds for the baseline CPU of that architecture.
        zig build -Doptimize=fast "-Dfloat=$FLOAT" \
            "-Dtarget=$zig_arch-macos.$MACOS_MIN" --prefix "$prefix"
        slices+=("$prefix/bin/sigma")
    done
    BINARY="$WORK_DIR/sigma$SUFFIX"
    lipo -create "${slices[@]}" -output "$BINARY"
    echo "Binary:  $BINARY ($(lipo -archs "$BINARY"))"

    # ── 2. Code-sign the binary (hardened runtime) ───────────────────────
    echo "Signing binary ..."
    codesign --force --timestamp --options runtime \
        --identifier "$PKG_IDENTIFIER" --sign "$IDENTITY" "$BINARY"
    codesign --verify --strict --verbose=2 "$BINARY"
    # Run a slice for this host; a package for the other architecture cannot be
    # smoke-tested here without an emulator. Both the status and output must match.
    HOST_ARCH=$(uname -m)
    if [[ ",$HOST_ARCHS," == *",$HOST_ARCH,"* ]]; then
        if ! smoke_output=$("$BINARY" -e '1 2 + . BYE') || [[ "$smoke_output" != "3 " ]]; then
            echo "Error: the signed binary does not run: $BINARY" >&2
            exit 1
        fi
    else
        echo "Skipping execution check: $HOST_ARCH is not in $HOST_ARCHS."
    fi
    echo "Signature OK"

    # ── 3. Build the signed .pkg ─────────────────────────────────────────
    echo "Building signed .pkg ..."
    PKG_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sigma-pkgroot.XXXXXX")
    mkdir -p "$PKG_ROOT/usr/local/bin" "$PKG_ROOT/usr/local/share/doc/sigma"
    cp -X "$BINARY" "$PKG_ROOT/usr/local/bin/sigma"
    cp -X LICENSE THIRD_PARTY_NOTICES.md README.md docs/USER_MANUAL.md \
        "$PKG_ROOT/usr/local/share/doc/sigma/"
    chmod 755 "$PKG_ROOT/usr/local/bin/sigma"
    chmod 644 "$PKG_ROOT/usr/local/share/doc/sigma/"*
    # Strip extended attributes so pkgbuild does not emit AppleDouble (._*) files
    xattr -cr "$PKG_ROOT"

    COMPONENT="$WORK_DIR/$NAME-component.pkg"
    rm -f "$COMPONENT"
    pkgbuild \
        --root "$PKG_ROOT" \
        --identifier "$PKG_IDENTIFIER" \
        --version "$VERSION" \
        --install-location / \
        --ownership recommended \
        "$COMPONENT"
    rm -rf "$PKG_ROOT"
    PKG_ROOT=""

    # The distribution adds the title, the license page and the system checks.
    RESOURCES="$WORK_DIR/resources"
    rm -rf "$RESOURCES"
    mkdir -p "$RESOURCES"
    cp -X LICENSE "$RESOURCES/LICENSE.txt"
    DISTRIBUTION="$WORK_DIR/distribution.xml"
    cat > "$DISTRIBUTION" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>FORTH/Σ $VERSION</title>
    <license file="LICENSE.txt"/>
    <options customize="never" require-scripts="false" hostArchitectures="$HOST_ARCHS"/>
    <domains enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions><os-version min="$MACOS_MIN"/></allowed-os-versions>
    </volume-check>
    <choices-outline><line choice="default"><line choice="$PKG_IDENTIFIER"/></line></choices-outline>
    <choice id="default"/>
    <choice id="$PKG_IDENTIFIER" visible="false"><pkg-ref id="$PKG_IDENTIFIER"/></choice>
    <pkg-ref id="$PKG_IDENTIFIER" version="$VERSION" onConclusion="none">$(basename "$COMPONENT")</pkg-ref>
</installer-gui-script>
EOF

    PKG_FILE="$OUTPUT_DIR/$NAME.pkg"
    rm -f "$PKG_FILE"
    productbuild \
        --distribution "$DISTRIBUTION" \
        --resources "$RESOURCES" \
        --package-path "$WORK_DIR" \
        --sign "$INSTALLER_IDENTITY" \
        --timestamp \
        "$PKG_FILE"
    pkgutil --check-signature "$PKG_FILE" | sed -n '1,3p'
    echo "Package: $PKG_FILE"

    # ── 4. Notarize and staple ───────────────────────────────────────────
    if [[ $SKIP_NOTARIZE -eq 1 ]]; then
        echo "Skipping notarization (--skip-notarize)"
    else
        echo "Submitting for notarization (this may take a few minutes) ..."
        result=$(xcrun notarytool submit "$PKG_FILE" "${notary_args[@]}" --wait --output-format json)
        status=$(echo "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
        submission_id=$(echo "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
        echo "Submission $submission_id: $status"
        if [[ "$status" != "Accepted" ]]; then
            echo "Notarization failed — fetching log:" >&2
            xcrun notarytool log "$submission_id" "${notary_args[@]}" >&2 || true
            exit 1
        fi

        echo "Stapling ticket ..."
        xcrun stapler staple "$PKG_FILE"

        echo "Verifying with Gatekeeper ..."
        spctl --assess --type install -vv "$PKG_FILE"
    fi
    PKG_FILES+=("$PKG_FILE")
done

echo ""
echo "=== Done ==="
for PKG_FILE in "${PKG_FILES[@]}"; do
    echo "Distribution package: $PKG_FILE ($(du -h "$PKG_FILE" | cut -f1))"
    echo "SHA256 $(shasum -a 256 "$PKG_FILE" | cut -d ' ' -f 1)"
done
