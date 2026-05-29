#!/bin/bash
# v1.7 — Income captions + share generator with income block.
# Builds Debug & Release for simulator; writes result to verify_v17_build.txt
set -u
cd "$(dirname "$0")"
OUT="verify_v17_build.txt"
: > "$OUT"
log() { echo "$@" | tee -a "$OUT"; }

PROJ="SacredBillTracker.xcodeproj"
SCHEME="SacredBillTracker"

log "=== xcodebuild build (Debug, simulator) ==="
xcodebuild build \
  -project "$PROJ" -scheme "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -quiet 2>&1 | tail -25 | tee -a "$OUT"
DBG=${PIPESTATUS[0]}
log "Debug exit: $DBG"
log ""

log "=== xcodebuild build (Release, simulator) ==="
xcodebuild build \
  -project "$PROJ" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -quiet 2>&1 | tail -25 | tee -a "$OUT"
REL=${PIPESTATUS[0]}
log "Release exit: $REL"
log ""

log "=== Summary ==="
log "Debug:   $([[ $DBG -eq 0 ]] && echo PASS || echo FAIL)"
log "Release: $([[ $REL -eq 0 ]] && echo PASS || echo FAIL)"
log "[Done]"
