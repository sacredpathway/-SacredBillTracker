# Mac mini Transfer Ready: Sacred Bill Tracker Learning Center RC

Release candidate: `release/learning-center-1.0.23-rc`

Version/build: `1.0.23 (61)`

Archive:

- `SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz`
- `SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz.sha256`

## Before Unpacking on the Mac mini

```bash
shasum -a 256 -c SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz.sha256
tar -xzf SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz
cd SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427
```

## Verify the Mac mini

```bash
system_profiler SPHardwareDataType | awk -F': ' '/Model Name|Model Identifier|Chip|Total Number of Cores|Memory/ {print $1 ": " $2}'
df -h / /System/Volumes/Data
xcodebuild -version
xcode-select -p
xcrun simctl list runtimes
```

Target validation host:

- 16 GB RAM or better.
- 40 GB free storage or better.
- Xcode installed and selected.
- iOS Simulator runtime installed and healthy.

## Verification Commands

```bash
mkdir -p LearningCenterRCMacMiniLogs

xcodebuild -resolvePackageDependencies \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  > LearningCenterRCMacMiniLogs/package-resolve.log 2>&1

xcodebuild build \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  > LearningCenterRCMacMiniLogs/debug-build.log 2>&1

xcodebuild build \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  > LearningCenterRCMacMiniLogs/release-build.log 2>&1
```

Run targeted Learning Center UI tests against an available simulator:

```bash
xcrun simctl list devices available

xcodebuild test \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>' \
  -only-testing:SacredBillTrackerUITests/HelpCenterUITests \
  > LearningCenterRCMacMiniLogs/help-center-ui-tests.log 2>&1
```

## Required Safety Checks

```bash
plutil -lint SacredBillTracker.xcodeproj/project.pbxproj
rg -n 'SBT_UI_TEST_OPEN_HELP_CENTER|SAVELIFE|savelife|SaveLife|DemoRecording|SBT_DEMO_RECORDING' SacredBillTracker SacredBillTrackerUITests SacredBillTracker.xcodeproj/project.pbxproj
rg -n 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|SWIFT_ACTIVE_COMPILATION_CONDITIONS' SacredBillTracker.xcodeproj/project.pbxproj
```

Expected:

- `SBT_UI_TEST_OPEN_HELP_CENTER` appears only in DEBUG app code and UI tests.
- No SAVELIFE or demo-recording production activation appears in source.
- App/widget targets are `MARKETING_VERSION = 1.0.23` and `CURRENT_PROJECT_VERSION = 61`.
- Release build settings do not include `DEBUG`.

## Stop Point

Do not upload, submit, publish, deploy, push, or install on physical devices. Stop after local Mac mini verification and update `LEARNING_CENTER_RC_FINAL_REPORT.md` with results.
