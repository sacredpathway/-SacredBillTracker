# Sacred Bill Tracker Staging Verifier Contracts

Local preparation only. Do not deploy these contracts to production or connect
production store credentials without explicit approval.

## Environment Isolation

- Candidate staging Supabase project: `thwjnpofhrpxfuvwkfgd`
- Current default Supabase project in source: `zziauybwemoiqfpidiur`
- iOS staging acceptance builds require `SBT_STAGING_ACCEPTANCE`, reject archive
  builds, and restrict network traffic to `https://thwjnpofhrpxfuvwkfgd.supabase.co`.
- No shell staging variables were present during this inspection, so remote
  migration/deployment was intentionally not attempted.

## Required Edge Functions

### `POST /functions/v1/store-verification-apple`

Request:

```json
{
  "account_id": "uuid",
  "environment": "sandbox",
  "app_transaction_id": "optional signed StoreKit/AppTransaction evidence",
  "transaction_id": "client-observed transaction id",
  "original_transaction_id": "client-observed original transaction id",
  "product_id": "com.sacredbilltracker.app.receiptjar.lifetime",
  "reason": "purchase|restore|refresh"
}
```

Server requirements:

- Authenticate caller and require `account_id == auth.uid()`.
- Verify signed Apple transaction information or fetch authoritative state from
  App Store Server API before changing entitlements.
- Store Apple notifications/events idempotently by `(provider, environment, event_id)`.
- Bind `(apple, environment, original_transaction_id)` to one account only.
- Convert Apple lifecycle states into `active`, `trial`, `grace`,
  `billing_retry`, `cancelled_active`, `expired`, `revoked`, `refunded`, or
  `quarantined`.
- Reject or quarantine conflicting ownership; never transfer by matching email.

Response:

```json
{
  "account_id": "uuid",
  "environment": "sandbox",
  "effective_plan_tier": "free|essential|business|unlimited",
  "receipt_jar_lifetime": true,
  "verified_at": "iso-8601",
  "expires_at": "iso-8601-or-null",
  "has_conflict": false,
  "ownership_resolution": "securely_bound|legacy_ownership_unresolved|quarantined"
}
```

### `POST /functions/v1/store-notifications-apple`

Server requirements:

- Verify App Store Server Notifications V2 signed payloads.
- Upsert `sbt_store_events` idempotently.
- Update `sbt_store_purchases` only after signature and App Store state checks.
- Ignore older provider event times after a newer state was applied.

### `POST /functions/v1/store-verification-google`

Request:

```json
{
  "account_id": "uuid",
  "environment": "sandbox",
  "package_name": "com.sacredbilltracker.app",
  "product_id": "subscription_or_one_time_product_id",
  "purchase_token": "client purchase token",
  "reason": "purchase|restore|refresh"
}
```

Server requirements:

- Authenticate caller and require `account_id == auth.uid()`.
- Verify purchase token through Google Play Developer API.
- Hash purchase tokens before storage.
- Bind purchase-token lineage/order lineage to one account only.
- Do not fabricate Google purchases for Apple-origin entitlements.
- Map Play states into granting/non-granting Sacred Bill Tracker states.

### `POST /functions/v1/store-notifications-google`

Server requirements:

- Accept Real-time Developer Notifications through Pub/Sub delivery only.
- Verify message provenance using the configured Google Cloud project.
- Use Developer API lookups before entitlement changes.
- Upsert `sbt_store_events` idempotently using RTDN/message id.
- Ignore stale notifications.

## Entitlement Algorithm

Granting states: `active`, `trial`, `grace`, `cancelled_active`.

Non-granting states: `billing_retry`, `account_hold`, `expired`, `revoked`,
`refunded`, `quarantined`.

Plan precedence: `unlimited > business > essential > free`.

Receipt Jar lifetime is independent of subscription tier. Apple and Google
billing records stay independently attributable; cross-platform access comes
only from the account-level entitlement response.

## Required Secrets, Reported By Category

- Apple App Store Connect issuer ID: required, not found locally.
- Apple App Store Connect key ID: required, not found locally.
- Apple private key: required, not found locally.
- Apple notification shared secret or equivalent verification config: required
  if used by the deployed verifier, not found locally.
- Google Play service-account JSON: required, not found locally.
- Google Cloud Pub/Sub topic/subscription for RTDN: required, not found locally.
- Supabase service-role key for verifier functions: required for server writes,
  not found locally.

## Local Blockers Before Remote Work

- There is no `supabase/` project directory, migrations directory, or edge
  functions directory in this restored workspace.
- The migration draft is not wired into Supabase CLI migration ordering.
- Staging credentials are not present in the current shell.
- Staging project identity has not been independently verified from Supabase
  metadata in this task.
