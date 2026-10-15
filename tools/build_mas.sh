#!/usr/bin/env bash
# Build the Mac App Store variant: compiled with -DAPPSTORE (no self-updater), sandboxed, and
# packaged as a signed .pkg for upload with Transporter.
#
# Local sandbox test (ad-hoc signed, no pkg):
#   tools/build_mas.sh
# Store upload:
#   SIGN_IDENTITY="Apple Distribution: …" \
#   INSTALLER_IDENTITY="3rd Party Mac Developer Installer: …" \
#   PROVISIONING_PROFILE=path/to/WiFi-Viewer.provisionprofile \
#   VERSION=1.2.3 BUILD_NUMBER=42 tools/build_mas.sh
# BUILD_NUMBER (CFBundleVersion) must grow with every upload.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/WiFi-Viewer.app
PKG=build/WiFi-Viewer.pkg
ENTITLEMENTS=Resources/WiFi-Viewer-MAS.entitlements
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

SWIFT_FLAGS="-Xswiftc -DAPPSTORE" SIGN_IDENTITY=- ./build.sh

if [[ -n "${PROVISIONING_PROFILE:-}" ]]; then
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
  # A store-signed app must claim the application identifier its profile grants
  PROFILE_PLIST=$(mktemp)
  security cms -D -i "$PROVISIONING_PROFILE" > "$PROFILE_PLIST"
  TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$PROFILE_PLIST")
  rm -f "$PROFILE_PLIST"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist")
  SIGNED_ENTITLEMENTS=$(mktemp -t wifi-viewer-entitlements)
  cp "$ENTITLEMENTS" "$SIGNED_ENTITLEMENTS"
  /usr/libexec/PlistBuddy \
    -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" \
    -c "Add :com.apple.developer.team-identifier string $TEAM_ID" \
    "$SIGNED_ENTITLEMENTS"
  ENTITLEMENTS="$SIGNED_ENTITLEMENTS"
elif [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "PROVISIONING_PROFILE is required when signing for the store" >&2
  exit 1
fi

codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -q app-sandbox

if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  rm -f "$PKG"
  productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
  echo "Done: $PKG (upload with Transporter)"
else
  echo "Done: $APP (sandboxed; set INSTALLER_IDENTITY to build the .pkg)"
fi
