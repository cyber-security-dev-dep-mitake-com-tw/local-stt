#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.localstt.team}"
APP_NAME="LocalSTT"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION-team-unsigned.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/localstt-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

cd "$ROOT"
swift build -c release --product LocalSTT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/LocalSTT" "$APP/Contents/MacOS/LocalSTT"
cp "Config/Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"

# Ad-hoc signing provides integrity but no Developer ID identity or notarization.
codesign --force --deep --sign - --entitlements "Config/LocalSTT.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
rm -f "$DMG" "$DMG.sha256"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --force --sign - "$DMG"
shasum -a 256 "$DMG" | tee "$DMG.sha256"
echo "Created $DMG"
