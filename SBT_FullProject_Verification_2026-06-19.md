# Sacred Bill Tracker — Full `.xcodeproj` Verification
**Date:** 2026-06-19 · **Project:** `SacredBillTracker.xcodeproj` (real shipping app, now staged at **1.0.13 (29)**) · **Bundle:** `com.sacredbilltracker.app`
**Constraints honored:** no production Supabase data modified (read-only); no marketing assets changed; no source files changed.

---

## PASS / FAIL summary

| # | Check | Result |
|---|---|---|
| 1 | Shipping `Bill` model + Supabase encode/decode layer found | ✅ PASS |
| 2 | Production writes `user_id` AND `owner_id` | ✅ PASS (both set to auth user) |
| 3 | Partner RLS compatibility (`bills.user_id` populated) | ✅ PASS |
| 4 | `PrivacyInfo.xcprivacy` matches data collection | ⚠️ PARTIAL — financial data not declared |
| 5 | StoreKit / subscriptions wired correctly | ✅ PASS (StoreKit 2, correct) |
| 6 | Xcode build + simulator smoke test | ⛔ CANNOT RUN HERE — Linux sandbox (see below); last build on record = **BUILD SUCCEEDED**, app is live |
| — | Export compliance (`ITSAppUsesNonExemptEncryption`) | ✅ PASS (= NO) |
| — | In-app account deletion (App Store requirement) | ✅ PASS |

**Net:** No code blockers found. One privacy-label item to reconcile and a fresh on-device build/smoke test are the only things between here and App Review.

---

## 1. Shipping model + Supabase layer (PASS)

- **Model:** `SacredBillTracker/Models/Bill.swift` — the real, mature entity. Already uses `amount: Decimal`, `status: PaymentStatus`, `lastPaidDate`, `paymentURL`, `deletedAt`, `ownerUserID: UUID?`, `profileID`, plus payoff/15-3 fields. Custom decoder is back-compatible.
- **Encode/decode:** `SacredBillTracker/Services/SupabaseBillRepository.swift` uses a dedicated `BillRow: Codable` DTO that maps the model to/from the live snake_case columns (`due_date`, `last_paid_date`, `payment_url`, `is_shared`, `payoff_*`, etc.). Real path is active — `supabase-swift` is linked in the pbxproj (`Supabase in Frameworks`), so `#if canImport(Supabase)` compiles, not the fallback shim.

**Important context:** this is a *different* model from the `iOS_Updates/` pack I edited earlier. The earlier folder was an additive/abandoned pack that is **not** the shipping code. The real model never had the `is_paid` / `payment_link` mismatches — those existed only in the dead pack. No further model changes are needed here.

*Minor (non-blocking):* `BillRow` round-trips `amount` through `Double` at the wire boundary (`Decimal → Double → numeric(14,2)`). Because the DB column is `numeric(14,2)`, the stored value is correct to the cent; the in-app math stays `Decimal`. Optional hardening only.

## 2. `user_id` vs `owner_id` (PASS)

`BillRow.init(bill:userID:)` sets **both** on every insert/upsert:
```
self.user_id  = userID    // current authenticated user
self.owner_id = userID
```
So production always writes `user_id` (and a redundant `owner_id`) = the signed-in user. Soft-delete/restore/delete paths additionally scope by `.eq("user_id", userID)`.

## 3. Partner RLS compatibility (PASS)

- Live policy `"partners can read shared bills"` keys on **`bills.user_id`** (verified live): `is_shared = true AND deleted_at IS NULL AND` a `connected` row in `partner_invites` linking `bills.user_id` to `auth.uid()`.
- Production populates `user_id` correctly (§2), so a connected partner's shared-bill read path works.
- `loadBills()` deliberately does a filter-free SELECT and lets RLS scope the rows (own + partner-shared). `toBill()` sets `ownerUserID = owner_id ?? user_id` so the UI can tell own vs partner bills, and `saveBills()` filters out rows the user doesn't own to avoid RLS-rejected upserts clobbering a batch. Well-designed.

## 4. Privacy manifest vs actual collection (⚠️ PARTIAL — the one thing to fix)

`SacredBillTracker/PrivacyInfo.xcprivacy` declares:
- Accessed API: UserDefaults (reason `CA92.1`) ✓
- Collected: **Email Address** + **User ID** — both Linked, not Tracking, App Functionality ✓
- `NSPrivacyTracking = false`, no tracking domains ✓

**Gap:** the app also collects and transmits **financial data** to Supabase — bill amounts, payoff/debt balances, income (`IncomeStore`), and trucking loads/revenue. Under Apple's data categories this is **Financial Info → "Other Financial Info"** (and notes arguably **User Content**). Neither is declared.

**Action before review:** make sure the **App Store Connect → App Privacy** questionnaire (the binding "nutrition label") declares *Financial Info (Other Financial Info)* — Linked to user, **Not** used for tracking, purpose **App Functionality** — and ideally add a matching entry to `PrivacyInfo.xcprivacy`. This is the most likely review/metadata flag in the project. (Severity: medium — usually a metadata fix, not a binary rejection.)

## 5. StoreKit / subscriptions (PASS)

`Services/StoreKit/` — clean **StoreKit 2** implementation in `SubscriptionManager`:
- `Product.products(for:)` catalog load; paywall spinner + error surface.
- `purchase()` → `VerificationResult` check → `transaction.finish()` → entitlement refresh.
- Entitlements derived from `Transaction.currentEntitlements`; long-running `Transaction.updates` listener for renewals/Ask-to-Buy.
- **Restore** via `AppStore.sync()` (Apple requires a restore path — present).
- `showManageSubscriptions(in:)` from Settings.
- Debug owner-unlock for Focus+ is correctly `#if DEBUG`-gated — **release builds cannot bypass StoreKit** (no rejection risk).
- Product IDs: `com.sacredbilltracker.app.pro.monthly`, `…pro.yearly`, `sacred_focus_plus_monthly`; Pro group `22047990`.

*Verify before submitting (WARN, not a blocker):* the **Focus+** add-on. Its group ID is a placeholder (`focusPlusGroupID = "sacred_focus_plus"`, with a code comment that the group "needs to be created in App Store Connect before submitting"), and the product ID doesn't follow the bundle convention. If the Focus+ product/group isn't actually live in ASC, `loadProducts()` silently drops it and the Focus+ paywall shows "couldn't load." Confirm Focus+ exists in ASC, or that paywall is non-functional. The **Pro** tier (the main monetization) is fully correct.

## 6. Build + simulator smoke test (⛔ cannot run in this environment)

This session's shell is a **Linux sandbox with no macOS/Xcode toolchain** (`xcodebuild`/`swift` not present), so a fresh compile + simulator run **cannot be performed here**. Evidence the project builds:
- `release_guard_build.log` → `** BUILD SUCCEEDED **`
- `submit_v1011_to_appstore.log` → `** EXPORT SUCCEEDED **`
- The app is live on the App Store (1.0.12/27); project is staged at 1.0.13 (29).

**Run this on your Mac to get a fresh PASS** (build + boot + smoke):
```bash
cd "~/Documents/Claude/Projects/SACRED BILL TRACKER"

# 1) Clean build for the simulator
xcodebuild -project SacredBillTracker.xcodeproj \
  -scheme SacredBillTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build/SmokeDerived \
  clean build | tail -40

# 2) Boot sim, install, launch (smoke)
xcrun simctl boot "iPhone 16 Pro" 2>/dev/null; open -a Simulator
APP=$(find build/SmokeDerived/Build/Products -name "SacredBillTracker.app" -path "*Debug-iphonesimulator*" | head -1)
xcrun simctl install booted "$APP"
xcrun simctl launch booted com.sacredbilltracker.app
```
Want me to drive this via the Mac's Terminal/Xcode instead? I can, but a copy-paste run is faster and more reliable than me clicking through the IDE.

---

## Files inspected
- `SacredBillTracker/Models/Bill.swift`
- `SacredBillTracker/Services/SupabaseBillRepository.swift`
- `SacredBillTracker/PrivacyInfo.xcprivacy`, `SacredBillTracker/Info.plist`
- `SacredBillTracker/Services/StoreKit/{ProductIdentifiers,SubscriptionManager,Entitlements}.swift`, `Configuration.storekit`
- `SacredBillTracker.xcodeproj/project.pbxproj` (compliance keys, versions, SPM linkage)
- Live Supabase (read-only): `bills` RLS policies, column types, `status` vocab
- Build logs: `release_guard_build.log`, `submit_v1011_to_appstore.log`

## Files changed
**None.** This pass was verification-only. (The earlier `iOS_Updates/` edits were in a separate, non-shipping pack and do not affect this project.)

## Build / test results
- Fresh build: not runnable in this Linux sandbox.
- On record: `** BUILD SUCCEEDED **` + `** EXPORT SUCCEEDED **`; app live; project at 1.0.13 (29).

## Remaining blockers before App Review
1. **Privacy label (medium).** Add **Financial Info → Other Financial Info** (Linked, not Tracking, App Functionality) to the App Store Connect App Privacy answers, and ideally to `PrivacyInfo.xcprivacy`, since the app collects bills/debts/income/loads. Currently only Email + User ID are declared.
2. **Fresh build + simulator smoke test (low risk).** Run the commands above on your Mac to confirm 1.0.13 (29) builds clean and launches before archiving.
3. **Focus+ IAP (verify).** Confirm the Focus+ product and its subscription group exist/are approved in App Store Connect, or expect that paywall to fail to load. Does not affect the Pro tier.

No code defects found in the model, Supabase mapping, RLS compatibility, or StoreKit wiring.
