# Sacred Bill Tracker 1.0.20 (56) Local Deployment Readiness

Prepared locally only. No database migration, Supabase deployment, secret update,
App Store Connect change, Play Console change, upload, submission, release,
commit, or push occurred.

## Local Functions Prepared

- `verify-store-subscription`: recovered from prior legitimate source and lightly
  modernized to recognize the Receipt Jar product in its local product registry.
- `store-notifications-apple`: recovered unchanged from prior legitimate source.
- `store-verification-google`: newly created local Edge Function entrypoint.
- `store-notifications-google`: newly created local Edge Function entrypoint.
- `_shared/entitlement-engine.mjs`: newly created pure entitlement rules.
- `_shared/apple-lifetime-policy.mjs`: newly created Receipt Jar lifetime policy.
- `_shared/google-policy.mjs`: newly created Google verification mapping.
- `_shared/rtdn-policy.mjs`: newly created RTDN envelope parsing/idempotency helpers.

## Required Function Deployments

1. `verify-store-subscription`
2. `store-notifications-apple`
3. `store-verification-google`
4. `store-notifications-google`

Deploy only to staging first, after explicit approval.

## Secret and Config Requirements

Present in staging by name from prior read-only audit:

- `APPLE_BUNDLE_ID`
- `APPLE_ISSUER_ID`
- `APPLE_KEY_ID`
- `APPLE_PRIVATE_KEY`
- `SBT_APPLE_NEW_BINDINGS_ENABLED`
- `SBT_GOOGLE_IOS_ENTITLEMENTS_ENABLED`
- `SBT_SANDBOX_APPLE_BROKER_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_DB_URL`
- `SUPABASE_JWKS`
- `SUPABASE_PUBLISHABLE_KEYS`
- `SUPABASE_SECRET_KEYS`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_URL`

Missing or not confirmed in staging:

- `GOOGLE_SERVICE_ACCOUNT_JSON`
- `GOOGLE_PACKAGE_NAME`
- `GOOGLE_PLAY_RTDN_SUBSCRIPTION`
- `GOOGLE_PLAY_RTDN_SHARED_TOKEN`
- Authenticated Google Pub/Sub push audience/service-account settings if replacing
  the shared-token staging stopgap.

## Apple Notification Endpoint

Configure App Store Server Notifications V2 to the deployed staging
`store-notifications-apple` URL only after the function is deployed and verified.
The handler must verify signed payloads and dedupe notification UUIDs before
reconciling purchase state.

## Google API and RTDN Requirements

- Google Play Developer API service account with Android Publisher access.
- Package name must match `com.sacredbilltracker.app`.
- Pub/Sub topic/subscription for Google RTDN.
- Authenticated push verification should replace shared-token staging auth before
  production consideration.
- RTDN must enqueue/reconcile only; it must not grant based solely on notification
  type.

## Android Staging Requirements

- Inject only public staging anon configuration into debug/staging builds.
- Keep service-role secrets server-side only.
- Release builds fail closed for staging config.
- Production cross-platform/account entitlement behavior remains off until
  separately approved.

## Recommended Deployment Order

1. Confirm staging schema/RPC contracts and service-only grants.
2. Configure missing staging Google secrets only after approval.
3. Deploy `verify-store-subscription` to staging.
4. Deploy `store-verification-google` to staging.
5. Deploy `store-notifications-apple` to staging.
6. Deploy `store-notifications-google` to staging.
7. Configure Apple ASSN V2 staging endpoint.
8. Configure Google RTDN Pub/Sub push to staging endpoint.
9. Run the 25-row staging sandbox QA matrix.
10. Only after observed pass evidence, consider production planning.

## Rollback Considerations

- Edge Functions can be rolled back by redeploying the previous version.
- Keep old function bundles and deployment IDs before each deploy.
- Do not alter production secrets or functions during staging validation.
- If ownership conflicts appear, stop and preserve rows/events for audit rather
  than transferring ownership.

## QA Scenarios Unlocked After Deployment

- iOS purchase/restore/current entitlement refresh.
- Apple renewal/expiration/revocation/refund notification paths.
- Android purchase/restore through server-authoritative verification.
- Google RTDN lifecycle events after Pub/Sub setup.
- Cross-device same-account entitlement recovery.
- Conflict/quarantine checks for duplicate ownership attempts.
- Receipt Jar lifetime verification on Apple after the product exists in ASC.

## Remaining Blockers

- Google staging secrets and Pub/Sub are missing/unconfirmed.
- Apple and Google remote endpoints are not configured in this local-only pass.
- Receipt Jar requires real approved store product configuration before sandbox
  purchase QA.
- Staging DB was not mutated, so new function paths still require staged deploy
  and live fixture validation.
- iOS simulator test run was interrupted by Xcode worker materialization failure.
