# Sacred Bill Tracker Learning Center RC Transfer

Release candidate: `release/learning-center-1.0.23-rc`

Version/build: `1.0.23 (61)`

Baseline commit: `2f7e19454497556224799320a7a54c50706a8de5`

## Purpose

This package contains the isolated Learning Center release candidate prepared for verification on a more capable Mac. It intentionally excludes local build products, DerivedData, temporary compiler diagnostics, private credentials, and unrelated development artifacts.

## Expected Validation Mac

- Apple Silicon Mac with at least 16 GB RAM.
- At least 40 GB free storage.
- Xcode 27.0 build 27A266a or a stable compatible Xcode.
- Installed iOS Simulator runtime compatible with the project.
- Healthy CoreSimulator service.

## Verification Commands

From the unpacked package root:

```bash
xcodebuild -resolvePackageDependencies \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker

xcodebuild build \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

For targeted Learning Center UI tests, use an available bootable iOS simulator and run only the Learning Center UI test class:

```bash
xcodebuild test \
  -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=<SIMULATOR_NAME>' \
  -only-testing:SacredBillTrackerUITests/HelpCenterUITests
```

## Production Safety Checks

- Confirm `SBT_UI_TEST_OPEN_HELP_CENTER` appears only in `#if DEBUG` app code and the UI test target.
- Confirm Release build settings do not include the `DEBUG` compilation condition.
- Confirm no SAVELIFE production enablement, subscription price changes, Supabase deployment changes, or website changes are present.
- Confirm app and widget targets remain `MARKETING_VERSION = 1.0.23` and `CURRENT_PROJECT_VERSION = 61`.

## Reference Files

- `LEARNING_CENTER_RELEASE_CHANGE_MANIFEST.md`
- `LEARNING_CENTER_RC_FINAL_REPORT.md`
- `APP_STORE_RELEASE_NOTES_LEARNING_CENTER_1.0.23.md`
