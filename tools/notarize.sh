#!/usr/bin/env bash
# Submit a file to Apple's notary service, wait for the verdict and staple the ticket.
# Usage: tools/notarize.sh <file-to-submit> <path-to-staple>
#   app: tools/notarize.sh notarize.zip build/WiFi-Viewer.app   (an .app must be submitted as a zip)
#   dmg: tools/notarize.sh build/WiFi-Viewer.dmg build/WiFi-Viewer.dmg
# Credentials (App Store Connect API key): APPLE_NOTARY_KEY (.p8 contents or its base64),
# APPLE_NOTARY_KEY_ID, APPLE_NOTARY_ISSUER.
set -euo pipefail

SUBMIT="$1"
TARGET="$2"

KEY_DIR="$(mktemp -d)"
KEY="$KEY_DIR/AuthKey.p8"
trap 'rm -rf "$KEY_DIR"' EXIT
if [[ "$APPLE_NOTARY_KEY" == *"BEGIN PRIVATE KEY"* ]]; then
  printf '%s\n' "$APPLE_NOTARY_KEY" > "$KEY"
else
  echo "$APPLE_NOTARY_KEY" | base64 --decode > "$KEY"
fi
AUTH=(--key "$KEY" --key-id "$APPLE_NOTARY_KEY_ID" --issuer "$APPLE_NOTARY_ISSUER")

RESULT="$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait --timeout 30m --output-format json)"
echo "$RESULT"
ID="$(echo "$RESULT" | jq -r .id)"
STATUS="$(echo "$RESULT" | jq -r .status)"
# Always print the log for troubleshooting (Accepted submissions may still carry warnings)
xcrun notarytool log "$ID" "${AUTH[@]}" || true
if [[ "$STATUS" != "Accepted" ]]; then
  echo "Notarization failed: $STATUS" >&2
  exit 1
fi

# Staple the ticket so Gatekeeper passes even offline
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
