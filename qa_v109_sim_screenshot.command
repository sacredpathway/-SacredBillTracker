#!/bin/bash
# qa_v109_sim_screenshot.command
# Builds SacredBillTracker for the iPhone Simulator, boots a sim,
# installs, launches, and saves a dashboard screenshot so the Sacred
# Daily Focus card change can be visually verified.

set -o pipefail
cd "$(dirname "$0")"

LOG="qa_v109_sim_screenshot.log"
SHOT="qa_v109_dashboard.png"
DERIVED="$(pwd)/build_v109_sim"

echo "==> v1.0.9 Sacred Daily Focus QA"        | tee "$LOG"
echo "    Log : $(pwd)/$LOG"                    | tee -a "$LOG"
echo "    Shot: $(pwd)/$SHOT"                   | tee -a "$LOG"

# 1. Pick a usable simulator UDID (iPhone 17 Pro Max if available, else first iPhone).
echo "==> Picking simulator…"                   | tee -a "$LOG"
SIM_UDID=$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
runtimes = data.get("devices", {})
pref = None
fallback = None
for runtime, devs in runtimes.items():
    if "iOS" not in runtime:
        continue
    for d in devs:
        name = d.get("name", "")
        if not d.get("isAvailable", False):
            continue
        if "iPhone" not in name:
            continue
        if pref is None and "17 Pro Max" in name:
            pref = d.get("udid")
        if fallback is None:
            fallback = d.get("udid")
print(pref or fallback or "")
')
if [ -z "$SIM_UDID" ]; then
    echo "❌ No available iPhone simulator." | tee -a "$LOG"
    exit 2
fi
echo "    UDID: $SIM_UDID" | tee -a "$LOG"

# 2. Boot the sim (idempotent).
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b >/dev/null 2>&1 || true

# 3. Build for that sim.
echo "==> Building for sim…" | tee -a "$LOG"
xcodebuild \
    -project SacredBillTracker.xcodeproj \
    -scheme SacredBillTracker \
    -configuration Debug \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -derivedDataPath "$DERIVED" \
    -quiet \
    clean build 2>&1 | tee -a "$LOG"
BUILD_STATUS=${PIPESTATUS[0]}
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "❌ BUILD FAILED — first errors:" | tee -a "$LOG"
    grep -nE "error:" "$LOG" | head -10 | tee -a "$LOG"
    exit 3
fi
echo "✅ BUILD SUCCEEDED" | tee -a "$LOG"

# 4. Install on the sim.
APP_PATH=$(find "$DERIVED/Build/Products" -maxdepth 4 -type d -name "SacredBillTracker.app" | head -1)
echo "    .app: $APP_PATH" | tee -a "$LOG"
xcrun simctl install "$SIM_UDID" "$APP_PATH" 2>&1 | tee -a "$LOG"
xcrun simctl launch "$SIM_UDID" com.sacredbilltracker.app 2>&1 | tee -a "$LOG"

# 5. Give the dashboard time to render.
sleep 4

# 6. Screenshot.
xcrun simctl io "$SIM_UDID" screenshot "$SHOT"
if [ -f "$SHOT" ]; then
    echo "✅ Screenshot saved: $(pwd)/$SHOT" | tee -a "$LOG"
else
    echo "❌ Screenshot not produced" | tee -a "$LOG"
    exit 4
fi
