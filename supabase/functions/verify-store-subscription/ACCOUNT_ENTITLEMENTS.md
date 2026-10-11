# Account entitlement recovery — source only

Do not deploy this directory alone. The reviewed-binding schema, historical ownership audit, Google product registry/tier mappings and actual Deno/Postgres integration must be validated first.

## Historical model and evidence limits

The recovered Git checkout has one reachable commit. At that baseline, SubscriptionManager's appAccountToken parameter was optional; only supplied values were passed to StoreKit. The legacy Pro/Focus+ path could therefore create an unbound purchase. originalID identified subscription lineage, transaction.id identified the renewal/current transaction; restore used AppStore.sync plus StoreKit enumeration. The prior tier manager granted local verified StoreKit access and promoted from current_subscription_tier.

The recovered deployed Apple function accepted original_transaction_id from the request, fetched Apple state, decoded JWS without signature verification, and wrote owner_id from the caller without comparing appAccountToken. It also probed environments and could treat expired auto-renewing subscriptions as active. Consequently its owner_id/raw_payload rows are discovery hints, not sufficient ownership proof.

The recovered record_verified_subscription RPC stores platform, owner, product, original/current IDs, purchase_token, expiry, last_verified_at and raw_payload; conflict handling does not itself establish owner identity. current_subscription_tier aggregates both platforms by owner, supporting the existing cross-platform product policy. The recovered Google route similarly lacks an external-account comparison. The separate staging HMAC binding scheme is not proof of the historical production Android scheme and is not assumed here.

No actual historical customer receipt corpus, independently authenticated account-to-purchase history, or verified notification corpus was available in the recovered files. No automatic owner backfill is safe on this evidence.

## Secure migration

1. Independently review ownership evidence and approve precisely one (platform, environment, store-key, owner) row with an audit reference. Do not seed this table merely by copying subscriptions.owner_id, a user-supplied transaction ID, or an unverified receipt. Unresolved users require an ownership review; knowing an original ID does not qualify.
2. The authenticated handler fetches CURRENT store state and verifies Apple's signed transaction/renewal chain, bundle, environment, product, purchased ownership and timestamps.
3. Only a tokenless, currently active/trial/grace Apple purchase can claim a previously approved binding. The SQL function locks that existing approval row; it cannot insert an approval or change its owner. Claiming is idempotent. Expired/revoked purchases cannot claim; previously claimed ones can return negative state to invalidate cached access.
4. Restore can submit a locally verified unbound original ID as a discovery hint. The server still requires independently reviewed approval. Server discovery includes approved bindings, allowing restoration on another device without a populated local transaction cache.
5. A conflicting signed account token does not override an existing reviewed owner. This code does not call Apple's Set App Account Token endpoint, which can overwrite tokens. Any future store-side token assignment requires separate ownership review and reconciliation.

SQL permissions prevent client inserts, updates, deletes and RPC calls. A service operator can insert reviewed evidence; service clients cannot update/delete owners. Database-administrator powers are outside this client threat model. Real PostgreSQL concurrency/RLS execution has not yet been tested; in-memory tests exercise the handler contract.

Apple documentation: https://developer.apple.com/documentation/appstoreserverapi/appaccounttoken

## Google and additive unified contract

The iOS request retains operation=entitlement_snapshot for compatibility, but the deployed adapter now supplies both Apple verification and Google account aggregation. Apple entitlements remain in entitlements with source_platform/binding_state metadata. New account_sources entries retain Google's product, opaque subscription UUID, tier, environment, verified time, expiry and negative state. No purchase token, Apple transaction substitute or artificial Apple product is returned.

Google discovery uses server-known owner/platform/environment rows only. Each purchase token is reverified through subscriptionsv2 using the configured package and existing service credentials. The exact historical obfuscatedExternalAccountId must match an independently reviewed, already-claimed binding. The SHA-256 token key is server-only and is not sent to iOS. Missing evidence, unknown products, ambiguous mappings and API failures cannot become verified Free. Registry feature_key joins subscription_tier_ranks; no guessed Android-product-to-iOS mapping is added. Only established Essential/Business/Unlimited ranks are accepted; unmapped/add-on products require a reviewed mapping before rollout.

Expired, pending, hold and paused purchases deny access. Canceled but paid-through purchases retain access to verified expiry. Refund/revocation denial relies on Google's current expired state or expiry. There is no fabricated refunded field and no direct Voided Purchases integration in this change; end-to-end refund propagation still requires validation.

Google documentation: https://developer.android.com/google/play/billing/security

The envelope verification timestamp is the earliest actual store verification in the batch. Complete verification is required: one unverified source prevents a successful replacement snapshot. iOS preserves optional account_sources, caches it with the authenticated owner in device-only Keychain, and computes a separate account tier without inserting Google products into Apple purchase IDs. Rewards remain distinct. All sources share the same 72-hour maximum; verified expiry can end access earlier. Logout/account switch/revision guards and cache invalidation remain in force.

## Deployment blockers

- Review and populate real ownership evidence; do not invent legacy owners or a production Google obfuscation scheme.
- Execute schema/RLS/concurrency tests against isolated PostgreSQL and validate the Deno/Apple SDK bundle.
- Verify actual production product registry mappings and real authenticated store responses without manufacturing purchases.
- Finish app-level simulator tests and simulator Release build after storage headroom is established.
- Deployment, migration execution, Cloud triggers and release actions are outside this validation change; none has occurred.
