# Sacred Bill Tracker 1.0.20 (56) Unified Account Backend Plan

Draft only. Do not apply production migrations, deploy production functions, create store credentials, create products, upload builds, submit for review, or change pricing without explicit owner approval.

## Canonical Account

`SacredBillTrackerUserID` is the Supabase/Auth UUID. Apple subject IDs, Google subject IDs, email addresses, Apple private relay addresses, device IDs, purchase tokens, and transaction IDs are linked attributes only.

Email equality is never enough to merge accounts. Ambiguous duplicate accounts go to `needs_review` or `quarantined` and require secure reauthentication or support review.

## Migration Strategy

1. Back up production database and storage metadata.
2. Apply the migration to staging only.
3. Backfill `sbt_accounts` from existing `auth.users`.
4. Backfill `owner_id` on existing bills from `user_id`, then verify counts per user.
5. Import existing identity links from Supabase provider identities when available.
6. Leave duplicate email/private-relay matches unmerged; mark review queues.
7. Backfill known verified Apple/Google purchases only from server-verifiable records.
8. Leave local-only Receipt Jar data quarantined until the signed-in user explicitly chooses migration.
9. Run RLS probes for bills, receipts, receipt documents, education progress, settings, and entitlements.
10. Run Apple/Google verifier fixtures against staging edge functions.
11. Run iOS and Android client tests against staging.
12. Only after owner approval, apply production in small, restartable batches.

## Apple Verification Boundary

The backend must use App Store Server API and App Store Server Notifications V2. It must verify signed Apple JWS payloads, bind `originalTransactionId` to one `SacredBillTrackerUserID`, record notification IDs for idempotency, and ignore older events after a newer provider event time has been processed.

Client StoreKit transactions may trigger a refresh, but the client is not authoritative. The server decides entitlement state.

## Google Verification Boundary

The backend must use Google Play Developer API and Real-time Developer Notifications. It must verify subscriptions and one-time products on the server, bind purchase-token lineage to one `SacredBillTrackerUserID`, record RTDN/message IDs for idempotency, and ignore stale events after a newer provider event time.

The Android app must not fabricate Apple transactions, and iOS must not fabricate Google transactions. Cross-platform access comes from the account-level entitlement response.

## Entitlement Precedence

Effective plan is the highest active account-level plan:

`unlimited > business > essential > free`

Granting statuses:

`active`, `trial`, `grace`, `cancelled_active`

Non-granting statuses:

`billing_retry`, `account_hold`, `expired`, `revoked`, `refunded`, `quarantined`

An expired or revoked lower-tier purchase never downgrades an active higher-tier purchase. Multiple providers remain separately recorded. Receipt Jar lifetime is independent of plan tier and remains active only while the verified non-consumable/one-time purchase is bound and not refunded/revoked/quarantined.

Legacy/grandfathered grants may participate as provider `legacy`, but must be auditable and must not overwrite store-origin records.

## Ownership Protection

Unique keys:

- Apple: `(provider, environment, originalTransactionId)`
- Google: `(provider, environment, purchaseToken lineage/hash or order lineage)`
- Store event idempotency: `(provider, environment, event_id)`

If a purchase already belongs to account A, account B receives a conflict/quarantine state. The backend must not silently transfer the purchase. Support transfer requires audit notes and an explicit support/admin action.

## Data Sync Scope

Owner-scoped cloud records must use `SacredBillTrackerUserID` or a verified account relationship:

- Bills and bill status/history
- Categories
- Financial Education progress/favorites
- Receipt Jar metadata
- Receipt Jar original-document metadata and storage paths
- Receipt-to-bill associations
- Account settings
- Device registrations

Clients must not be able to read or write another user's records by supplying a different owner ID. RLS and storage policies must enforce owner checks server-side.

## Receipt Documents

Receipt original files should use private Supabase Storage bucket `receipt-jar-originals`.

Path format:

`{owner_user_id}/{receipt_id}/{filename}`

Policies must compare the first path segment to `auth.uid()`. Obscure URLs, random filenames, and client-side filters are not authorization.

OCR text must be payment-data redacted before any cloud persistence.

## Gmail

Gmail remains UI/architecture only. Future Gmail links should attach to `SacredBillTrackerUserID` and request only:

`https://www.googleapis.com/auth/gmail.readonly`

Production OAuth credentials and verification are a separate approval-gated phase.

## Sandbox QA Matrix

Run before production readiness:

- iOS to iOS: same account, different account, restore, expiration, revocation
- Android to Android: same account, different account, restore, expiration, revocation
- iOS purchase to Android login: plan, Receipt Jar, bills, progress, receipts, documents
- Android purchase to iOS login: plan, Receipt Jar equivalent, bills, progress, receipts, documents
- Logout/login and device replacement on both platforms
- Ambiguous duplicate accounts and private relay emails
- Support-reviewed ownership transfer

Passing local tests does not make this production-ready. Production readiness requires deployed verifier functions, applied migrations, real sandbox store testing, RLS/storage audit, and explicit approval.
