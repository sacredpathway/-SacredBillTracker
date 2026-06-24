# SacredBillTracker — 3-Tier Integration Spec (build-ready)
**Goal:** Replace the old Pro/AutoTrack/Focus+ paywall with the 3-tier system and gate features by Essential / Business / Unlimited.
**Status:** Authored from the live source; **NOT compiled** (no Xcode toolchain in the audit environment). Apply on the Mac, then build + device-test (steps at the bottom).
**Already applied for you:** `ProductIdentifiers.plansGroupID` → `"22184614"`.

> Design principle: centralize all tier logic in `SubscriptionManager` so feature views change minimally and there is **one** source of truth. Legacy subscribers are mapped up so nobody loses access.

---

## Feature → minimum tier (the contract)

| Capability | Min tier | Notes |
|---|---|---|
| Manual bills (no 5-bill cap), income entry | **Essential** | Essential's whole value prop. |
| Business income/expense tracking, business bills, personal⁄business split, business reports | **Business** | |
| Managed Profiles (family/spouse/child/rental), forecasting, AI insights, advanced analytics, goals, net worth, advanced exports, premium themes | **Unlimited** | Everything. |
| Legacy `proMonthly`/`proYearly` | → **Business** | Existing Pro subs keep ≥ Business. |
| Legacy `autotrack.monthly/annual` | → **Unlimited** | Existing AutoTrack subs keep Unlimited. |

---

## STEP 1 — Make `SubscriptionManager` tier-aware (additive)

In `SacredBillTracker/Services/StoreKit/SubscriptionManager.swift`:

**1a. Add a published tier + capability flags** (near the other `@Published` props, after `hasAutoTrack`):
```swift
/// Highest 3-tier plan the user holds, derived from StoreKit entitlements
/// for essential/business/unlimited (see refreshEntitlements()).
@Published private(set) var rawPlanTier: PlanTier = .free
```

**1b. Add the effective-tier bridge + capability flags** (in the `// MARK: - Convenience` block, replace the single `isPro` line):
```swift
/// Effective tier = max(new 3-tier plan, legacy Pro→Business, legacy AutoTrack→Unlimited).
var effectiveTier: PlanTier {
    var t = rawPlanTier
    if currentTier.isPro { t = max(t, .business) }   // legacy Pro
    if hasAutoTrack      { t = max(t, .unlimited) }  // legacy AutoTrack
    return t
}

// Tier-aware capabilities — gate features on THESE, not on isPro.
var canUnlimitedBills:   Bool { effectiveTier >= .essential }
var canIncomeTracking:   Bool { effectiveTier >= .essential }
var canBusinessTracking: Bool { effectiveTier >= .business  }
var canBusinessReports:  Bool { effectiveTier >= .business  }
var canManagedProfiles:  Bool { effectiveTier >= .unlimited }
var canForecasting:      Bool { effectiveTier >= .unlimited }
var canAIInsights:       Bool { effectiveTier >= .unlimited }
var canAdvancedAnalytics:Bool { effectiveTier >= .unlimited }

/// Back-compat: any paid plan (Business+) counts as "Pro" for legacy call sites
/// that haven't been migrated to a specific capability yet.
var isPro: Bool { effectiveTier >= .business }
```
> Delete the old `var isPro: Bool { currentTier.isPro }` (line ~78).

**1c. Populate `rawPlanTier` in `refreshEntitlements()`** — add these cases inside the `switch transaction.productID` (alongside the existing cases), and set the published value at the end:
```swift
            case ProductID.essentialMonthly, ProductID.businessMonthly, ProductID.unlimitedMonthly:
                let t = PlanTier.from(productID: transaction.productID)
                if t.rank > plan.rank { plan = t }
```
At the top of `refreshEntitlements()` add `var plan: PlanTier = .free` next to `var tier: SubscriptionTier = .free`, and near the bottom (with the other assignments) add:
```swift
            self.rawPlanTier = plan
```
Also set `rawPlanTier = .free` inside `clearForSignedOutUser()`.

> This is purely additive to the existing Pro/AutoTrack logic — legacy behavior is unchanged; new tier purchases now register.

---

## STEP 2 — Point every paywall trigger at the 3-tier paywall

In `SacredBillTracker/Views/Paywall/PaywallView.swift`, replace the `paywallSheet` extension (~line 356):
```swift
private struct PaywallSheetModifier: ViewModifier {
    @EnvironmentObject private var tiers: TierEntitlementManager
    @Binding var isPresented: Bool
    var reason: String?
    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ThreeTierPaywallView(source: reason ?? "paywall")
                .environmentObject(tiers)
        }
    }
}

extension View {
    /// Presents the 3-tier paywall. `reason` is used as the analytics source.
    func paywallSheet(isPresented: Binding<Bool>, reason: String? = nil) -> some View {
        modifier(PaywallSheetModifier(isPresented: isPresented, reason: reason))
    }
}
```
> Every existing `.paywallSheet(...)` call site (Settings, Budgeting, Bills, AddEditBill) now shows the 3-tier paywall — no call-site edits needed. `TierEntitlementManager` is already injected at app root (`SacredBillTrackerApp.swift:176`), so the `@EnvironmentObject` resolves.
> Keep the old `PaywallView` struct in the file (its `#Preview` and `AutoTrackPaywallView` still use it) — only the `paywallSheet` modifier changes.

---

## STEP 3 — Switch each gate from `isPro` to the right capability

These are the behavior-defining edits. Replace the boolean used at each gate:

| File | Current check | Change to |
|---|---|---|
| `Views/Bills/BillsView.swift` (bill-cap paywall trigger) | `isPro` / free-cap | `subs.canUnlimitedBills` |
| `Views/Bills/AddEditBillView.swift` (cap + business-bill toggle) | `isPro` | bills: `subs.canUnlimitedBills`; business-bill toggle: `subs.canBusinessTracking` |
| `Views/Dashboard/BudgetingView.swift` `budgetPro` (line 874) | `subs.isPro \|\| subs.hasAutoTrack` | forecast/wellness/AI/auto-budget: `subs.canForecasting`; basic budget UI: `subs.canUnlimitedBills` |
| `Views/Profiles/ManagedProfilesView.swift` + `Services/ManagedProfileStore.swift` `isPremiumUnlocked` | `isPro` | `subs.canManagedProfiles` |
| `Views/Reports/ReportsView.swift` | `isPro` / `allowReports` | basic reports: `subs.canIncomeTracking`; business/profit reports: `subs.canBusinessReports` |
| `Services/StoreKit/Entitlements.swift` `FreeTierLimits.allowBusinessBills` | `false` | drive via `subs.canBusinessTracking` at call sites |

> Rule of thumb: if the feature is in Essential's bullet list → `canUnlimitedBills`/`canIncomeTracking`; Business bullets → `canBusinessTracking`/`canBusinessReports`; Unlimited bullets → `canManagedProfiles`/`canForecasting`/`canAIInsights`/`canAdvancedAnalytics`.
> Optionally, for richer upsell UX, wrap premium surfaces with the existing `.tierGated(.forecasting)` etc. instead of a manual `if` — both read the same entitlement.

---

## STEP 4 — Verify the requirement holds

After Step 3, the contract is enforced:
- **Essential $4.99** → `canUnlimitedBills` + `canIncomeTracking` true; `canBusinessTracking` / `canManagedProfiles` / `canForecasting` **false**. ✔ bills + income only.
- **Business $9.99** → adds business tracking + reports; profiles/forecasting/AI still false. ✔
- **Unlimited $14.99** → everything true. ✔
- **No $4.99 user reaches Unlimited features** — `canManagedProfiles/canForecasting/...` require `effectiveTier >= .unlimited`; Essential is rank 1. ✔ (backend `current_subscription_tier` fix already prevents wrong promotion server-side.)

---

## STEP 5 — Build + device test (the validation gate)

```bash
# version bump
cd "/path/to/SACRED BILL TRACKER"
agvtool new-marketing-version 1.0.15
agvtool next-version -all
```
In Xcode (run scheme → Options → StoreKit Configuration = `Configuration.storekit` for local, or sandbox Apple ID for real):
1. Build to a device. Confirm **no compile errors** from Steps 1–3.
2. Open any gated feature → the **3-tier paywall** appears with all 3 cards + live prices.
3. Buy **Essential** (sandbox) → bills cap lifts, income works; tapping a Business/Unlimited feature still shows the paywall.
4. Buy/upgrade to **Unlimited** → everything unlocks; no paywall loops.
5. Confirm backend: `select feature_key,status from subscriptions order by updated_at desc limit 3;` shows the **correct** feature_key (essential/business/unlimited), not autotrack_premium.
6. Archive → Distribute → App Store Connect. Attach a paywall **review screenshot** to each of the 3 IAPs, then submit the products **with** build 1.0.15.

---

## Migration / subscriber safety
- Existing **Pro** subscribers → `effectiveTier ≥ .business` (Step 1b). They keep business features.
- Existing **AutoTrack** subscribers → `effectiveTier = .unlimited`. They keep everything.
- Existing **Focus+** add-on (`hasFocusPlus`) is independent — leave its gating as-is unless you fold Focus features into Unlimited.

## Files touched
- ✅ `ProductIdentifiers.swift` (plansGroupID — done)
- `SubscriptionManager.swift` (Step 1)
- `PaywallView.swift` (Step 2)
- `BillsView.swift`, `AddEditBillView.swift`, `BudgetingView.swift`, `ManagedProfilesView.swift`, `ManagedProfileStore.swift`, `ReportsView.swift`, `Entitlements.swift` (Step 3)
