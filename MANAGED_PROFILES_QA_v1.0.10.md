# Managed Financial Profiles QA - v1.0.10 (Build 26)

## Release Readiness Gate

Managed Financial Profiles must not be marked TestFlight-ready until all of the following pass against staging:

- Premium gating is verified for subscriber and non-subscriber accounts.
- Migration `supabase/migrations/20260611090000_managed_financial_profiles.sql` is applied to the staging Supabase project only.
- Two distinct authenticated users complete the profile-isolation QA matrix.
- RLS is verified with real authenticated requests, not only schema inspection.
- Income behavior is accepted as local/iCloud-only for v1.0.10 or Supabase income sync is fully implemented.

## Premium-Only Requirement

Managed Financial Profiles are a Premium-only feature in v1.0.10.

Plan:

- Use the existing Sacred Bill Tracker Pro monthly product if available: `com.sacredbilltracker.app.pro.monthly`.
- App Store monthly subscription price target: `$19.99/month`.
- Existing Pro yearly entitlement also unlocks Managed Financial Profiles because the app uses the shared `subs.isPro` entitlement.
- Do not create or change App Store Connect products from the app codebase without an explicit release-management task.

Paywall copy:

> Managed Financial Profiles is a Premium feature. Manage your personal, family, business, and rental property finances in one place.

Free behavior:

- The user remains on the default profile only.
- Existing bill tracking continues normally.
- Existing testing profiles and their data are not deleted.
- Add Profile, Archive Profile, Manage Profiles, All Profiles, profile switching, and profile assignment pickers are locked.
- Multi-profile reports and exports require the Premium paywall.
- If a non-premium account already has multiple profiles from testing, the app falls back to the default profile and preserves historical data.

Premium behavior:

- Create Personal, Spouse, Child, Parent, Business, and Rental Property profiles.
- Edit profile names and types.
- Archive non-final active profiles.
- Switch between profiles and All Profiles.
- Access All Profiles dashboard totals, reports, exports, calendar, bills, income, trash, and search filtering.

## Income Sync Decision

Status: DEFERRED WITH NOTES.

The iOS app's income system is currently local/iCloud-only:

- `IncomeStore` persists `WeeklyIncome` through `CloudBackedDefaults`.
- `CloudBackedDefaults` writes to local `UserDefaults` and `NSUbiquitousKeyValueStore`.
- No Swift repository currently reads from or writes to Supabase `income_entries`.
- The `income_entries` table in the managed profiles migration is server-side groundwork only.

v1.0.10 can ship with local/iCloud income if release notes and QA notes call this out clearly. Do not describe income as Supabase-synced until a remote income repository, conflict handling, and migration/backfill path are implemented and tested.

## Migration Status

Status: PREPARED, NOT APPLIED.

Migration file:

- `supabase/migrations/20260611090000_managed_financial_profiles.sql`

Local static verification:

- `scripts/verify_managed_profiles_gate.sh` passed locally.
- The script verifies the migration contains `financial_profiles`, `archived_at`, `bills.profile_id`, `income_entries`, owner-scoped RLS policies, profile/owner trigger guards, and `ON DELETE RESTRICT` profile foreign keys.
- It also verifies the app-side premium gate is present for Managed Profiles store actions, the profile UI/paywall, bill profile pickers, quick-add profile picker, income profile picker, and the `$19.99/month` fallback paywall price.

Staging application remains blocked because no staging Supabase project ref, staging database password, or percent-encoded staging Postgres URL is present in the repo. The app config still points at production-looking project ref `zziauybwemoiqfpidiur`; do not use linked-project migration commands from this checkout.

Safe staging commands after receiving a staging-only percent-encoded Postgres URL:

```bash
export SBT_STAGING_DB_URL='<percent-encoded staging Postgres db-url>'
supabase db push --dry-run --db-url "$SBT_STAGING_DB_URL"
supabase db push --db-url "$SBT_STAGING_DB_URL"
/opt/homebrew/opt/libpq/bin/psql "$SBT_STAGING_DB_URL" -f supabase/verification/verify_managed_profiles_staging.sql
```

Do not run these commands against `zziauybwemoiqfpidiur` unless production migration is explicitly approved.

## RLS Verification Result

Status: STATIC PASS, STAGING LIVE VERIFICATION PENDING.

Static migration review indicates:

- `financial_profiles`, `bills`, and `income_entries` enable RLS.
- Profile read/insert/update policies are scoped to `auth.uid() = owner_id`.
- No owner delete policy is created for `financial_profiles`; profiles are archived by app flow instead of deleted.
- Bills and income policies require owner-scoped access and verify that `profile_id` belongs to the authenticated owner.
- `bills.profile_id` and `income_entries.profile_id` use `ON DELETE RESTRICT`, preserving historical bill/income references.
- Triggers reject mismatched owner/profile combinations.

Important limitation:

- Supabase RLS does not currently know App Store subscription entitlement state. Free-vs-Premium behavior is enforced in the iOS app via `SubscriptionManager` and `ManagedProfileStore`, not database RLS. RLS verifies ownership isolation and no cross-user leakage; real StoreKit sandbox QA must verify free users stay on the default profile in app flows.

Live staging verification still required:

- Apply the migration to staging.
- Run `supabase/verification/verify_managed_profiles_staging.sql`.
- Sign in as two different staging users and confirm cross-user profile, bill, income, report, export, and trash isolation with real authenticated requests.

## Required Staging Database Checks

- `public.financial_profiles` exists.
- `public.financial_profiles.archived_at` exists.
- `public.bills.profile_id` exists.
- `public.income_entries` exists.
- `bills.profile_id` foreign key uses `ON DELETE RESTRICT`.
- `income_entries.profile_id` foreign key uses `ON DELETE RESTRICT`.
- `financial_profiles` has no owner delete policy.
- Profile RLS allows each owner to select/insert/update only their own profiles.
- Bills and income rows cannot be read across owner accounts.
- Archiving a profile does not delete or orphan historical bills/income.

## Two-User QA Matrix

Real device / StoreKit sandbox requirements:

- Use a non-subscriber sandbox account to confirm free users are locked to the default profile.
- Use a subscriber sandbox account with `com.sacredbilltracker.app.pro.monthly` active to confirm profile creation/edit/archive/switching.
- Confirm the paywall displays the Managed Profiles message and App Store product price for the live sandbox product.
- Confirm the App Store Connect monthly price is configured as `$19.99/month`; this cannot be changed from code.
- Confirm existing test profiles on a non-subscriber account are preserved but locked.
- Confirm no TestFlight upload occurs until staging migration and live RLS checks pass.

Non-subscriber account:

- Confirm the profile switcher shows the default profile with a lock.
- Tap the profile switcher and confirm the Managed Financial Profiles paywall appears.
- Open Settings > Manage Profiles and confirm the Managed Financial Profiles paywall appears.
- Confirm Add Profile is not available without the paywall.
- Confirm profile assignment pickers do not appear in Add/Edit Bill, Quick Add, or Add/Edit Income.
- Confirm new bills and income save to the default profile.
- Confirm old testing profiles are not deleted.
- Confirm Reports remain behind the existing Pro paywall.

User A:

- Use a Premium subscriber entitlement.
- Create profiles: Personal, Spouse, Business, Rental Property.
- Add bills to each profile.
- Add income to each profile.
- Switch between each profile and confirm only scoped bills/income appear.
- Confirm All Profiles shows combined totals.
- Verify Dashboard, Bills, Calendar, Income, Reports, Export, Trash, and Search respect the selected profile.
- Archive a non-active profile and confirm it disappears from normal profile selection.
- Confirm archived profile historical bills/income remain included in All Profiles totals/exports.
- Confirm the last active profile cannot be archived.

User B:

- Test both non-subscriber and subscriber states where possible.
- Sign into a separate account.
- Confirm User B cannot see User A profiles.
- Confirm User B cannot see User A bills, income, reports, exports, or trash.
- Test partner/shared behavior if available.
- Confirm shared bills do not expose User A profile names or profile management data.

## Deferred Warning Notes

Known non-blocking warnings remaining after the v1.0.10 profile work:

- `BillsRealtimeService`: Supabase realtime APIs are deprecated and should be migrated to the newer filter syntax plus `subscribeWithError`.
- `PushNotificationManager`: `.timeSensitive` warning remains because the correct fix requires confirming the app entitlement/notification behavior, not a mechanical code change.
- `NotificationSettingsView`: `onChange(of:perform:)` can be modernized to the iOS 17 closure form in a polish pass.

Fixed during this QA pass:

- Swift 6 future-error warning from capturing mutable notification payload across concurrent code.
- Remote push handler warnings for an unmutated `didFetch` placeholder and unreachable `.newData` result.

## Final TestFlight Readiness Verdict

Status: NOT READY.

Reasons:

- Staging migration has not been applied because staging credentials are not available.
- RLS has passed static migration review only; live staging verification is still pending.
- Real StoreKit sandbox subscriber and non-subscriber QA is still pending.
- Real two-user profile-isolation QA is still pending.
- Income Supabase sync remains intentionally deferred/local-iCloud only and must be described that way in release notes.
