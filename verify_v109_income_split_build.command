#!/bin/bash
# verify_v109_income_split_build.command
# Builds SacredBillTracker against the iOS Simulator destination to
# confirm the v1.0.9 Business/Personal income-split changes compile.
#
# Double-click in Finder to run, or:
#   bash "verify_v109_income_split_build.command"

set -o pipefail
cd "$(dirname "$0")"

LOG="build_v109_income_split.log"
echo "==> Building SacredBillTracker (Debug, iOS Simulator)…"
echo "    Log: $(pwd)/$LOG"

xcodebuild \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  -quiet \
  clean build 2>&1 | tee "$LOG"

STATUS=${PIPESTATUS[0]}
echo ""
if [ "$STATUS" -eq 0 ]; then
  echo "✅ BUILD SUCCEEDED — v1.0.9 income split compiles."
else
  echo "❌ BUILD FAILED — see $LOG for the first error."
  grep -nE "error:|note:" "$LOG" | head -20
fi
exit $STATUS
