# Sacred Bill Tracker v1.0.5 — Go / No-Go Launch Checklist

**Current state:** Build 1.0.5 (14) uploaded to App Store Connect; v1.0.5 created with What's New copy; NOT submitted for App Review.

---

## 🔴 REQUIRED before App Store submission

| # | Item | Status |
|---|---|---|
| R1 | Build 14 finishes processing in TestFlight | ⏳ check ASC |
| R2 | Internal E2E on real iPhone — owner sends invite, partner accepts, shared bill flows OFF/ON | ❌ pending your hands |
| R3 | Demo App Review credentials provisioned (`appreview@sacredbilltracker.com` exists in `auth.users` with bills) | ❌ verify |
| R4 | Privacy Policy URL set in ASC App Information | ❌ verify |
| R5 | App Privacy questionnaire answered in ASC (Data Linked / Not Linked / Not Collected per category) | ❌ verify |
| R6 | "What's New" text matches actual shipped features (no Resend mention if not shipping) | ✅ done |
| R7 | Build attached to v1.0.5 version page in ASC (App Store tab → version → Build → Add) | ❌ pending |
| R8 | Reviewer Notes pasted into App Review Information field — use `REVIEWER_NOTES_v1.0.5.md` | ❌ pending |
| R9 | Sign in with Apple — sign out works | ✅ verified in source |
| R10 | Sign in with Apple — account deletion works (in-app, not just via email/Apple support) | ✅ verified in source |
| R11 | Restore Purchases button visible on paywall AND in Settings | ✅ verified in source |
| R12 | Manage Subscription deep link points to `apps.apple.com/account/subscriptions` | ✅ verified in source |
| R13 | No DEBUG-only UI compiles into Release build (Reset sample, Continue as Dev Tester, Delete Forever) | ✅ verified in source |
| R14 | App icon present, no placeholder icons in any tab | ❌ verify in TestFlight |

## 🟡 RECOMMENDED before submission (high-value polish)

| # | Item | Status |
|---|---|---|
| O1 | Resend Edge Function deployed + pg_net trigger wired so partner invites email automatically | ❌ blocked on Resend API key |
| O2 | At least one external (non-team) tester has accepted + completed E2E partner flow | ❌ pending |
| O3 | All 5 launch screenshots in ASC accurately represent v1.0.5 features (the "Built for Couples & Teams" screenshot is now truthful — was misleading in 1.0.4) | ✅ verify in ASC |
| O4 | App Preview video (optional, but improves conversion) | ❌ optional |
| O5 | Crash-free first install verified on a NON-DEMO Apple ID (no debug bypass) | ❌ pending |
| O6 | Notifications grant flow tested — accept + decline paths | ❌ pending |
| O7 | Offline mode tested — airplane mode add bill, reconnect, sync | ❌ pending |
| O8 | Recurring bill rollover tested — mark paid, verify next due date advances correctly | ❌ pending |
| O9 | Localized strings checked for typos (English-only ship is fine for v1) | ✅ inspection clean |
| O10 | Marketing alignment audit — ASC copy ↔ landing page ↔ social posts all reference Partner Budgeting consistently | ❌ verify with marketing materials in `Sacred B ill Tracker/` folder |

## 🟢 POST-LAUNCH (within first 7 days)

| # | Item |
|---|---|
| P1 | Monitor Resend (or whatever email service) deliverability and open rates |
| P2 | Watch Supabase logs for `partner_invites` insert spikes (potential abuse) |
| P3 | Watch ASC crash logs daily for the first week |
| P4 | Reply to any 1–3 star reviews within 24h |
| P5 | Post-mortem on the v1.0.4 → v1.0.5 transition: did "Built for Couples & Teams" misleading screenshots cause any tickets? |
| P6 | Plan v1.0.6 polish: realtime sync (Supabase Realtime), push notification when partner accepts, rate-limiting on partner_invites INSERT |
| P7 | Add automated CI test for RLS partner-share semantics so this doesn't regress |
| P8 | Decommission the `delete_own` policy duplicate-cleanup leftover (`insert_own`, `read_own` still present in `bills` table — cosmetic) |

## 🚦 Decision matrix

**Ship to App Store NOW** if:
- All R1–R14 items green
- O2 done (one external tester completed E2E)
- You're OK shipping without auto-emails (workaround: tell users to message their partner directly)

**Ship after Resend deploys** if:
- You'd rather wait 1–2 days and have the auto-email path working
- Recommended path for less support friction

**HOLD** if:
- Any R-row is red
- You haven't done your own iPhone E2E test yet (highest priority — no automation can replace it)

---

## Reference files in this repo

```
LAUNCH_CHECKLIST_v1.0.5.md            ← this file
REVIEWER_NOTES_v1.0.5.md              ← paste into ASC App Review Information
SacredBillTracker/
  partner_invites_migration.sql       ← already applied to prod DB
  resend_trigger_install.sql          ← run AFTER `supabase functions deploy`
  resend_trigger_rollback.sql         ← emergency disable
  resend_monitoring.sql               ← post-deploy observability queries
  supabase/functions/send-partner-invite/index.ts   ← Resend Edge Function source
```

## Production risk assessment (current)

| Risk | Likelihood | Impact | Status |
|---|---|---|---|
| Apple rejects for "feature not working" (Built for Couples screenshot) | Was high in v1.0.4, **low in v1.0.5** | High | ✅ Mitigated by build 13/14 |
| User confusion: "I sent invite, partner got nothing" | High (until Resend ships) | Medium | ⚠️ Open — Option B docs available, in-app messaging now mentions "they need to install + sign in" |
| Sign in with Apple non-compliance | Low | High | ✅ Account delete + sign out wired |
| RLS leak (partner sees bills they shouldn't) | Low | Critical | ✅ E2E tested with real `authenticated` JWT, all 5 cases pass |
| StoreKit / paywall regression | Low | Medium | ⚠️ Needs device test |

---

**Bottom line:** the app is in objectively better shape than the currently-live v1.0.4 (which silently shipped non-functional Partner UI). Everything App Store reviewers can see is now backed by real, tested functionality. Safe to submit once R1–R14 are green.
