# DEV MODE Verification — 2026-05-06

**Result: PASS (with one config fix applied + one minor known issue)**

Build configuration: **Debug** (iPhone 17 Pro Max, iOS 26.4 simulator).
App Store / release work remains **HALTED**.

---

## Config fix applied during this run

The Run scheme's Build Configuration was set to **Release**, not Debug. That's why the first build hid all `#if DEBUG` Settings sections. Fixed via Xcode → Product → Scheme → Edit Scheme → Run → Info → Build Configuration: **Debug**. Rebuilt clean. No code changed.

---

## Checklist results

| # | Step | Result | Notes |
|---|---|---|---|
| 1 | Build clean (DEBUG) | PASS | BUILD SUCCEEDED, only pre-existing deprecation warnings (`postgresChange(_:schema:table:filter:)`, `subscribe()` in `BillsRealtimeService`) |
| 2 | App launches | PASS | Cold launch into Dashboard, no crash |
| 3 | Bills populate | PASS | 7 sample bills loaded, total $2,753.65 household |
| 4 | Dashboard works | PASS | Quote, brand header, This Month $2,753.65, Overdue=1, Upcoming=3 |
| 5 | Bills tab | PASS | List shows Electric (overdue), Rent, Car Insurance (paid), Car Note, Phone (paid), Streaming, Internet — filters All/Household/Business + All/Unpaid/Paid/Overdue |
| 6 | Calendar tab | PASS | May 2026 grid with bill markers on due dates |
| 7 | Reports tab | PASS | Category breakdown: Rent $1,650 / Transportation $548.50 / Insurance $182.40 / Utilities $156.78 / Phone $89.99 / Subscriptions $45.99 / Internet $79.99 |
| 8 | Settings — Partner (DEBUG) | PASS | Section visible with "Coming Soon" badge |
| 9 | Settings — Partner Budgeting view | PASS | Opens cleanly: hero, description, "Partner invites are coming soon", invite-by-email form, partner-status section |
| 10 | Settings — Reset with sample data (DEBUG) | PASS | Button visible in Data section |
| 11 | Empty-state regression | PASS | No tab hits an empty-state screen on fresh DEBUG launch |
| 12 | Account info | PASS | Signed in as Demarquis Hinton, Pro (Yearly), Version 1.0.3 (7) |

---

## Known minor issue (non-blocking)

**Internet bill ($79.99) name+amount matches a v1.0 legacy demo signature** in `Services/LegacyDemoBills.swift`. Even though the BillStore purge is now `#if DEBUG`-skipped, `CachingBillRepository.migrateLocalToRemoteIfNeeded` still calls `LegacyDemoBills.filterOut(...)` on the local cache the first time a user signs in. This caused the Release-config first run to under-report by $79.99 (6 bills shown instead of 7).

After switching to Debug config and rebuilding, all 7 bills displayed correctly.

**Recommended one-line fix on next pass** (do NOT apply now per user instruction): wrap the `LegacyDemoBills.filterOut` call in `migrateLocalToRemoteIfNeeded` with `#if !DEBUG`. Or change Internet's seed amount from `79.99` to e.g. `79.98` to dodge the signature. Either is safe; will not touch Release.

---

## What I did NOT touch (per user directive)

- App Store Connect — no actions
- TestFlight — no uploads
- Release build configuration — verified setting only, did not edit
- Version / build numbers — unchanged (still 1.0.3 (7))
- Screenshots — only diagnostic captures of this verification, none added to App Store assets folders
- Metadata — untouched

---

## Files referenced

- `RESTORE_NOTES.md` — what was restored
- `DEV_MODE_CHECKLIST.md` — checklist source
- `_RECOVERY_BACKUP_20260506_140850/` — pre-restore safety snapshot (preserved, marked DO_NOT_DELETE)
- `_APPSTORE_ASSETS_PRESERVED_20260506/` — App Store asset symlinks (originals untouched)
