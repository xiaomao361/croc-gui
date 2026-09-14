#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
if [[ -z ${CROC_CORE:-} ]]; then
    CROC_CORE=$("$SCRIPT_DIR/fetch-croc-core.sh")
fi
SIGN_IDENTITY=${SIGN_IDENTITY:--}
OUTPUT_DIR=${CROC_PACKAGE_OUTPUT_DIR:-"$PROJECT_DIR/.build/package"}
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Packaging/Info.plist")
FINAL_APP="$OUTPUT_DIR/croc.app"
FINAL_ZIP="$OUTPUT_DIR/croc-$VERSION-arm64.zip"

if [[ ! -x "$CROC_CORE" ]]; then
    print -u2 "croc core is not executable: $CROC_CORE"
    exit 2
fi

CORE_VERSION=$("$CROC_CORE" --version)
if [[ "$CORE_VERSION" != "croc version 10.7.0" ]]; then
    print -u2 "unexpected croc core version: $CORE_VERSION"
    exit 2
fi

cd "$PROJECT_DIR"
swift build -c release

PACKAGE_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/croc-package.XXXXXX")
trap 'rm -rf "$PACKAGE_TEMP"' EXIT

APP="$PACKAGE_TEMP/croc.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICONSET="$PACKAGE_TEMP/AppIcon.iconset"

install -d "$MACOS" "$RESOURCES" "$ICONSET" "$OUTPUT_DIR"
install -m 755 ".build/release/CrocGUI" "$MACOS/CrocGUI"
install -m 755 "$CROC_CORE" "$RESOURCES/croc"
install -m 644 "ThirdPartyNotices/croc-NOTICE.txt" "$RESOURCES/croc-NOTICE.txt"
install -m 644 "ThirdPartyNotices/croc-LICENSE.txt" "$RESOURCES/croc-LICENSE.txt"
install -m 644 "Packaging/Info.plist" "$CONTENTS/Info.plist"
print -n "APPL????" > "$CONTENTS/PkgInfo"

swift "Tools/GenerateAppIcon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$RESOURCES/croc"
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$RESOURCES/croc"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

if [[ -e "$FINAL_APP" ]]; then
    rm -rf "$FINAL_APP"
fi
if [[ -e "$FINAL_ZIP" ]]; then
    rm -f "$FINAL_ZIP"
fi
mv "$APP" "$FINAL_APP"
ditto -c -k --sequesterRsrc --keepParent "$FINAL_APP" "$FINAL_ZIP"

print "$FINAL_APP"
print "$FINAL_ZIP"
