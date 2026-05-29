# Partner Invite Email — Root Cause Report

**Date:** 2026-05-10  
**Reported symptom:** "Partner budgeting invite email was triggered from the app, but the recipient never received the email."  
**Severity:** No data loss. Misleading UX only.

---

## TL;DR
**No email-sending code is deployed.** The "delivery failure" is actually a "feature not built" scenario. Send Invite tap → DB row inserted → end. There is no Resend account, no Edge Function deployed, no `pg_net` extension, no trigger, no glue function. Recipient providers (Gmail/iCloud/Outlook) never had a chance because nothing left our backend.

## Hard evidence (from production Supabase, 2026-05-10)

| Diagnostic | Expected for working email | Actual |
|---|---|---|
| `partner_invites` row inserted | yes | ✅ yes (latest 01:55 today) |
| Trigger on insert that calls Edge Function | `trg_notify_partner_invite` | ❌ **NONE** — only the unrelated timestamp trigger |
| `pg_net` extension installed | yes | ❌ **NOT INSTALLED** |
| `notify_partner_invite()` function | yes | ❌ **NOT FOUND** |
| Edge Function `send-partner-invite` deployed | yes | ❌ NOT DEPLOYED (source committed at `supabase/functions/send-partner-invite/index.ts`, never run `supabase functions deploy`) |
| Resend account / API key | yes | ❌ NEVER PROVISIONED |

## Where the user-visible bug originates

In `PartnerService.sendInvite`, a successful Postgres INSERT returns `true`. The UI then renders an alert reading **"Invite sent to [email]."** That copy is wrong. The invite is *created*, not *sent*. No email leaves our infrastructure.

## Recommended permanent fix (build 15 must include)

### Code-side (already committed in repo as of this report)
1. Alert title changed from "Heads up" to "Invite created"
2. Alert body changed to honest copy: *"Heads-up: automatic emails are coming soon. For now, ask [email] to install Sacred Bill Tracker and sign in using exactly that email. The pending invite will appear in their Settings → Partner Budgeting screen."*
3. Always-visible banner on Partner Budgeting screen: *"Automatic invite emails are coming soon"* — sets expectations before the user taps anything
4. Banner removed at the same commit that deploys Resend (search for `emailPendingBanner` in `PartnerBudgetingView.swift`)

### Backend-side (manual, requires user)
1. Sign up at https://resend.com → API key
2. Verify a sender domain (or use `onboarding@resend.dev` for first test)
3. Run from your Mac terminal:
   ```bash
   cd "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER"
   supabase login
   supabase link --project-ref zziauybwemoiqfpidiur
   supabase secrets set RESEND_API_KEY=re_xxx \
                        FROM_EMAIL='SacredBillTracker <invites@yourdomain>' \
                        APP_DEEPLINK_BASE='https://sacredbilltracker.app/invite'
   supabase functions deploy send-partner-invite --no-verify-jwt
   ```
4. Tell me when done. I will run `resend_trigger_install.sql` from Chrome (creates `pg_net`, `notify_partner_invite()`, and `trg_notify_partner_invite`) — that closes the loop.
5. End-to-end smoke test: insert a test invite, watch `net._http_response`, watch Resend dashboard for delivery → bounce → recipient inbox.

### Post-deploy verification queries (file: `resend_monitoring.sql`)
- Last 20 outbound HTTP responses
- Failure rate over last 24h
- Per-day volume / abuse detection by inviter

## Why no points 1–8 apply right now

| Your point | Why it's moot |
|---|---|
| 1. API endpoint hit | The endpoint is the database INSERT, which IS being hit successfully. There's no email endpoint to verify yet. |
| 2. Resend API key / DNS / SPF / DKIM | No Resend account exists. |
| 3. Resend dashboard logs | No Resend account exists. |
| 4. Recipient email normalization | `PartnerService` lowercases on insert. Verified clean. |
| 5. Email template rendering | Template exists in `index.ts` but the function has never executed. |
| 6. Detailed logging | Pointless until pipeline exists. The Edge Function ALREADY logs to Supabase function logs once deployed. |
| 7. Silent error swallowing | Reviewed in source — none. The misleading "Invite sent" copy was the only deception, and that's now fixed. |
| 8. Test Gmail / iCloud / Outlook | Nothing has been emailed to any provider. |

## Build 14 vs Build 15

Build 14 in TestFlight today still says "Invite sent to X." That's misleading. **Do not promote build 14 to App Store production.** The code edits in this session land in build 15, which will:
- Show the email-pending banner
- Use honest "Invite created" alert wording
- Use new support email `sacredbilltracker@gmail.com`
- Keep all UX polish from this and previous sessions

When Resend deploys, build 16 (or whatever follows) removes the banner.

## Decision recommendation

**Hold App Store submission.** Build 15 — with honest copy + Resend deployed — is the first build that should be promoted to public release. Anything sooner ships a misleading invite UX that will generate support tickets.
