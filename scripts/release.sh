#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\([^"]*\)"/\1/p' project.yml | head -n 1)}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Usage: $0 VERSION" >&2
  exit 2
fi

APP="$ROOT_DIR/dist/ChargeCap.app"
DMG="$ROOT_DIR/dist/ChargeCap-${VERSION}.dmg"
IDENTITY="${CHARGE_CAP_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -n 1)}"

if [[ -z "$IDENTITY" ]]; then
  echo "No Developer ID Application certificate found." >&2
  exit 1
fi

if [[ "$(sed -n 's/^[[:space:]]*MARKETING_VERSION: "\([^"]*\)"/\1/p' project.yml | head -n 1)" != "$VERSION" ]]; then
  echo "project.yml MARKETING_VERSION does not match $VERSION." >&2
  exit 1
fi

echo "Building ChargeCap $VERSION with: $IDENTITY"
make clean
make build SIGN_IDENTITY="$IDENTITY"

codesign --verify --deep --strict --verbose=2 "$APP"
for component in \
  "$APP/Contents/MacOS/ChargeCapHelper" \
  "$APP/Contents/PlugIns/ChargeCapControl.appex" \
  "$APP"; do
  signature="$(codesign -dvvv "$component" 2>&1)"
  if ! grep -q '^Timestamp=' <<<"$signature"; then
    echo "Missing secure timestamp: $component" >&2
    exit 1
  fi
done

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/ChargeCap.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "ChargeCap $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

KEY_PATH="${APPLE_API_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${APPLE_API_KEY_ID:-CJ28PU73CA}.p8}"
KEY_ID="${APPLE_API_KEY_ID:-$(basename "$KEY_PATH" | sed -n 's/^AuthKey_\(.*\)\.p8$/\1/p')}"
ISSUER="${APPLE_API_ISSUER:-}"

if [[ "${CHARGE_CAP_SKIP_NOTARIZATION:-0}" == "1" ]]; then
  echo "Skipping notarization because CHARGE_CAP_SKIP_NOTARIZATION=1." >&2
else
  if [[ ! -f "$KEY_PATH" || -z "$KEY_ID" || -z "$ISSUER" ]]; then
    echo "Missing notarization credentials. Set APPLE_API_KEY_PATH, APPLE_API_KEY_ID and APPLE_API_ISSUER." >&2
    echo "Set CHARGE_CAP_SKIP_NOTARIZATION=1 only for local testing." >&2
    exit 1
  fi

  echo "Submitting for notarization..."
  xcrun notarytool submit "$DMG" \
    --key "$KEY_PATH" \
    --key-id "$KEY_ID" \
    --issuer "$ISSUER" \
    --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "Built $DMG"
echo "SHA-256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
