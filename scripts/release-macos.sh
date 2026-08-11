#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
OUTPUT_DIR="$PROJECT_DIR/.build/package"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Packaging/Info.plist")
ARCH=arm64
SIGN_IDENTITY=${SIGN_IDENTITY:-"Developer ID Application: zhou wei (A5L4GGX82X)"}
NOTARY_PROFILE=${NOTARY_PROFILE:-claracore-notary}
FINAL_APP="$OUTPUT_DIR/croc.app"
FINAL_ZIP="$OUTPUT_DIR/croc-$VERSION-$ARCH.zip"
FINAL_DMG="$OUTPUT_DIR/croc-$VERSION-$ARCH.dmg"
CHECKSUMS="$OUTPUT_DIR/SHA256SUMS.txt"

cd "$PROJECT_DIR"

SIGN_IDENTITY="$SIGN_IDENTITY" "$SCRIPT_DIR/package-app.sh"

codesign --verify --deep --strict --verbose=2 "$FINAL_APP"
xcrun notarytool submit "$FINAL_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_APP"
xcrun stapler validate "$FINAL_APP"

if [[ -e "$FINAL_ZIP" ]]; then
    rm -f "$FINAL_ZIP"
fi
ditto -c -k --sequesterRsrc --keepParent "$FINAL_APP" "$FINAL_ZIP"

RELEASE_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/croc-release.XXXXXX")
trap 'rm -rf "$RELEASE_TEMP"' EXIT
DMG_STAGE="$RELEASE_TEMP/croc"
install -d "$DMG_STAGE"
ditto "$FINAL_APP" "$DMG_STAGE/croc.app"
ln -s /Applications "$DMG_STAGE/Applications"

if [[ -e "$FINAL_DMG" ]]; then
    rm -f "$FINAL_DMG"
fi
hdiutil create -volname "croc" -srcfolder "$DMG_STAGE" -ov -format UDZO "$FINAL_DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$FINAL_DMG"
codesign --verify --verbose=2 "$FINAL_DMG"
xcrun notarytool submit "$FINAL_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_DMG"
xcrun stapler validate "$FINAL_DMG"

spctl --assess --type execute --verbose=4 "$FINAL_APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$FINAL_DMG"
hdiutil verify "$FINAL_DMG"

cd "$OUTPUT_DIR"
shasum -a 256 "${FINAL_ZIP:t}" "${FINAL_DMG:t}" > "${CHECKSUMS:t}"

print "$FINAL_APP"
print "$FINAL_ZIP"
print "$FINAL_DMG"
print "$CHECKSUMS"
