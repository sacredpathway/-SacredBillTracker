#!/bin/bash
# Sacred Bill Tracker — device-deployment verification.
# Runs entirely on the host Mac. Writes everything to
# verify_device_deployment.txt next to this script.

set -u

cd "$(dirname "$0")"
OUT="verify_device_deployment.txt"
: > "$OUT"

log() { echo "$@" | tee -a "$OUT"; }
sep() { log ""; log "============================================================"; log "$1"; log "============================================================"; }

PROJ="SacredBillTracker.xcodeproj"
SCHEME="SacredBillTracker"
BUNDLE="com.sacredbilltracker.app"

sep "1. xcodebuild + Xcode version"
xcodebuild -version  2>&1 | tee -a "$OUT"

sep "2. Connected iOS devices (xctrace)"
# Filter to "iPhone" / "iPad" and skip simulators.
xcrun xctrace list devices 2>&1 | awk '
  /^== Devices ==/ { mode="dev"; print; next }
  /^== Simulators ==/ { mode="sim"; next }
  mode=="dev" && NF>0 { print }
' | tee -a "$OUT"

sep "3. Connected iOS devices (devicectl, if available)"
if xcrun --find devicectl >/dev/null 2>&1; then
  xcrun devicectl list devices 2>&1 | tee -a "$OUT"
else
  log "devicectl not available in this Xcode."
fi

sep "4. Build settings — signing + entitlements (Debug, iOS device)"
xcodebuild -showBuildSettings \
  -project "$PROJ" \
  -scheme  "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS' 2>&1 \
  | grep -E "DEVELOPMENT_TEAM|PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE|CODE_SIGN_ENTITLEMENTS|IPHONEOS_DEPLOYMENT_TARGET|MARKETING_VERSION|CURRENT_PROJECT_VERSION|TARGETED_DEVICE_FAMILY|EXPANDED_CODE_SIGN_IDENTITY" \
  | sort -u | tee -a "$OUT"

sep "5. Debug build for simulator (sanity)"
xcodebuild build \
  -project "$PROJ" \
  -scheme  "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -quiet 2>&1 | tail -20 | tee -a "$OUT"
SIM_DEBUG=${PIPESTATUS[0]}
log "Debug-simulator exit: $SIM_DEBUG"

sep "6. Release build for simulator"
xcodebuild build \
  -project "$PROJ" \
  -scheme  "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -quiet 2>&1 | tail -20 | tee -a "$OUT"
SIM_RELEASE=${PIPESTATUS[0]}
log "Release-simulator exit: $SIM_RELEASE"

sep "7. Debug build for generic iOS device (signing test)"
xcodebuild build \
  -project "$PROJ" \
  -scheme  "$SCHEME" \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic 2>&1 | tail -40 | tee -a "$OUT"
DEV_DEBUG=${PIPESTATUS[0]}
log "Device-Debug exit: $DEV_DEBUG"

sep "8. Summary"
log "Debug   (simulator): $([[ $SIM_DEBUG    -eq 0 ]] && echo PASS || echo FAIL)"
log "Release (simulator): $([[ $SIM_RELEASE  -eq 0 ]] && echo PASS || echo FAIL)"
log "Debug   (iOS device): $([[ $DEV_DEBUG   -eq 0 ]] && echo PASS || echo FAIL)"
log "Bundle ID: $BUNDLE"
log "Team:      DCCSGYD5A4"
log "Deployment: iOS 17.0"

log ""
log "[Done]"
