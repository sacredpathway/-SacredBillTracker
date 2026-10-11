# Path A - Receipt Jar Production Release Gate

Status: local-only preparation.

Purpose: hide/disable Receipt Jar in production Release builds until the
production lifetime backend contract and real Apple sandbox QA are complete.

## Gate

`ReceiptJarReleaseGate.isEnabled` is compile-time enabled only for:

- `DEBUG`
- `SBT_STAGING_ACCEPTANCE`
- `SBT_RECEIPT_JAR_PRODUCTION_ENABLED`

Normal App Store Release builds do not define any of those symbols, so the
default is disabled.

## Covered Surfaces

- Settings no longer shows the Receipt Jar section when the gate is disabled.
- `ReceiptJarView` fails closed if it is reached by future/stale navigation.
- `SubscriptionManager.receiptJarProduct` returns `nil` when disabled.
- `SubscriptionManager.hasReceiptJar` cannot become true when disabled.
- `ProductID.all` filters the Receipt Jar product from StoreKit product loading.
- Offline entitlement validation rejects Receipt Jar entitlements when disabled.
- StoreKit transaction scanning uses the filtered product list.

## App Store Impact

Hiding Receipt Jar changes shipped binary behavior. An already-uploaded build
cannot be modified in App Store Connect, so this path requires a new archive and
new uploaded build. Because build 56 already exists as the current release
candidate, the next upload should use build 57 after explicit approval.

Receipt Jar IAP metadata can remain unsubmitted/unattached while the binary
does not expose, request, or sell the product. Review notes and screenshots
should not mention Receipt Jar for the Path A submission.

## Remaining Path A Blockers

- Explicit approval to increment the build number.
- Rebuild/archive/export/upload a new binary after approval.
- App Store Connect selection of the new build and final metadata review.
