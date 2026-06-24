# 3-Tier Subscription — Backend Enforcement & Test Evidence (2026-06-24)

## Migration applied (live, project zziauybwemoiqfpidiur)
`supabase/migrations/20260624230000_tier_enforcement_guards_and_unlimited_autotrack_grant.sql`
- Broadened `has_autotrack_premium()` to grant bank-sync to any active tier **rank ≥ 3** (Unlimited + legacy AutoTrack), keeping period-end rigor. Fixes a gap where a new `unlimited_monthly_1499` buyer (`feature_key='unlimited'`) was blocked from bank sync.
- Added `assert_essential()` / `assert_business()` / `assert_unlimited()` guard functions.
- Core tables intentionally left ungated (freemium): bills, income_entries, budget_categories, budget_goals, financial_profiles.

## Deterministic backend simulation (live functions, non-persisting test user)
Same `original_transaction_id` across steps to model real StoreKit upgrade/downgrade; test rows deleted after (verified 0 leftover).

| Action | derived feature_key | current_subscription_tier | has_essential | has_business | has_unlimited | bank-sync (post-fix) |
|---|---|---|---|---|---|---|
| buy essential_monthly_499 | essential | essential | true | false | false | false |
| upgrade → business_monthly_999 | business | business | true | true | false | false |
| upgrade → unlimited_monthly_1499 | unlimited | unlimited | true | true | true | true |
| downgrade → essential_monthly_499 | essential | essential | true | false | false | false |
| expired | — | free | false | false | false | false |
| legacy …autotrack.monthly | autotrack_premium | unlimited | — | — | true | true |

Confirms: correct tier per product, cumulative gating (essential ⊂ business ⊂ unlimited), correct upgrade/downgrade/expiry, and that bank sync is granted to Unlimited/legacy-AutoTrack only.

## Not covered (credential-gated, requires device)
Real on-device sandbox purchase (StoreKit → verify-store-subscription → subscriptions row) was not executed: it requires signing a Sandbox Apple Account into the device and an app login (passwords). Run the steps in `SBT_Gap_Closure_2026-06-24.md` to close this gate.

## Client product IDs (verified in source) — match ASC + backend exactly
`Services/StoreKit/ProductIdentifiers.swift`: `essential_monthly_499`, `business_monthly_999`, `unlimited_monthly_1499` (+ legacy pro/autotrack/focus IDs).
