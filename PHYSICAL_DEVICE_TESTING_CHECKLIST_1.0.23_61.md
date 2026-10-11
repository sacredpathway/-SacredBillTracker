# Sacred Bill Tracker 1.0.23 (61) Physical-Device Testing Checklist

Use this checklist after the Mac mini simulator validation checkpoint. Do not run production backend migrations or App Store Connect uploads as part of this checklist unless separately approved.

## Prerequisites

- Use the validated RC source folder or the updated validated archive created from it.
- Open `SacredBillTracker.xcodeproj` in Xcode 27.0 or a compatible stable Xcode.
- Confirm the selected scheme is `SacredBillTracker`.
- Confirm app target version/build resolves to `1.0.23 (61)`.
- Confirm widget target version/build resolves to `1.0.23 (61)`.
- Confirm signing uses team `DCCSGYD5A4` and automatic signing, or choose the correct production signing team/profile if different.
- Use a real iPhone/iPad on a supported iOS version and trusted by the Mac.

## Install And Launch

- Build and run the app on the device with the `Release` configuration if possible.
- Confirm the app installs, launches, and does not crash on first open.
- Confirm onboarding/sign-in routing is correct for a clean install.
- Confirm returning users route correctly if testing with an existing account.
- Confirm the widget extension does not break install or launch.

## Learning Center

- Open `Settings -> Help and referrals -> Learning Center`.
- Confirm the Learning Center title, search field, topic count, and category count appear.
- Browse categories and open at least these articles:
  - Account setup and first bill.
  - Main app navigation.
  - Receipt Jar.
  - FAQ: upgrades, restores, and offer codes.
  - Troubleshooting common issues.
- Search for `Receipt`, `restore`, `budget`, and a no-result query such as `zzzz-no-topic`.
- Confirm search results filter correctly and the empty-result state appears.
- Confirm article sections render: `Where to find it`, `Access`, `How to use it`, `Tips`, `Limitations`, and `Take Me There` where available.
- Confirm `Take Me There` links navigate to the expected in-app destination and back navigation returns safely.
- Confirm Dynamic Type at a large accessibility size still keeps the Learning Center readable and navigable.
- Confirm offline use: enable Airplane Mode after launch and verify bundled Learning Center content still displays.

## General Smoke

- Add, edit, and delete a test bill.
- Use Bills search/filter and Trash restore/delete flows.
- Open Dashboard, Reports, Calendar, Settings, and Account-related screens.
- Confirm notification permission prompts and reminder settings behave as expected.
- Confirm Calendar-related flows request permissions only when needed.
- Confirm paywall, restore purchases, and manage subscription entry points open the correct Apple-controlled surfaces in the intended test environment.
- Confirm Receipt Jar screens remain correctly gated if the entitlement is unavailable.
- Confirm no debug-only route or testing UI is reachable from a normal Release launch.

## Device-Specific Checks

- Test portrait and landscape where supported.
- Test light mode, dark mode, and system appearance.
- Test with normal and large Dynamic Type.
- Test at least one low-connectivity/offline launch.
- Test a cold launch after force-quitting the app.
- Test app background/foreground transitions.
- Add the widget if available and confirm it renders without crashing.

## Evidence To Capture

- Device model and iOS version.
- Xcode version/build.
- App version/build shown by Xcode or the installed app.
- Screenshots of the Learning Center list, search result, empty search state, and one article detail.
- Any device console crash logs or Xcode organizer crash reports if failures occur.

## Remaining Blockers Before App Store Submission

- A signed device run has not yet been performed from this RC checkpoint.
- A production archive and App Store validation/upload have not yet been performed.
- App Store Connect product, subscription, offer-code, privacy, and review metadata must be checked separately.
- Backend migrations and production configuration changes remain out of scope unless explicitly approved.
