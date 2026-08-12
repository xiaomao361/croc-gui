#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
CROC_VERSION=10.7.0
ARCH=arm64
ASSET="croc_v${CROC_VERSION}_macOS-ARM64.tar.gz"
ASSET_URL="https://github.com/schollz/croc/releases/download/v${CROC_VERSION}/${ASSET}"
ASSET_SHA256=be7a6716068277002d2fc30a5c37c8786641b40226b412ace20b44aebacd594c
BINARY_SHA256=5063bc6f029cb38936067e69d0851606c98705441aed6b2eb3406a337ea280eb
TARGET_DIR="$PROJECT_DIR/.build/vendor/croc/${CROC_VERSION}-${ARCH}"
TARGET="$TARGET_DIR/croc"

if [[ -x "$TARGET" ]]; then
    current_sha=$(shasum -a 256 "$TARGET" | awk '{print $1}')
    current_version=$("$TARGET" --version)
    if [[ "$current_sha" == "$BINARY_SHA256" && "$current_version" == "croc version ${CROC_VERSION}" ]]; then
        print "$TARGET"
        exit 0
    fi
fi

FETCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/croc-core.XXXXXX")
trap 'rm -rf "$FETCH_TEMP"' EXIT
ARCHIVE="$FETCH_TEMP/$ASSET"

curl --fail --location --retry 3 --output "$ARCHIVE" "$ASSET_URL"
actual_archive_sha=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
if [[ "$actual_archive_sha" != "$ASSET_SHA256" ]]; then
    print -u2 "croc archive checksum mismatch"
    exit 2
fi

tar -xzf "$ARCHIVE" -C "$FETCH_TEMP"
if [[ ! -x "$FETCH_TEMP/croc" ]]; then
    print -u2 "croc executable is missing from official archive"
    exit 2
fi

actual_binary_sha=$(shasum -a 256 "$FETCH_TEMP/croc" | awk '{print $1}')
if [[ "$actual_binary_sha" != "$BINARY_SHA256" ]]; then
    print -u2 "croc executable checksum mismatch"
    exit 2
fi

if [[ $(file "$FETCH_TEMP/croc") != *"Mach-O 64-bit executable arm64"* ]]; then
    print -u2 "croc executable is not a macOS arm64 binary"
    exit 2
fi

if [[ $("$FETCH_TEMP/croc" --version) != "croc version ${CROC_VERSION}" ]]; then
    print -u2 "croc executable reported an unexpected version"
    exit 2
fi

install -d "$TARGET_DIR"
install -m 755 "$FETCH_TEMP/croc" "$TARGET"
print "$TARGET"
