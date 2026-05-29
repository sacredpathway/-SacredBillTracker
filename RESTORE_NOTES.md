# RESTORE NOTES — Sacred Bill Tracker

**Date:** 2026-05-06
**Mode:** DEBUG-only restoration. **Release / App Store behavior UNCHANGED.**
**Status:** App Store / TestFlight submission **HALTED** by user request.

---

## 1. What broke

The codebase was **not** missing files. All modules intact: Dashboard, Bills, Calendar, Reports, Loads, Partner, Paywall, Auth, Settings, Account, Components, Models, Services, DesignSystem, StoreKit.

What broke was **runtime behavior in DEBUG**. Three release-prep additions caused the simulator to boot empty:

1. `BillStore.bootstrap()` added a hard guard — no auth user → `bills = []`.
2. `purgeLegacyDemoBillsIfNeeded` ran on every boot AND on every realtime event, deleting any v1.0 demo-signature bills from Supabase.
3. No DEBUG auto-seed path — fresh simulator runs always showed an empty state.

Result: Dashboard/Bills/Calendar/Reports all read empty in dev. Partner Budgeting (DEBUG) link and "Reset with sample data (DEBUG)" button were still present in Settings.

---

## 2. Files touched (DEBUG-only edits)

### `SacredBillTracker/Services/BillStore.swift`
- **`bootstrap()`** — wrapped both branches in `#if DEBUG / #else / #endif`:
  - Signed-out + DEBUG → auto-seed `SampleData.bills()` (7 fixtures).
  - Signed-out + Release → original hard guard (`bills = []`).
  - Signed-in + DEBUG → if remote returns empty, seed `SampleData.bills()` and persist; otherwise show what loaded. Legacy demo purge **skipped**.
  - Signed-in + Release → original `purgeLegacyDemoBillsIfNeeded(in: loaded)` path.

### `SacredBillTracker/SacredBillTrackerApp.swift`
- **`handleUserChange(_:)`** — wrapped the post-`refreshFromRemote()` block in `#if DEBUG / #else / #endif`:
  - DEBUG → if remote empty, call `store.reload()` (which seeds via `bootstrap`); else `store.replace(bills: fresh)`. Realtime callback updates the store directly. **No purge.**
  - Release → original behavior: `purgeLegacyDemoBillsIfNeeded` after refresh, plus realtime callback that re-purges on every push.

### Files NOT modified (intentionally)
- `Services/SampleData.swift` — already `#if DEBUG`-wrapped, fine as-is.
- `Services/LegacyDemoBills.swift` — needed by Release purge path, untouched.
- `Services/CachingBillRepository.swift` — `migrateLocalToRemoteIfNeeded` legacy filter still runs (harmless in DEBUG since fixtures don't match v1.0 signatures).
- `Views/Settings/SettingsView.swift` — already had Partner (DEBUG) link + Reset-with-sample-data (DEBUG) button. No edits needed.
- `SacredBillTracker.xcodeproj/project.pbxproj` — untouched.

---

## 3. Compile-time isolation guarantee

Every dev-mode change sits inside `#if DEBUG` blocks. The Release configuration:
- Keeps the hard auth guard.
- Keeps `purgeLegacyDemoBillsIfNeeded` calls on bootstrap and on every realtime push.
- Keeps the `migrateLocalToRemoteIfNeeded` legacy filter.
- Does **not** link `SampleData` (the type itself is `#if DEBUG`).

`#if DEBUG` / `#else` / `#endif` pair count: **6/6 balanced**. Static check passed.

---

## 4. Backup location (DO NOT DELETE)

```
/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER/_RECOVERY_BACKUP_20260506_140850/
```

Contains a full snapshot of `SacredBillTracker/` and `SacredBillTracker.xcodeproj/` taken **before** any restoration edits. Marked read-only. See `DO_NOT_DELETE.txt` inside the folder.

App Store assets preserved (symlinked, originals untouched) in:

```
/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER/_APPSTORE_ASSETS_PRESERVED_20260506/
```

Linked folders: `AppStoreMockups_DRAFT`, `AppStoreMockups_DRAFT_SBT`, `AppStoreScreenshots`, `AppStoreScreenshots_NEW`, `FINAL_SUBMISSION`, `RealSimulatorScreenshots`, `RealSimulatorScreenshots_SBT`, `RealSimulatorScreenshots_v2`, `SacredBillTracker_AppStoreScreenshots_FINAL`, `_proof`, `_real_screens`.

---

## 5. Rollback (if anything looks wrong)

```bash
cd "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER"
rm -rf SacredBillTracker SacredBillTracker.xcodeproj
cp -R _RECOVERY_BACKUP_20260506_140850/SacredBillTracker .
cp -R _RECOVERY_BACKUP_20260506_140850/SacredBillTracker.xcodeproj .
```

That returns you to the exact pre-restoration state.

---

## 6. Outstanding blocker

**Xcode is not installed on this Mac.** Live simulator verification deferred. See `DEV_MODE_CHECKLIST.md` for the verification steps to run after Xcode is reinstalled.

---

## 7. Hands-off until further notice

- App Store Connect actions: **HALTED**.
- TestFlight submissions: **HALTED**.
- Version/build number bumps: **HALTED**.
- Screenshot regeneration / metadata edits: **HALTED**.

Resume only after explicit user approval.
