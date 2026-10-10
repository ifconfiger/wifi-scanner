#!/usr/bin/env bash
# Package build/WiFi-Scanner.app into a drag-to-install disk image.
# Usage: tools/make_dmg.sh [output.dmg]   (default: build/WiFi-Scanner.dmg)
# When SIGN_IDENTITY names a Developer ID certificate the image itself is signed too, as notarization expects.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/WiFi-Scanner.app
OUT="${1:-build/WiFi-Scanner.dmg}"
[[ -d "$APP" ]] || { echo "$APP not found; run ./build.sh first" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/WiFi-Scanner.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$OUT"
hdiutil create -volname WiFi-Scanner -srcfolder "$STAGE" -fs HFS+ \
  -format UDZO -imagekey zlib-level=9 "$OUT" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT"
  codesign --verify --strict "$OUT"
fi
hdiutil verify "$OUT" >/dev/null
echo "Done: $OUT"
