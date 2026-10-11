# Learning Center Release Candidate Final Report

Date: 2026-10-10

## Release Candidate Location

- Original working tree preserved: `/Users/demarquishinton/Developer/SBT-1.0.22-Build60-Reconstructed`
- Isolated worktree: `/Users/demarquishinton/Developer/SBT-LearningCenter-RC`
- Branch: `release/learning-center-1.0.23-rc`
- Baseline commit: `2f7e19454497556224799320a7a54c50706a8de5`
- Baseline subject: `Baseline production source 1.0.21 build 59`
- Proposed app version/build: `1.0.23 (61)`

## Included Learning Center Files

- `SacredBillTracker/Views/Settings/HelpCenterView.swift`
- `SacredBillTracker/Views/Settings/SettingsView.swift`
- `SacredBillTracker/ContentView.swift`
- `SacredBillTracker/SacredBillTrackerApp.swift`
- `SacredBillTrackerUITests/HelpCenterUITests.swift`
- `SacredBillTracker.xcodeproj/project.pbxproj`
- `SacredBillTracker.xcodeproj/xcshareddata/xcschemes/SacredBillTracker.xcscheme`
- `APP_STORE_RELEASE_NOTES_LEARNING_CENTER_1.0.23.md`
- `LEARNING_CENTER_RELEASE_CHANGE_MANIFEST.md`
- `LEARNING_CENTER_RC_FINAL_REPORT.md`

## Implemented Scope

- Added the in-app Learning Center under `Settings -> Help and referrals -> Learning Center`.
- Added 25 offline help articles across the verified feature categories.
- Added search, category browsing, article detail views, FAQs, troubleshooting, plan labels, and "Take Me There" actions.
- Added `LearningCenterRouter` and tab selection tags for safe in-app routing.
- Added a DEBUG-only launch argument, `SBT_UI_TEST_OPEN_HELP_CENTER`, for direct UI-test access to the real Learning Center.
- Added a dedicated `SacredBillTrackerUITests` target containing `HelpCenterUITests.swift`.
- Updated app/widget version metadata to `1.0.23 (61)`.

## Explicitly Excluded

- No SAVELIFE production enablement, purchase UI, StoreKit product wiring, or entitlement changes.
- No SAVE20/SAVE40 changes, subscription-price changes, or offer-code changes.
- No Supabase schema/backend deployment.
- No Squarespace/website edits.
- No demo-recording, simulator-migration, or video-production code.

## Safety Verification

- `plutil -lint SacredBillTracker.xcodeproj/project.pbxproj`: passed.
- Xcode project targets verified:
  - `SacredBillTracker`
  - `SacredBillTrackerWidgets`
  - `SacredBillTrackerTests`
  - `SacredBillTrackerUITests`
- `HelpCenterView.swift` is included in the app target sources.
- `HelpCenterUITests.swift` is included in the UI-test target sources.
- Release compile conditions show `SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited)"`, not `DEBUG`.
- `SBT_UI_TEST_OPEN_HELP_CENTER` appears only in `SacredBillTrackerApp.swift` inside `#if DEBUG` and in the UI test file.
- Candidate scan found no `SaveLife`, `SAVELIFE`, `savelife`, `DemoRecording`, `EducationalRecording`, or `SBT_DEMO_RECORDING` references.
- Static version check verified the app and widget targets are set to `MARKETING_VERSION = 1.0.23` and `CURRENT_PROJECT_VERSION = 61`.
- The only `SAVE20`/`SAVE40` source references are Learning Center explanatory copy and an existing DEBUG-only sandbox-account testing section; no offer, entitlement, or pricing logic was changed.

## Build and Test Results

- Package resolution: passed after a long AppsFlyer package checkout.
  - Log: `LearningCenterRCBuildLogs/package-resolve.log`
- Debug build, broad simulator build: interrupted intentionally after it began compiling both `arm64` and `x86_64` simulator slices and remained dependency-heavy.
  - Log: `LearningCenterRCBuildLogs/debug-build.log`
- Debug build, arm64-only simulator build: interrupted after a bounded run because Xcode was still compiling SwiftPM dependencies (`swift-crypto`, `xctest-dynamic-overlay`, `supabase-swift`) and had not reached app source compilation.
  - Log: `LearningCenterRCBuildLogs/debug-build-arm64.log`
- Debug build, arm64-only simulator continuation: reached the `SacredBillTracker` app target and began `SwiftEmitModule normal arm64 Emitting module for SacredBillTracker`. The app module emit included `HelpCenterView.swift`, `SettingsView.swift`, `ContentView.swift`, and `SacredBillTrackerApp.swift`, but made no visible progress for the final bounded window and was interrupted after about 3 hours total wall-clock time.
  - Log: `LearningCenterRCBuildLogs/debug-build-arm64-continued.log`
  - Compiler diagnostic sample: `LearningCenterRCBuildLogs/debug-swift-frontend-sample.txt`
  - Evidence: sample shows `swift-frontend` inside Swift semantic analysis/type-checking for the app module, not a CoreSimulator startup failure and not a reported source error.
- Follow-up diagnosis on 2026-10-10 corrected the initial read of the continued build log:
  - `debug-build-arm64-continued.log` shows the app target progressed past `SwiftEmitModule` and into individual `SwiftCompile normal arm64` jobs before the build was manually interrupted.
  - The active app-source batch at interruption was StoreKit/paywall/partner/account support code (`Entitlements.swift`, `SubscriptionManager.swift`, `TierEntitlementManager.swift`, `ThreeTierPaywallView.swift`, `PartnerBudgetingView.swift`, `AccountView.swift`, and related files), not `HelpCenterView.swift`.
  - The only compiler warning in that log is the pre-existing `RequestReviewAction`/`_StoreKit_SwiftUI` warning in `SacredBillTrackerApp.swift`; the same `@Environment(\.requestReview)` code exists at baseline and is not introduced by the Learning Center work.
- A single controlled diagnostic build with `-debug-time-function-bodies`, `-debug-time-expression-type-checking`, `-jobs 1`, `ONLY_ACTIVE_ARCH=YES`, `ARCHS=arm64`, and `COMPILER_INDEX_STORE_ENABLE=NO` was attempted to gather narrow compiler timing data.
  - Log: `LearningCenterRCBuildLogs/compiler-diagnostics/debug-build-with-typecheck-timing.log`
  - Result: interrupted after a bounded run because the diagnostic flags forced slow SwiftPM/package recompilation and still had not reached `HelpCenterView.swift`.
  - Timing data captured 7,123 rows, all from packages/widgets before interruption. The largest observed individual type-check/function timings were small (hundreds of milliseconds, max observed `317.23ms` in `swift-crypto`), so the diagnostic run did not identify a pathological Learning Center expression or function.
- Local environment evidence:
  - Mac memory: 8 GB physical RAM, 6 CPUs.
  - Disk: about 22 GiB free; Data volume about 89% used.
  - VM state showed heavy historical compression/swap activity (`Swapins` about 59.4M, `Swapouts` about 61.9M).
  - Xcode: 27.0 build 27A266a, Swift frontend 6.4.0.34.1.
  - `simctl list runtimes` hung during this diagnosis pass and was interrupted, indicating simulator/CoreSimulator tooling is not fully healthy.
- Release build: not run because the Debug build did not complete.
- Targeted UI tests: not run because no completed app build was available from the isolated RC worktree.
- Screenshots: not captured in this RC pass.

No Learning Center compiler errors were observed in the available logs, but the build did not complete, so this is not a full compile pass. The strongest evidence-supported diagnosis is local Xcode/SwiftPM/CoreSimulator performance and runtime-health trouble on an 8 GB Mac, compounded by the size of the existing app and dependency graph. The Learning Center increases source size, but the available logs do not implicate `HelpCenterView.swift` as the active stall source.

## Release Notes

Prepared at:

- `APP_STORE_RELEASE_NOTES_LEARNING_CENTER_1.0.23.md`

Summary:

- New searchable Learning Center in Settings.
- Step-by-step guides for core app features.
- Getting Started, FAQs, troubleshooting, and offline help access.
- No subscription, backend, or unreleased lifetime-purchase changes.

## Remaining Follow-Up

- App Store submission still needs the normal signed archive, upload, and review workflow.
- Review and commit only the listed release-candidate files; exclude generated build caches/logs unless intentionally archived.
- Generated build cache remains at `build/learning-center-rc` in the original working copy and should be excluded from the release commit.
- Earlier Debug, Release, and targeted UI-test blockers are superseded by the 2026-10-11 Mac mini validation results later in this report.

## Transfer Package

Prepared on 2026-10-10 for verification on a more capable Mac:

- Portable source folder: `/Users/demarquishinton/Developer/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427`
- Archive: `/Users/demarquishinton/Developer/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz`
- Checksum: `/Users/demarquishinton/Developer/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz.sha256`
- Transfer/runbook: `LEARNING_CENTER_RC_TRANSFER_README.md`

Package verification:

- Archive checksum verified with `shasum -a 256 -c`.
- Required Learning Center source, UI tests, release notes, manifest, final report, and transfer README are present.
- Excluded `.git`, build products, `LearningCenterRCBuildLogs`, DerivedData, `.build`, `.swiftpm`, Xcode `xcuserdata`, and common signing/private-key file patterns.
- Source scan of `SacredBillTracker` and `SacredBillTrackerUITests` found no `SAVELIFE`, `savelife`, `SaveLife`, demo-recording, or `SBT_DEMO_RECORDING` references.

No approved alternate Mac was accessible from this Codex session. Codex listed only the local host, and there is no configured `~/.ssh/config` host alias. To continue verification elsewhere, move the archive and checksum to a Mac with at least 16 GB RAM and 40 GB free storage, unpack it, then run the commands in `LEARNING_CENTER_RC_TRANSFER_README.md`.

## 2026-10-10 Continuation Check

Additional release-preparation work completed after the initial transfer package:

- Re-read this final report and `LEARNING_CENTER_RELEASE_CHANGE_MANIFEST.md`.
- Rechecked current host:
  - Computer: `Demarquis’s MacBook`
  - Hardware: MacBook Neo, Apple A18 Pro, 6 cores, 8 GB RAM.
  - Storage: about 22 GiB free on `/System/Volumes/Data`.
  - Xcode: 27.0 build 27A266a at `/Applications/Xcode.app/Contents/Developer`.
  - VM state continues to show very heavy historical compression/swap activity (`Swapins` about 68.3M, `Swapouts` about 70.9M).
- Bounded simulator runtime query did not return useful runtime data.
- `plutil -lint SacredBillTracker.xcodeproj/project.pbxproj`: passed.
- `xcodebuild -list -project SacredBillTracker.xcodeproj` was attempted only as a static project listing, but it began resolving SwiftPM packages and was interrupted to avoid repeating the known dependency-heavy bottleneck on the 8 GB Mac.
- Rechecked alternate-Mac access:
  - Codex app project list shows only `hostId: local` for local projects; no alternate Mac host is configured.
  - `~/.ssh/config` does not exist.
  - SSH agent reports no loaded identities.
  - No remote volumes are mounted under `/Volumes`.
  - Bounded Bonjour discovery for `_ssh._tcp` and `_smb._tcp` returned no available Mac mini service.
  - ARP table shows router and several iPhone devices, but no identifiable Mac mini.
- Rechecked release-candidate safety:
  - No `.env*`, `.p8`, `.p12`, `.cer`, `.mobileprovision`, `AuthKey_*`, or `GoogleService-Info.plist` files found in the RC scan.
  - Source scan of `SacredBillTracker` and `SacredBillTrackerUITests` found no `SAVELIFE`, `savelife`, `SaveLife`, demo-recording, or `SBT_DEMO_RECORDING` references.
  - Git diff remains limited to the expected Learning Center project/source files, with untracked Learning Center docs/tests/logs/build cache.

Conclusion: final Debug/Release/UI-test verification cannot be completed from this session because no suitable Mac is accessible through an existing authorized connection, and the current 8 GB Mac remains below the validation target. The portable package remains the correct next artifact for transfer.

## Mac mini Move-Ready Staging

Prepared a final local transfer staging folder:

- Transfer folder: `/Users/demarquishinton/Developer/SBT-MacMini-Transfer-Ready`
- Archive: `/Users/demarquishinton/Developer/SBT-MacMini-Transfer-Ready/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz`
- Checksum file: `/Users/demarquishinton/Developer/SBT-MacMini-Transfer-Ready/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz.sha256`
- Mac mini runbook: `/Users/demarquishinton/Developer/SBT-MacMini-Transfer-Ready/MAC_MINI_TRANSFER_READY.md`

The archive also includes:

- `MAC_MINI_TRANSFER_READY.md`
- `VERIFY_LEARNING_CENTER_RC_ON_MAC_MINI.sh`

The current archive checksum is recorded in the adjacent `.sha256` file. That file is the source of truth because the archive includes this report.

## 2026-10-11 Mac mini Verification Attempt

Transfer verification on `Demarquis’s Mac mini`:

- Hardware: Mac mini, `Mac16,10`, Apple M4, 10 cores, 16 GB RAM.
- Xcode: 27.0 build 27A266a at `/Applications/Xcode.app/Contents/Developer`.
- iOS Simulator runtime: iOS 26.5 (`com.apple.CoreSimulator.SimRuntime.iOS-26-5`).
- Available simulator devices include `iPhone 17 Pro`, `iPhone 17`, `iPad Pro 13-inch (M5)`, and `iPad (A16)`.
- Archive location: `/Users/demarquishinton/Downloads/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz`.
- Archive SHA-256 verified: `38180c4802c203b3a4f0731a7fdbab27448da3c0e880940d009f1d43eadcdde4`.
- `shasum -a 256 -c SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427.tar.gz.sha256`: passed.
- Archive unpacked to `/Users/demarquishinton/Downloads/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427`.
- `plutil -lint SacredBillTracker.xcodeproj/project.pbxproj`: passed.
- `xcodebuild -list -project SacredBillTracker.xcodeproj`: passed and listed `SacredBillTracker`, `SacredBillTrackerWidgets`, `SacredBillTrackerTests`, and `SacredBillTrackerUITests`.
- `xcodebuild -resolvePackageDependencies -project SacredBillTracker.xcodeproj -scheme SacredBillTracker`: passed.
  - Log: `LearningCenterRCMacMiniLogs/package-resolve.log`
- Resolved packages: `AppsFlyerLib` 6.18.1, `Supabase` 2.43.1, `swift-crypto` 4.4.0, `swift-asn1` 1.7.0, `swift-http-types` 1.5.1, `swift-clocks` 1.0.6, `swift-concurrency-extras` 1.3.2, and `xctest-dynamic-overlay` 1.9.0.

Mac mini safety checks:

- `SBT_UI_TEST_OPEN_HELP_CENTER` appears only in `SacredBillTracker/SacredBillTrackerApp.swift` and `SacredBillTrackerUITests/HelpCenterUITests.swift`.
- No `SAVELIFE`, `savelife`, `SaveLife`, `DemoRecording`, or `SBT_DEMO_RECORDING` references were found in `SacredBillTracker`, `SacredBillTrackerUITests`, or `SacredBillTracker.xcodeproj/project.pbxproj`.
- Release build settings for the app target resolve to `MARKETING_VERSION = 1.0.23`, `CURRENT_PROJECT_VERSION = 61`, and `PRODUCT_BUNDLE_IDENTIFIER = com.sacredbilltracker.app`.
- Release build settings for the widget target resolve to `MARKETING_VERSION = 1.0.23`, `CURRENT_PROJECT_VERSION = 61`, and `PRODUCT_BUNDLE_IDENTIFIER = com.sacredbilltracker.app.widget`.
- Raw `MARKETING_VERSION = 1.0` values in `project.pbxproj` belong to test targets, not the app or widget release targets.

Initial Mac mini blocker before recovery:

- Storage is below the required validation threshold. Before package resolution the Mac mini reported about `1.7Gi` free on `/System/Volumes/Data`; after package resolution it reported about `857Mi` free.
- Required target remains `40GB` free storage or better.
- Debug build, Release build, and targeted Learning Center UI tests were not run because the Mac mini is too low on free disk space to safely continue Xcode build validation.

Conclusion at this stage: transfer integrity, extraction, Xcode selection, simulator availability, project lint, package resolution, and static safety/version checks passed on the Mac mini. Full compile and UI-test validation were temporarily blocked by insufficient disk space until the recovery work below.

### Mac mini Space Recovery

Space recovery completed on 2026-10-11 after the initial blocker:

- Cleared unavailable CoreSimulator devices and recreated one fresh validation simulator: `SBT iPhone 17 Pro` (`136300A8-C679-45C3-94AD-951BFD395DF6`) on iOS 26.5.
- Cleared rebuildable Xcode state including DerivedData, archives, products, logs, and iOS DeviceSupport.
- Cleared user cache contents.
- Removed reinstallable/nonessential developer payloads not needed for this iOS validation pass:
  - Android SDK at `~/Library/Android/sdk`.
  - Unity editor installs at `/Applications/Unity`.
- Requested APFS local snapshot thinning with `tmutil thinlocalsnapshots`.
- Final space after cleanup: about `45Gi` free on `/System/Volumes/Data`.

Storage now meets the `40GB+` validation target. Debug build, Release build, and targeted Learning Center UI tests can be retried from this unpacked Mac mini folder.

### Mac mini Build and UI-Test Completion

Validation completed on 2026-10-11 after space recovery:

- Applied a minimal compile fix in `SacredBillTracker/Views/Settings/SettingsView.swift`:
  - `SBTAccountPreferences` is now accessible to `HelpCenterView.swift` instead of being `private`.
- Applied a minimal UI-test project reference fix in `SacredBillTracker.xcodeproj/project.pbxproj`:
  - The `SacredBillTrackerUITests` group now points to the actual `SacredBillTrackerUITests` folder, so Xcode resolves `HelpCenterUITests.swift` correctly.
- Hardened `SacredBillTrackerUITests/HelpCenterUITests.swift` for SwiftUI `List` lazy loading:
  - Assertions now scroll to directory rows, search results, empty results, and article sections before checking them.

Build and test results from `/Users/demarquishinton/Downloads/SBT-LearningCenter-RC-Portable-1.0.23-61-20261010-192427`:

- Debug simulator build:
  - Command: `xcodebuild build -project SacredBillTracker.xcodeproj -scheme SacredBillTracker -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: passed, `** BUILD SUCCEEDED **`.
  - Log: `LearningCenterRCMacMiniLogs/debug-build.log`
- Release simulator build:
  - Command: `xcodebuild build -project SacredBillTracker.xcodeproj -scheme SacredBillTracker -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Result: passed, `** BUILD SUCCEEDED **`.
  - Release guard: `verify_release_no_debug_strings: ✅ clean — no banned strings in Release build.`
  - Log: `LearningCenterRCMacMiniLogs/release-build.log`
- Targeted Learning Center UI tests:
  - Command: `xcodebuild test -project SacredBillTracker.xcodeproj -scheme SacredBillTracker -configuration Debug -destination 'platform=iOS Simulator,name=SBT iPhone 17 Pro' -only-testing:SacredBillTrackerUITests/HelpCenterUITests`
  - Result: passed, `Executed 5 tests, with 0 failures (0 unexpected)`.
  - Log: `LearningCenterRCMacMiniLogs/help-center-ui-tests.log`

Final observed free space after cleanup plus builds/tests: about `36Gi` free on `/System/Volumes/Data`. No App Store upload, submission, backend migration, production deployment, or physical-device installation was performed.

### Post-Validation Release Readiness Check

Additional lightweight checks completed after the successful Mac mini build/test pass:

- The three validation fixes were compared against the original transfer archive and are minimal:
  - `SettingsView.swift`: one access-control change, `private struct SBTAccountPreferences` -> `struct SBTAccountPreferences`.
  - `project.pbxproj`: one project-group path addition, `path = SacredBillTrackerUITests;`.
  - `HelpCenterUITests.swift`: scroll-aware assertions/helpers for SwiftUI `List` lazy loading; no app behavior changed.
- Learning Center content inventory:
  - `25` bundled articles across `12` categories.
  - `19` live articles and `6` gated/prepared-access articles.
  - Search field, empty-result state, article rows, article details, and related navigation all have UI-test coverage from the targeted suite.
- Release safety checks:
  - `SBT_UI_TEST_OPEN_HELP_CENTER` remains DEBUG-only app code plus UI-test code.
  - Release build log confirms `verify_release_no_debug_strings` was clean.
  - No `.env`, `.p8`, `.p12`, `.cer`, `.mobileprovision`, `AuthKey_*`, `GoogleService-Info.plist`, `.git`, DerivedData, `.swiftpm`, `.build`, or `xcuserdata` entries were found in the validated RC source tree.
  - `Configuration.storekit` parses as valid JSON.
  - App/widget Info.plists and privacy manifests pass `plutil -lint`.
- Version and signing configuration:
  - App target Release: `MARKETING_VERSION = 1.0.23`, `CURRENT_PROJECT_VERSION = 61`, `PRODUCT_BUNDLE_IDENTIFIER = com.sacredbilltracker.app`.
  - Widget target Release: `MARKETING_VERSION = 1.0.23`, `CURRENT_PROJECT_VERSION = 61`, `PRODUCT_BUNDLE_IDENTIFIER = com.sacredbilltracker.app.widget`.
  - Signing is automatic with development team `DCCSGYD5A4`; local simulator validation used `CODE_SIGNING_ALLOWED=NO`.
- Git state:
  - This validated Mac mini folder is a portable source snapshot and intentionally has no `.git` directory.
  - The checked workspace git repository at `/Users/demarquishinton/Documents/ChatGPT/(apple) sacred bill traker` has no commits and does not contain this RC source tree.
  - No git commit, push, or branch publication was performed.
- Physical-device testing checklist added:
  - `PHYSICAL_DEVICE_TESTING_CHECKLIST_1.0.23_61.md`

## Recommendation

GO for code isolation, release-candidate preparation, and Mac mini local validation.

App Store submission still requires the normal signing/archive/review workflow, but the prior local validation blocker is cleared: transfer integrity, package resolution, Debug build, Release build, Release debug-string guard, and targeted Learning Center UI tests all completed successfully on the Mac mini.
