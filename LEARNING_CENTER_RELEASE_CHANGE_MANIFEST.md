# Sacred Bill Tracker Learning Center Release Candidate Manifest

Branch: `release/learning-center-1.0.23-rc`
Worktree: `/Users/demarquishinton/Developer/SBT-LearningCenter-RC`
Baseline commit: `2f7e19454497556224799320a7a54c50706a8de5` (`Baseline production source 1.0.21 build 59`)
Proposed release version: `1.0.23`
Proposed build: `61`

## Included Changes

- Adds the offline Sacred Bill Tracker Learning Center at `Settings -> Help and referrals -> Learning Center`.
- Adds searchable feature-directory content, categories, articles, FAQs, troubleshooting, feature availability labels, and contextual "Take Me There" actions.
- Adds a lightweight `LearningCenterRouter` to support safe tab navigation from Learning Center articles.
- Adds DEBUG-only Help Center launch routing for UI tests.
- Adds a dedicated `SacredBillTrackerUITests` target with targeted Learning Center UI tests.
- Updates version metadata to `1.0.23 (61)` for the app and widget extension.

## File Manifest

- `SacredBillTracker/Views/Settings/HelpCenterView.swift`
- `SacredBillTracker/Views/Settings/SettingsView.swift`
- `SacredBillTracker/ContentView.swift`
- `SacredBillTracker/SacredBillTrackerApp.swift`
- `SacredBillTrackerUITests/HelpCenterUITests.swift`
- `SacredBillTracker.xcodeproj/project.pbxproj`
- `SacredBillTracker.xcodeproj/xcshareddata/xcschemes/SacredBillTracker.xcscheme`
- `LEARNING_CENTER_RELEASE_CHANGE_MANIFEST.md`
- `APP_STORE_RELEASE_NOTES_LEARNING_CENTER_1.0.23.md`
- `LEARNING_CENTER_RC_TRANSFER_README.md`

## Explicitly Excluded

- SAVELIFE production enablement, purchase UI, entitlement changes, StoreKit product changes, and backend deployment.
- SAVE20/SAVE40 offer changes, subscription price changes, and entitlement-plan changes.
- Supabase schema or production backend changes.
- Squarespace website edits.
- Demo recording, simulator migration, video-production infrastructure, and generated video assets.

## Production Safety Checks

- The direct Help Center test route uses the launch argument `SBT_UI_TEST_OPEN_HELP_CENTER`.
- That launch argument is wrapped in `#if DEBUG` in `SacredBillTrackerApp.swift`.
- Release build settings keep `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited)"`, so the DEBUG-only route is not compiled into Release.
- Candidate scan found no `SaveLife`, `SAVELIFE`, `savelife`, `DemoRecording`, `EducationalRecording`, or `SBT_DEMO_RECORDING` references after cleanup.

## Build/Test Evidence

- Package resolution log: `build/learning-center-rc/package-resolve.log`
- Debug build log: `build/learning-center-rc/debug-build.log`
- Release build log: `build/learning-center-rc/release-build.log`
- Targeted UI test log: `build/learning-center-rc/help-center-ui-tests.log`

Final results are recorded in `LEARNING_CENTER_RC_FINAL_REPORT.md`.
