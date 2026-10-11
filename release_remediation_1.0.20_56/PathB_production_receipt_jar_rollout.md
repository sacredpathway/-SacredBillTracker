# Path B - Production Receipt Jar Rollout Plan

Status: local-only proposal. No production mutation has been made.

## Production Gaps

Production project: `zziauybwemoiqfpidiur`

Present:

- `subscriptions`
- `record_verified_subscription`
- `current_subscription_tier`
- `subscription_products`
- `reward_entitlements`
- `sbt_reviewed_purchase_bindings`
- `verify-store-subscription` active, version 9, `verify_jwt=true`
- `store-notifications-apple` active, version 10, `verify_jwt=false`

Missing:

- `sbt_store_purchases`
- `sbt_store_events`
- `sbt_effective_entitlements`
- `sbt_record_verified_receipt_jar_purchase`
- `sbt_recalculate_effective_entitlements`

Production `subscription_products` also does not include
`com.sacredbilltracker.app.receiptjar.lifetime`.

## Required Database Contract

Apply the staging-proven additive contract to production after explicit
approval:

- Create `sbt_store_purchases` with provider/environment/product/status checks,
  unique `(provider, environment, provider_original_id)`, and Apple numeric
  transaction ID checks.
- Create `sbt_store_events` with unique `(provider, environment, event_id)`.
- Create `sbt_effective_entitlements` keyed by `account_id`.
- Enable RLS on all three tables.
- Grant service role `SELECT/INSERT/UPDATE` on the three tables.
- Grant authenticated `SELECT` only on `sbt_effective_entitlements`.
- Create owner-select RLS policy for `sbt_effective_entitlements`.
- Create `sbt_recalculate_effective_entitlements(p_account_id uuid)`.
- Create `sbt_record_verified_receipt_jar_purchase(...)`.
- Revoke function execute from `public`, `anon`, and `authenticated`.
- Grant function execute to `service_role`.

The SQL reference is the staging-proven file:
`SacredBillTracker/staging_only_receipt_jar_lifetime_contract_proposal.sql`.
Before production use, replace the staging guard with an explicit production
approval guard for `zziauybwemoiqfpidiur`.

## Required Verifier Delta

Deploy the local staging-proven `verify-store-subscription` implementation to
production only after the DB contract exists and smoke checks pass.

Required behavior:

- Route `operation == "receipt_jar_lifetime"` or product ID
  `com.sacredbilltracker.app.receiptjar.lifetime` to the lifetime verifier.
- Verify Apple signed transaction JWS or server-side transaction lookup.
- Enforce bundle ID `com.sacredbilltracker.app`.
- Enforce Apple environment requested by the client.
- Enforce product ID, non-expiring non-consumable shape, revocation/refund
  status, and app account token ownership.
- Persist through `sbt_record_verified_receipt_jar_purchase`.
- Return an authoritative snapshot with independent `receipt_jar_lifetime`.
- Preserve legacy subscription behavior through `record_verified_subscription`.

Production secrets already include Apple and Supabase secret names required by
the current production subscription verifier. Values were not read or changed.

## Notification Delta

Production `store-notifications-apple` v10 currently validates only:

- `essential_monthly_499`
- `business_monthly_999`
- `unlimited_monthly_1499`

It also requires subscription `expiresDate`, so it is not ready for a
non-consumable Receipt Jar transaction. Path B requires a notification update
that recognizes Receipt Jar non-consumable transaction payloads and routes
refund/revoke events to `sbt_record_verified_receipt_jar_purchase` instead of
`record_verified_subscription`.

## Product Registry

If the production verifier continues using `subscription_products` for legacy
subscription registry only, Receipt Jar does not need to be inserted there for
the lifetime route. If any production notification or snapshot path is extended
to require registry membership, add a dedicated registry row only after its
feature-key semantics are defined. Do not map Receipt Jar to a plan tier.

## Real Apple Sandbox QA Minimum

Before production submission under Path B:

1. First purchase of `com.sacredbilltracker.app.receiptjar.lifetime`.
2. Production-like staging backend persistence through the lifetime RPC.
3. Authoritative response sets `receipt_jar_lifetime=true`.
4. Duplicate replay/idempotency.
5. Restore purchases.
6. Logout/login persistence.
7. Fresh device/session restore.
8. Owner conflict with a second staging account.
9. Confirm no subscription tier grant.
10. Confirm no fabricated expiration.

Refund/revocation can be separately classified if Apple sandbox tooling cannot
exercise them safely, but server-side synthetic coverage is not a substitute for
the purchase/restore test.

## Rollback Plan

Function rollback:

- Redeploy the previous production `verify-store-subscription` bundle/version if
  captured before rollout.
- Do not delete lifetime tables until no deployed function references them.

Database rollback:

- Preferred rollback is disabling client exposure and leaving additive tables in
  place.
- Destructive rollback, only before real customer data exists:
  drop the two lifetime RPCs, revoke grants, drop `sbt_effective_entitlements`,
  `sbt_store_events`, and `sbt_store_purchases`.

Notification rollback:

- Revert `store-notifications-apple` to the prior production bundle/version.
- Apple may retry notifications; make rollback idempotent and safe for duplicate
  delivery.

## Remaining Path B Blockers

- Explicit approval to mutate production.
- Production SQL migration execution.
- Production verifier deployment.
- Production notification update/deployment if Receipt Jar can be refunded or
  revoked before the next backend release.
- App Store Connect Receipt Jar product readiness.
- Real Apple sandbox purchase/restore QA.
