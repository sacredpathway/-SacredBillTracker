#!/bin/bash
# install_v109_on_device.command
# Builds SacredBillTracker (Debug) for the first connected iPhone,
# installs the .app, launches it, and tees the full transcript to a log.
#
# Requires:
#   - iPhone connected via USB or Wi-Fi paired
#   - Developer Mode enabled on the iPhone (Settings → Privacy & Security
#     → Developer Mode → ON), device trusted
#   - Xcode 15+ command-line tools

set -o pipefail
cd "$(dirname "$0")"

LOG="install_v109_on_device.log"
echo "==> SacredBillTracker v1.0.9 — device install" | tee "$LOG"
echo "    Log: $(pwd)/$LOG" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 1. Find the first connected iPhone ─────────────────────────
echo "==> Listing connected devices…" | tee -a "$LOG"
DEVICE_JSON=$(xcrun devicectl list devices --json-output - 2>&1)
echo "$DEVICE_JSON" >> "$LOG"

DEVICE_ID=$(echo "$DEVICE_JSON" \
    | /usr/bin/python3 -c '
import json, sys
raw = sys.stdin.read()
# devicectl --json-output - also prints a human table BEFORE the JSON
# blob on stdout. Trim everything up to the first "{" and parse from
# there. The last "}" guards against any trailing text.
i = raw.find("{")
j = raw.rfind("}")
if i < 0 or j < 0:
    sys.exit(0)
try:
    data = json.loads(raw[i:j+1])
except Exception:
    sys.exit(0)
# Accept any paired iOS device with a real transport (wired/wireless).
# tunnelState may be "disconnected" until devicectl opens the tunnel
# — that is NOT the same as the device being unavailable.
for d in data.get("result", {}).get("devices", []):
    plat = d.get("hardwareProperties", {}).get("platform", "")
    cp = d.get("connectionProperties", {})
    pairing = cp.get("pairingState", "")
    transport = cp.get("transportType") or ""
    if plat == "iOS" and pairing == "paired" and transport in ("wired", "wireless"):
        print(d.get("identifier", ""))
        break
')

if [ -z "$DEVICE_ID" ]; then
    echo "" | tee -a "$LOG"
    echo "❌ No connected iPhone found via devicectl." | tee -a "$LOG"
    echo "   • Plug the device in via USB" | tee -a "$LOG"
    echo "   • Unlock it, tap Trust if prompted" | tee -a "$LOG"
    echo "   • Settings → Privacy & Security → Developer Mode → ON, then reboot" | tee -a "$LOG"
    echo "   • Re-run this script" | tee -a "$LOG"
    exit 2
fi
echo "    Target device id: $DEVICE_ID" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 2. Build for the connected device ──────────────────────────
DERIVED="$(pwd)/build_v109_device"
echo "==> Building (Debug, destination id=$DEVICE_ID)…" | tee -a "$LOG"
xcodebuild \
    -project SacredBillTracker.xcodeproj \
    -scheme SacredBillTracker \
    -configuration Debug \
    -destination "id=$DEVICE_ID" \
    -derivedDataPath "$DERIVED" \
    -allowProvisioningUpdates \
    -quiet \
    clean build 2>&1 | tee -a "$LOG"
BUILD_STATUS=${PIPESTATUS[0]}

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "" | tee -a "$LOG"
    echo "❌ BUILD FAILED — first errors:" | tee -a "$LOG"
    grep -nE "error:" "$LOG" | head -10 | tee -a "$LOG"
    exit 3
fi
echo "✅ BUILD SUCCEEDED" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 3. Locate the .app ─────────────────────────────────────────
APP_PATH=$(find "$DERIVED/Build/Products" -maxdepth 4 -type d -name "SacredBillTracker.app" | head -1)
if [ -z "$APP_PATH" ]; then
    echo "❌ Could not locate SacredBillTracker.app under $DERIVED" | tee -a "$LOG"
    exit 4
fi
echo "    .app: $APP_PATH" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 4. Install on the device ───────────────────────────────────
echo "==> Installing on device $DEVICE_ID…" | tee -a "$LOG"
xcrun devicectl device install app \
    --device "$DEVICE_ID" \
    "$APP_PATH" 2>&1 | tee -a "$LOG"
INSTALL_STATUS=${PIPESTATUS[0]}

if [ "$INSTALL_STATUS" -ne 0 ]; then
    echo "❌ INSTALL FAILED" | tee -a "$LOG"
    exit 5
fi
echo "✅ INSTALL SUCCEEDED" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# ── 5. Launch the app ──────────────────────────────────────────
echo "==> Launching com.sacredbilltracker.app…" | tee -a "$LOG"
xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --terminate-existing \
    com.sacredbilltracker.app 2>&1 | tee -a "$LOG"
LAUNCH_STATUS=${PIPESTATUS[0]}

if [ "$LAUNCH_STATUS" -ne 0 ]; then
    echo "❌ LAUNCH FAILED" | tee -a "$LOG"
    exit 6
fi
echo "✅ LAUNCH SUCCEEDED — open the Reports tab on the iPhone to verify." | tee -a "$LOG"
exit 0
