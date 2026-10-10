#!/usr/bin/env bash
# Build and package WiFi-Scanner.app (location authorization requires running as an .app bundle)
set -euo pipefail
cd "$(dirname "$0")"

# The macOS 26+ SDK implements SwiftUI's @State as a macro whose plugin ships only with Xcode,
# so prefer Xcode when the active developer directory is the Command Line Tools
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == *CommandLineTools* && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# CONFIG=debug builds a debug binary (used to test the updater locally)
CONFIG="${CONFIG:-release}"
swift build -c "$CONFIG"

APP=build/WiFi-Scanner.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c "$CONFIG" --show-bin-path)/WiFiScanner" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns Resources/oui.tsv "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Release CI injects the version through the VERSION environment variable (e.g. 1.2.3)
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
fi

# Signing: ad-hoc by default (enough to run locally). When CI sets SIGN_IDENTITY to a Developer ID
# certificate, enable the Hardened Runtime and a secure timestamp as notarization requires
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - --entitlements Resources/WiFi-Scanner.entitlements "$APP"
else
  codesign --force --options runtime --timestamp \
    --entitlements Resources/WiFi-Scanner.entitlements \
    --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

echo "Done: $APP"
echo "Run:  open $APP"
