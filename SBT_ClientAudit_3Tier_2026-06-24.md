# SacredBillTracker — Client-Side 3-Tier Audit (Xcode source)
**Date:** 2026-06-24 · **Project:** `/SACRED BILL TRACKER/SacredBillTracker.xcodeproj`
**Overall: ⛔ FAIL — NOT safe to archive as 1.0.15 (for a 3-tier launch) · Risk: HIGH**

> Every finding below is from reading the actual project files (paths + line numbers cited). The individual tier files are written correctly — but the 3-tier system is **not integrated into the app**, so it does nothing for users.

---

## Files checked (exact paths)
1. `SacredBillTracker/Services/StoreKit/ProductIdentifiers.swift` ✅ read
2. `SacredBillTracker/Services/StoreKit/SubscriptionPlanTier.swift` ✅ read
3. `SacredBillTracker/Services/StoreKit/TierEntitlementManager.swift` ✅ read
4. `SacredBillTracker/Views/Paywall/ThreeTierPaywallView.swift` ✅ read
5. `SacredBillTracker/Views/Paywall/FeatureGate.swift` ✅ read
6. `SacredBillTracker/Configuration.storekit` ✅ read
7. `SacredBillTracker/SacredBillTrackerApp.swift` (wiring) ✅ read
8. `SacredBillTracker/Views/Paywall/PaywallView.swift` (the live paywall) ✅ read
9. Whole-project greps for `.tierGated(`, `InlineUpsellBanner(`, `PlanTier`, `tiers.` usage

---

## Confirm-list results

| # | Requirement | Verdict | Evidence |
|---|---|---|---|
| 1 | StoreKit product IDs match ASC exactly | ✅ **PASS** | `ProductIdentifiers.swift`: `essential_monthly_499`, `business_monthly_999`, `unlimited_monthly_1499` — identical to ASC + `Configuration.storekit`. |
| 2 | Paywall loads all 3 products | 🟡 **PARTIAL** | `TierEntitlementManager.loadProducts()` requests `ProductID.tierPlans` (all 3) and `ThreeTierPaywallView` renders all 3 correctly. **BUT the paywall is never shown to users** (see Blocker A). |
| 3 | Essential ($4.99) only unlocks manual bills + income | ❌ **FAIL** | No tier gating is applied anywhere. Manual bills/income are not gated by `PlanTier`. Nothing enforces this. |
| 4 | Business ($9.99) unlocks personal + business tracking | ❌ **FAIL** | `GatedFeature.businessTracking/.businessDashboard/.personalBusinessSplit` exist and map to `.business` correctly, but `.tierGated(...)` is applied **0 times** — business views are not gated by the Business tier. |
| 5 | Unlimited ($14.99) unlocks everything | ❌ **FAIL** | Unlimited-tier gates (forecasting, AI, analytics, profiles, etc.) are defined but never applied to any view. |
| 6 | No $4.99 user can access Unlimited features | 🟡 **VACUOUS** | Technically true only because **nothing is tier-gated**. Note: the backend bug that *would* have promoted Essential→Unlimited was fixed earlier today; the client's `refreshFromBackend()` (TierEntitlementManager.swift:101) "promotes, never demotes," so a correct backend is required — now it is. |
| 7 | StoreKit IDs ↔ ASC ↔ .storekit | ✅ **PASS** | All three sources agree. |
| 8 | Safe to archive as 1.0.15 | ❌ **FAIL** | The 3-tier feature is non-functional in the UI and the 3 IAPs are not purchasable in-app (App Store review risk). |

---

## 🔴 Blocker A — The 3-tier system is dead code in the UI

**Evidence (whole-project greps):**
- `.tierGated(` applied outside its own definition: **0 occurrences**
- `InlineUpsellBanner(` used: **0 occurrences**
- `ThreeTierPaywallView` presented: **only** from `FeatureGate.swift:87` and `:130` — i.e. only from the two modifiers that are themselves never used
- `PlanTier` referenced in feature views: **0** (only in the 4 tier files)
- `TierEntitlementManager` consumed: **only** by `ThreeTierPaywallView` + `FeatureGate`

**Consequence:** Users never see the 3-tier paywall and no feature is gated by Essential/Business/Unlimited. The manager loads the products into memory (`SacredBillTrackerApp.swift:178 .task { await tiers.start() }`) but nothing presents them.

## 🔴 Blocker B — Two parallel, competing paywall systems ship at once

The app's **live** paywall everywhere is the OLD one:
- `PaywallView.swift:359 .paywallSheet(isPresented:reason:)` is what Settings, Budgeting, Bills, and AddEditBill actually call (`SettingsView.swift:551`, `BudgetingView.swift:923`, `BillsView.swift:134`, …).
- It sells **Pro Monthly $4.99 / Pro Yearly $39.99 / AutoTrack $14.99 / Focus+ $9.99** (`Configuration.storekit` groups `22047990`, `sacred_autotrack_premium`, `sacred_focus_plus`).

So the new tiers (Essential $4.99 / Business $9.99 / Unlimited $14.99) **duplicate** the old price points and run in parallel with a system users never reach. Shipping both = duplicate $4.99 and $14.99 offerings and user confusion.

## 🟡 Minor
- `ProductIdentifiers.swift:59 plansGroupID = "30010001"` is the **local .storekit** group id, not the real ASC group `22184614`. Harmless today (the constant is never read), but update it for correctness.
- New-tier entitlements are **client-side only** — no Supabase RLS enforces `has_business()/has_unlimited()` (confirmed in the backend audit). Acceptable for launch UX, but sensitive premium data should add server checks.

## ✅ What IS correct (so the fix is integration, not rewrite)
- Product IDs, prices ($4.99/$9.99/$14.99), tier ranks, and `PlanTier.from(productID:)` mapping — all correct.
- `TierEntitlementManager`: local StoreKit authoritative + backend promote-only; purchase/upgrade/downgrade/restore all sound; calls `verify-store-subscription` correctly.
- `ThreeTierPaywallView` + `FeatureGate` are well-built and ready to use.
- Backend `record_verified_subscription` feature_key bug — **fixed & verified earlier today**.

---

## Required code fixes (before a real 3-tier launch)
1. **Decide the paywall strategy (product decision needed):** replace the old `.paywallSheet`/`PaywallView` with `ThreeTierPaywallView`, OR keep Pro/AutoTrack/Focus+ and drop the 3 new tiers. Do **not** ship both.
2. **Present the new paywall:** add an entry point (e.g. Settings "Plans"/"Upgrade") that presents `ThreeTierPaywallView`, and/or route `.paywallSheet` to it.
3. **Apply gating:** wrap real premium surfaces with `.tierGated(...)`:
   - Business dashboards / personal-business split / business tracking → `.tierGated(.businessTracking)` (etc.)
   - Forecasting, AI insights, advanced analytics, goals, net worth, extra profiles, exports, themes → `.tierGated(.forecasting)` / `.aiInsights` / …
   - Essential = base paid tier (bills + income available to all paid tiers — no gate needed).
4. **Migration plan** for existing Pro/AutoTrack/Focus+ subscribers (legacy mapping already exists in `PlanTier.from(productID:)`).
5. Fix `plansGroupID` to `22184614` (cosmetic).
6. (Recommended) Add server-side RLS using `has_business()/has_unlimited()` for sensitive premium data.

## Recommendation
**Do not archive 1.0.15 as a 3-tier launch.** The tier code is correct but unintegrated; submitting the 3 IAPs while they're unreachable in-app risks an App Store rejection ("in-app purchase not present"). Either (a) complete the integration in items 1–4 and re-test on device, or (b) ship 1.0.15 on the existing Pro system and hold the 3 IAPs until integrated. The backend is now safe either way.
