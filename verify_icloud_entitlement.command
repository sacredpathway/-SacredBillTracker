#!/bin/bash
# Auto-verifies that the latest SacredBillTracker .xcarchive contains the
# iCloud key-value-store entitlement. Output is also written to
# verify_icloud_entitlement.txt next to this script.

set -uo pipefail

OUT="$(cd "$(dirname "$0")" && pwd)/verify_icloud_entitlement.txt"
: > "$OUT"

log() { echo "$@" | tee -a "$OUT"; }

ARCH_ROOT="$HOME/Library/Developer/Xcode/Archives"
log "Searching: $ARCH_ROOT"

LATEST_ARCHIVE="$(find "$ARCH_ROOT" -maxdepth 3 -name '*.xcarchive' \
  -exec stat -f '%m %N' {} \; 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2-)"

if [[ -z "${LATEST_ARCHIVE:-}" ]]; then
  log "FAIL: no .xcarchive found"
  exit 1
fi

log "Latest archive: $LATEST_ARCHIVE"

APP="$(find "$LATEST_ARCHIVE/Products/Applications" -maxdepth 2 -name '*.app' | head -1)"
if [[ -z "$APP" ]]; then
  log "FAIL: no .app inside archive Products"
  exit 2
fi

log "App bundle:    $APP"
log ""
log "=== codesign --display --entitlements - ==="
codesign --display --entitlements :- "$APP" 2>&1 | tee -a "$OUT"
log ""

if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "ubiquity-kvstore-identifier"; then
  log ""
  log "PASS: iCloud key-value store entitlement present"
  exit 0
else
  log ""
  log "FAIL: ubiquity-kvstore-identifier NOT found in archive"
  exit 3
fi
