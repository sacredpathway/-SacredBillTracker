# Sacred Bill Tracker — App Review Notes (v1.0.5, build 14)

## What this app is
A simple personal bill-tracking app for households and freelancers. Users manually
enter bills (rent, electric, internet, etc.), see what's due, and get local
reminder notifications. Optional partner sharing lets two users see selected bills.

## What this app is NOT
- **NOT a banking app.** No bank connections, no Plaid, no card linking.
- **NOT a payments app.** We do not transfer money or pay bills on the user's behalf.
- **NOT financial advice.** Reports are simple totals/cash-flow visualizations of
  data the user typed in themselves.

## Demo account for review
For convenience, please use either path:

- **Sign in with Apple** — supported and is the primary path.
- **Continue with Email** (if shown) — credentials below.

```
Email:    appreview@sacredbilltracker.com
Password: (provided in the App Review portal field below)
```

The demo account already has sample bills. If reports/dashboard appear empty,
go to Settings → "Reset with sample data" (only visible in App Review builds).

## Sign in with Apple (Apple guideline 5.1.1)
- In-app **Sign Out** is in Settings → Sign Out.
- In-app **Account Deletion** is in Settings → Delete Account. This permanently
  removes the user's Supabase account and all of their bill data. Calls the
  `delete_user_account` RPC server-side.

## Subscriptions / paywall
- Free tier: capped at 5 household bills.
- Pro tier: unlimited bills + business-bills feature, monthly + yearly options.
- Native StoreKit 2.
- **Restore Purchases** in Settings + on the paywall.
- **Manage Subscription** opens `https://apps.apple.com/account/subscriptions`.

## Partner Budgeting (new in v1.0.5) — how it works for review
1. User A taps Settings → Partner Budgeting → enters User B's email → Send Invite.
   This inserts a row into the `partner_invites` table with status `pending`.
2. User B installs the app and signs in with Apple using **the same email** that
   was invited. Row-Level Security on the `partner_invites` table matches the
   pending invite to User B by email.
3. User B taps Settings → Partner Budgeting and sees the pending invite. They
   tap to accept, which calls the `accept_partner_invite` RPC. Status flips to
   `connected` and the partnership is recorded.
4. On any bill, User A or B can toggle **"Share with partner"**. Only bills with
   that toggle ON are visible to the partner under the **Shared Bills** tab in
   Bills. Toggling off immediately removes partner access. Bills do not move
   accounts — each user retains ownership of their own data.

To test as the reviewer:
- Add a bill, toggle Share with partner ON, save. The bill appears in the
  Shared Bills tab once a partner is connected.
- The Shared Bills tab is empty for any account without a connected partner.

## Privacy
- See Privacy Policy URL in App Information.
- The app stores: name, email (from Sign in with Apple), bills the user enters,
  optional shared-with-partner flag per bill.
- The app does NOT collect: location, contacts, banking data, payment instruments,
  device sensors. No analytics SDK is bundled.
- Personally identifiable bill content is encrypted in transit and stored in
  Supabase. Each user's data is isolated by Row-Level Security keyed to their
  Apple-issued user ID.

## Notifications
- Local-only `UNUserNotification` reminders for upcoming bills.
- Permission requested on first add-bill or first Settings visit.
- No push notifications, no marketing pings.

## Known minor things
- Sharing is "pull-based" — when User A toggles a bill share, User B's app shows
  it after a manual pull-to-refresh. We don't push realtime updates yet.
- Partner invite emails are **not yet auto-sent** (Resend integration pending).
  The flow tells the inviting user to share the install link out-of-band. This
  is intentional for v1.0.5; nothing breaks because of it.

## Contact
- Support email: sacredbilltracker@gmail.com
- Maintained by Sacred Pathway LLC
