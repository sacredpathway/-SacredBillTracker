#!/bin/zsh
set -euo pipefail

LOG_DIR="LearningCenterRCMacMiniLogs"
mkdir -p "$LOG_DIR"

echo "== Machine =="
system_profiler SPHardwareDataType | awk -F': ' '/Model Name|Model Identifier|Chip|Total Number of Cores|Memory/ {print $1 ": " $2}'
df -h / /System/Volumes/Data || true
xcodebuild -version
xcode-select -p

echo "== Checksum/project safety =="
plutil -lint SacredBillTracker.xcodeproj/project.pbxproj
rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|SWIFT_ACTIVE_COMPILATION_CONDITIONS' SacredBillTracker.xcodeproj/project.pbxproj
rg -n 'SBT_UI_TEST_OPEN_HELP_CENTER|SAVELIFE|savelife|SaveLife|DemoRecording|SBT_DEMO_RECORDING' SacredBillTracker SacredBillTrackerUITests SacredBillTracker.xcodeproj/project.pbxproj || true

echo "== Package resolution =="
xcodebuild -resolvePackageDependencies \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  > "$LOG_DIR/package-resolve.log" 2>&1

echo "== Debug build =="
xcodebuild build \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  > "$LOG_DIR/debug-build.log" 2>&1

echo "== Release build =="
xcodebuild build \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  > "$LOG_DIR/release-build.log" 2>&1

echo "== Available simulators =="
xcrun simctl list devices available | tee "$LOG_DIR/available-simulators.txt"

cat <<'EOF'

Build verification complete.

Next: run the targeted UI test with a simulator name from LearningCenterRCMacMiniLogs/available-simulators.txt:

xcodebuild test \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>' \
  -only-testing:SacredBillTrackerUITests/HelpCenterUITests \
  > LearningCenterRCMacMiniLogs/help-center-ui-tests.log 2>&1

Do not upload, submit, publish, deploy, push, or install on a physical device.
EOF
