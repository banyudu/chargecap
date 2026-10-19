#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/ChargeCap.app"
DESTINATION_APP="/Applications/ChargeCap.app"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Build the app first with: make build" >&2
  exit 1
fi

if [[ ! -w /Applications ]]; then
  echo "/Applications is not writable by this account. Copy ChargeCap.app there from Finder, then reopen it." >&2
  exit 1
fi

rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"
codesign --verify --deep --strict "$DESTINATION_APP"

echo "Installed: $DESTINATION_APP"
echo "Open it with: open '$DESTINATION_APP'"
