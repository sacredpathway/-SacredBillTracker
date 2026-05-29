# DEV MODE RESTORED — Checklist

**Use this AFTER Xcode is reinstalled.** Each step is copy-paste safe. Stop at the first FAIL and report it.

---

## Pre-flight

- [ ] Xcode installed (`xcode-select -p` returns a path).
- [ ] iOS 17+ simulator available (iPhone 17 Pro Max recommended for parity with screenshots).
- [ ] Project opens cleanly:
  ```bash
  open "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER/SacredBillTracker.xcodeproj"
  ```
- [ ] Backup folder still present:
  ```bash
  ls "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER/_RECOVERY_BACKUP_20260506_140850/"
  ```

---

## Build & launch (DEBUG)

- [ ] Scheme: `SacredBillTracker`.
- [ ] Configuration: **Debug** (Product → Scheme → Edit Scheme → Run → Build Configuration = Debug).
- [ ] Destination: **iPhone 17 Pro Max** simulator.
- [ ] Wipe simulator state first (clean repro):
  - Simulator menu → Device → Erase All Content and Settings.
- [ ] **Cmd + R** to build & run.
- [ ] Build result: **BUILD SUCCEEDED** (zero errors, zero new warnings).

---

## Functional verification

### Sign-in / launch state
- [ ] App launches to Sign In screen (no crash).
- [ ] Even **without signing in**, Bills tab populates with 7 fixtures (DEBUG-only auto-seed).
- [ ] After signing in with Apple, Bills tab still populates (auto-seed runs if remote is empty).

### Bills populated (expected fixtures)
- [ ] Rent — $1,650.00, due in 5 days, unpaid
- [ ] Car Note — $548.50, due in 12 days, unpaid
- [ ] Car Insurance — $182.40, paid recently
- [ ] Phone — $89.99, paid recently
- [ ] Electric — $156.78, **OVERDUE** by 3 days
- [ ] Internet — $79.99, due in 7 days
- [ ] Streaming — $45.99, paid recently

### Tabs / navigation
- [ ] **Dashboard** — stat cards non-zero (Due This Month, Paid, Overdue ≥ 1, Upcoming).
- [ ] **Bills** — list shows 7 items, sectioned by status.
- [ ] **Calendar** — bill markers appear on the correct days.
- [ ] **Reports** — category breakdown chart renders with data.
- [ ] **Settings** — scroll to bottom and confirm:
  - [ ] **Partner (DEBUG)** section visible with "Coming Soon" badge.
  - [ ] **Data → Reset with sample data (DEBUG)** button visible.

### Dev tools
- [ ] Settings → Reset with sample data (DEBUG) → Reset → bills replaced cleanly with the 7 fixtures.
- [ ] Settings → Partner Budgeting (DEBUG) → opens `PartnerBudgetingView`, no crash.
- [ ] Sign out → bills do NOT disappear in DEBUG (auto-seed re-fills); in Release this would empty.

### Empty-state regression check
- [ ] No tab shows the "No bills yet" empty state on a fresh DEBUG launch.
- [ ] Dashboard never reads $0.00 across the board on first run.

---

## Release-build sanity (do NOT submit, just verify isolation)

- [ ] Switch scheme to **Release** (Edit Scheme → Run → Build Configuration = Release).
- [ ] Build succeeds.
- [ ] Auto-seed code is excluded — `SampleData` symbol unreachable from Release call sites.
- [ ] Switch back to **Debug** before continuing dev work.

---

## If anything fails

1. Capture the exact build error or screenshot.
2. **Do not** keep editing Release-path files.
3. Roll back to backup:
   ```bash
   cd "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER"
   rm -rf SacredBillTracker SacredBillTracker.xcodeproj
   cp -R _RECOVERY_BACKUP_20260506_140850/SacredBillTracker .
   cp -R _RECOVERY_BACKUP_20260506_140850/SacredBillTracker.xcodeproj .
   ```
4. Report what failed before retrying.

---

## Hands-off list (still HALTED)

- App Store Connect submissions
- TestFlight uploads
- Version / build number changes
- Screenshot regeneration
- App Store metadata edits

Do not resume any of the above without explicit approval.
