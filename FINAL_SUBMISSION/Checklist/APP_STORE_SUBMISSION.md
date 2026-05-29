# Sacred Bill Tracker — App Store Submission Pack

**Bundle ID:** `com.sacredbilltracker.app`
**Version:** 1.0  •  **Build:** 4
**Min iOS:** 17.0  •  **Devices:** iPhone + iPad
**Sign-in:** Sign in with Apple
**Monetization:** Auto-renewable subscriptions (Pro Monthly / Yearly, 7-day free trial)

---

## 1. Pre-flight Checklist (do these first)

- [ ] Apple Developer account active ($99/yr) — https://developer.apple.com/account
- [ ] App registered in App Store Connect with bundle ID `com.sacredbilltracker.app`
- [ ] Paid Apps Agreement signed — App Store Connect → Business → Agreements
- [ ] Banking + tax forms complete (required for paid subs)
- [ ] App Icon present at `Assets.xcassets/AppIcon.appiconset/app-icon-1024.png` (1024×1024, opaque, no alpha)
- [ ] Privacy policy live at `https://www.sacredpathway.org/sacred-bill-tracker-privacy`
- [ ] Terms of Use (EULA) URL — required for subscriptions
- [ ] Signing team selected in Xcode → Target → Signing & Capabilities

---

## 2. Build & Upload (exact steps)

```bash
# 1. Open project
open "SacredBillTracker.xcodeproj"
```

In Xcode:

- [ ] Select target `SacredBillTracker` → **Signing & Capabilities** → set Team
- [ ] Set destination to **Any iOS Device (arm64)**
- [ ] Bump build number if re-uploading: Target → General → Build → increment
- [ ] **Product → Archive**
- [ ] Window opens → **Distribute App** → **App Store Connect** → **Upload**
- [ ] Automatically manage signing → Next → Upload
- [ ] Wait ~10–30 min for build to finish processing in App Store Connect

---

## 3. App Store Connect — Metadata (copy-paste)

### App Information

| Field | Value |
|---|---|
| Name | `Sacred Bill Tracker` |
| Subtitle (30 chars) | `Household + Business Bills` |
| Primary Category | Finance |
| Secondary Category | Productivity |
| Bundle ID | `com.sacredbilltracker.app` |
| SKU | `SBT-IOS-001` |
| Content Rights | You own or have licensed all content |

### Promotional Text (170 chars)

```
Track every household and business bill in one app. Get reminders before due dates, see this month's cash flow at a glance, and never miss a payment again.
```

### Description (4000 chars max)

```
Sacred Bill Tracker is the simplest way to manage household AND business bills in one place — built for entrepreneurs, freelancers, owner-operators, and anyone juggling personal and company expenses.

WHY SACRED BILL TRACKER
• One app for both sides of your life — toggle between Household, Business, or All.
• See what's due today, this week, and this month at a glance.
• Never miss a payment — local reminders fire 0–14 days before due date.
• Beautiful Tree-of-Life design — calm, focused, no clutter.

CORE FEATURES
• Add bills with name, amount, due date, category, recurrence, auto-pay flag, and notes
• Mark bills Paid, Unpaid, or Overdue (overdue auto-detected)
• Dashboard: due today, due this week, overdue, upcoming, monthly totals split by household vs. business
• Monthly calendar with per-day bill markers
• Reports tab with monthly totals + category breakdown
• Smart filters across every screen
• Local notifications — fully configurable lead time
• Sign in with Apple — your data is yours
• Optional cloud sync across devices (Pro)

PRO FEATURES (7-day free trial)
• Unlimited bills (free tier limited to 5)
• Business bill tracking
• Reports + analytics
• Cloud sync across iPhone and iPad
• Priority support

PRICING
• Pro Monthly — $4.99 / month
• Pro Yearly — $39.99 / year (save 33%)
• 7-day free trial on both plans

Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Manage or cancel any time in Settings → Apple ID → Subscriptions.

Privacy: https://www.sacredpathway.org/sacred-bill-tracker-privacy
Terms (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

### Keywords (100 chars, comma-separated)

```
bill tracker,bills,budget,expenses,due date,reminder,household,business,finance,money,cash flow,debt
```

### Support URL

```
https://sacredbilltracker.com/
```

### Marketing URL (optional)

```
https://sacredbilltracker.com/
```

### Privacy Policy URL

```
https://www.sacredpathway.org/sacred-bill-tracker-privacy
```

### Copyright

```
© 2026 Sacred Bill Tracker
```

---

## 4. Screenshots Required

You MUST upload screenshots for these device sizes. Take from simulator: ⌘S in Simulator → saves to Desktop.

| Device | Resolution | Required? |
|---|---|---|
| iPhone 6.9" (iPhone 16 Pro Max) | 1320 × 2868 | YES |
| iPhone 6.7" (iPhone 15 Pro Max) | 1290 × 2796 | YES |
| iPad 13" (iPad Pro M4) | 2064 × 2752 | YES if iPad enabled |

Minimum 3 screenshots per size, max 10. Suggested order:
1. Dashboard (showing stats + brand header)
2. Bills list (filtered view)
3. Add Bill screen
4. Calendar view
5. Reports view
6. Paywall (Pro upgrade)

```bash
# Quick simulator boot for screenshot capture
xcrun simctl list devices available | grep "iPhone 16 Pro Max"
xcrun simctl boot "iPhone 16 Pro Max"
open -a Simulator
```

---

## 5. App Privacy (App Store Connect → App Privacy)

Click **Get Started** → answer:

| Question | Answer |
|---|---|
| Do you collect data? | **Yes** |
| Identifiers → User ID | Linked to user, used for App Functionality |
| User Content → Other (bills) | Linked to user, App Functionality |
| Contact Info → Email | Linked to user, App Functionality (Sign in with Apple) |
| Tracking? | **No** |
| Third-party data sharing? | **No** |

---

## 6. Subscriptions Setup (App Store Connect → Monetization → Subscriptions)

- [ ] Create Subscription Group: **Sacred Bill Tracker Pro** (group ID will appear after save)
- [ ] Copy that group ID into `SacredBillTracker/Services/StoreKit/ProductIdentifiers.swift` if it's a placeholder
- [ ] Add Subscription 1:
  - Reference Name: `Pro Monthly`
  - Product ID: `com.sacredbilltracker.app.pro.monthly`
  - Duration: 1 Month
  - Price: $4.99
  - Introductory Offer: 7 days FREE (Pay as you go OFF, Free)
- [ ] Add Subscription 2:
  - Reference Name: `Pro Yearly`
  - Product ID: `com.sacredbilltracker.app.pro.yearly`
  - Duration: 1 Year
  - Price: $39.99
  - Introductory Offer: 7 days FREE
- [ ] Both subscriptions: add **Localization** (English) — Display Name + Description (required)
- [ ] Add **Review Screenshot** for each subscription (1284×2778 or any iPhone screenshot of the paywall)
- [ ] Status must be **Ready to Submit** before you can attach to the build

### Subscription localization (copy-paste)

**Pro Monthly — Display Name:** `Pro Monthly`
**Pro Monthly — Description:** `Unlimited bills, business tracking, reports, and cloud sync. 7-day free trial, then $4.99/month.`

**Pro Yearly — Display Name:** `Pro Yearly`
**Pro Yearly — Description:** `Unlimited bills, business tracking, reports, and cloud sync. 7-day free trial, then $39.99/year (save 33%).`

---

## 7. App Review Information (App Store Connect)

### Sign-In Required?

**Yes** — uses Sign in with Apple. Reviewer can use Sign in with Apple directly OR provide a demo account.

### Demo Account (recommended — avoids reviewer rejection if they can't auth)

```
Email: appreview@sacredbilltracker.com
Password: ReviewPass2026!
```

(Create this in Supabase Auth ahead of time and seed it with 3–5 sample bills.)

### Notes for Reviewer (paste into App Review Notes box)

```
Sacred Bill Tracker is a personal-finance utility for tracking household and business bills.

DEMO ACCOUNT
Sign in with Apple is supported. For review convenience, you can also tap "Continue with Email" and use:
  Email: appreview@sacredbilltracker.com
  Password: ReviewPass2026!
This account has 5 sample bills pre-loaded.

SUBSCRIPTIONS
Pro features (unlimited bills, business tracking, reports, cloud sync) are gated behind an auto-renewable subscription.
- Pro Monthly: $4.99/mo, 7-day free trial
- Pro Yearly: $39.99/yr, 7-day free trial
Free tier supports up to 5 household bills, no business tracking, no reports.
Paywall is reachable from Settings → Upgrade to Pro and from any locked feature.

PRIVACY
Privacy policy: https://www.sacredpathway.org/sacred-bill-tracker-privacy
EULA: standard Apple EULA — https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

DATA STORAGE
Bills are stored locally by default; cloud sync (Supabase) is opt-in via Settings and only enabled for Pro subscribers.

NO ENCRYPTION beyond Apple's defaults — uses_non_exempt_encryption = NO in Info.plist.
```

### Contact Info

```
First Name: Demarquis
Last Name:  [your last name]
Phone:      [your phone]
Email:      demarquishinton@gmail.com
```

---

## 8. Export Compliance

In Xcode → Info.plist (or build settings), confirm:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

This skips the export-compliance question on every TestFlight upload.

---

## 9. Age Rating

App Store Connect → App Information → Age Rating → fill questionnaire. All answers should be **None** → result: **4+**.

---

## 10. Final Submission

- [ ] Build appears in App Store Connect → TestFlight tab → "Ready to Submit"
- [ ] Attach build to the 1.0 version: App Store tab → Build section → **+** → select build
- [ ] Attach both subscriptions to the version: In-App Purchases section → **+**
- [ ] Confirm screenshots uploaded for all required device sizes
- [ ] Fill App Review Information (demo account, notes)
- [ ] Click **Add for Review** → **Submit to App Review**
- [ ] Review typically takes 24–48 hours

---

## 11. Common Rejection Triggers — Pre-fix Checklist

- [ ] Paywall has visible **Restore Purchases** button → check `PaywallView.swift`
- [ ] Paywall has visible **Terms of Use** + **Privacy Policy** links → check `PaywallView.swift`
- [ ] Subscription price + duration + auto-renewal disclosure shown BEFORE purchase confirmation
- [ ] Sign in with Apple is offered if any other third-party sign-in is offered (Apple guideline 4.8)
- [ ] Account deletion path exists in-app (Settings → Delete Account) — guideline 5.1.1(v)
- [ ] No placeholder/Lorem text anywhere in the UI
- [ ] App icon has NO alpha channel and NO rounded corners (Apple rounds them)
- [ ] No "beta", "test", or "preview" wording in UI or description
- [ ] All external links work (privacy, terms, support)

---

## 12. Quick Verification Commands

```bash
# Verify app icon is 1024x1024 and opaque
sips -g pixelWidth -g pixelHeight -g hasAlpha "SacredBillTracker/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png"

# Validate the archive before upload (run after Product → Archive)
# Use Organizer → Validate App button

# Check what's in your built bundle
xcrun altool --validate-app -f /path/to/SacredBillTracker.ipa -t ios -u demarquishinton@gmail.com -p @keychain:AC_PASSWORD
```

---

## Status Snapshot (what's already done in your repo)

**App code (DONE)**
- Five user-facing tabs wired in `ContentView.swift`: Dashboard, Bills, Calendar, Reports, Settings. (Note: the codebase also contains `Views/Loads/*` from an earlier shared-code experiment with Sacred Pathway Driver Hub — those views are NOT mounted in `ContentView` and DO NOT appear in the app at runtime. Keep all marketing copy / screenshots focused only on the bills experience.)
- Sign in with Apple entitlement enabled in `SacredBillTracker.entitlements`.
- StoreKit 2 paywall (`PaywallView.swift`) with both a visible **Restore Purchases** button (line 261) and **Terms / Privacy** links (line 268, 270).
- A second **Restore Purchases** button is also exposed in `SettingsView.swift` (line 91) for non-paywall flows.
- Account-deletion path: `Settings → Delete Account` → `AuthService.deleteAccount()` → Supabase RPC `public.delete_user_account()` (Guideline 5.1.1(v) compliant).
- Sample data scrubbed — `SampleData.swift` only triggered from `Settings → Reset Sample` and is never auto-loaded.

**Backend (DONE in code, awaiting deployment)**
- Supabase URL + publishable key embedded in `Services/SupabaseConfig.swift`.
- `delete_user_account()` migration at `supabase/migrations/20260423120000_delete_user_account.sql`.
- App-review demo seed at `supabase/seeds/app_review_demo_seed.sql`.

**Assets (DONE — verified)**
- App icon: `Assets.xcassets/AppIcon.appiconset/app-icon-1024.png` is **1024×1024, RGB, no alpha** ✅.
- Logo: `Assets.xcassets/AppLogo.imageset/logo.png` present.
- Branding palette in `Color+Theme.swift` matches the README.
- `INFOPLIST_KEY_UISupportedInterfaceOrientations_*` set for iPhone (portrait + landscape) and iPad (all four).
- Marketing site at `site/index.html`; privacy policy HTML at `site/privacy/index.html` (well-formed, SacredBillTracker-specific, mentions Supabase + Sign in with Apple + in-app deletion).

**Project config (DONE)**
- `PRODUCT_BUNDLE_IDENTIFIER = com.sacredbilltracker.app`
- `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 4`
- `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
- `CODE_SIGN_STYLE = Automatic`, `DEVELOPMENT_TEAM = DCCSGYD5A4`

**Marketing screenshots (DONE — fallbacks)**
Six branded marketing screenshots per device size, all at exact Apple-required pixel dimensions, are staged at:
```
Desktop/SacredBillTracker/AppStoreScreenshots/
├── iPhone_6_9/01_Dashboard.png … 06_Paywall.png   (1320 × 2868)
├── iPhone_6_7/01_Dashboard.png … 06_Paywall.png   (1290 × 2796)
└── iPad_13/  01_Dashboard.png … 06_Paywall.png    (2064 × 2752)
```
These are programmatically rendered via `tools/generate_screenshots.py` using the Tree-of-Life palette and accurately reflect the actual SwiftUI layouts. They are App-Store acceptable as marketing screenshots, but you can replace any of them with a real simulator capture (Cmd+S in Simulator) before upload if you want pixel-perfect shots of the running app.

---

## Validation Pass — Rejection-Risk Audit (current state)

| Check | Status | Notes |
|---|---|---|
| Restore Purchases button visible in paywall | ✅ | `PaywallView.swift:261` |
| Restore Purchases button also in Settings | ✅ | `SettingsView.swift:91` |
| Terms link in paywall | ✅ | Apple stdEULA URL — `PaywallView.swift:268` |
| Privacy link in paywall | ✅ | `PaywallView.swift:270` → `https://www.sacredpathway.org/sacred-bill-tracker-privacy` (matches App Store Connect Privacy URL in §3) |
| Privacy link in Settings | ✅ | `SettingsView.swift:177` → same URL |
| Account-delete in-app | ✅ | `Settings → Delete Account` confirmation dialog → Supabase RPC |
| Sign in with Apple offered | ✅ | Entitlement enabled; `SignInView.swift` |
| App icon 1024×1024, no alpha | ✅ | Verified `mode=RGB size=(1024, 1024) has_alpha=False` |
| App icon no rounded corners | ✅ | RGB-only PNG; corners are square |
| No "beta" / "test" wording | ✅ | Grep for `beta\|Beta\|BETA\|preview only` returned no hits in any `.swift` file |
| No Lorem / placeholder copy | ✅ | One match in source for the word "placeholder" — a code comment in `AuthService.swift:18` describing a fallback, not user-visible |
| Sample data not auto-loaded | ✅ | Only via Settings → Reset; users start empty |
| Supported orientations | ✅ | iPhone: portrait + landscape · iPad: all four |
| `ITSAppUsesNonExemptEncryption` | ✅ | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` set in both Debug and Release in `project.pbxproj` (lines 497 + 533). TestFlight will no longer prompt for export compliance. |
| Entitlements file | ✅ | Sign in with Apple only (no push, no iCloud entitlement leak) |
| StoreKit ↔ ASC product ID match | ⏳ | Code uses `com.sacredbilltracker.app.pro.monthly` and `…pro.yearly`. These MUST be created identically in App Store Connect (§6) before the build can be submitted with subscriptions attached. |

---

## Encryption — export-compliance prompt (DONE)

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set in both Debug and Release configurations in `SacredBillTracker.xcodeproj/project.pbxproj`. Xcode will no longer ask "Does your app use encryption?" on TestFlight uploads, and App Store Connect will treat the build as exempt automatically.

If you ever need to verify in Xcode: Target → **Build Settings** → search "Encryption" → both configurations should show **NO**.

---

## What you still need to do (the only remaining blockers)

These all require credentials, GUI access, or App Store Connect — they cannot be done from inside the codebase.

1. **Confirm the privacy doc is live** at `https://www.sacredpathway.org/sacred-bill-tracker-privacy` over HTTPS. The page should match the contents of `site/privacy/index.html`. If it isn't already hosted there, upload that HTML to the Sacred Pathway site at the matching path.
2. **Supabase Dashboard** → Authentication → Users → create demo user `appreview@sacredbilltracker.com` / `ReviewPass2026!` (Auto Confirm User: ON), then run `supabase/seeds/app_review_demo_seed.sql` in the SQL Editor.
3. **App Store Connect** → Monetization → Subscriptions:
   - Create subscription group "Sacred Bill Tracker Pro"
   - Add subscription `com.sacredbilltracker.app.pro.monthly` ($4.99/mo, 7-day free intro offer)
   - Add subscription `com.sacredbilltracker.app.pro.yearly` ($39.99/yr, 7-day free intro offer)
   - Add English localizations + a review screenshot for each
4. **App Store Connect → App Information** — paste the Description / Promotional Text / Keywords from §3 of this doc.
5. **App Store Connect → Screenshots** — upload the marketing screenshots from `Desktop/SacredBillTracker/AppStoreScreenshots/{iPhone_6_9,iPhone_6_7,iPad_13}/`. (Or, if you want, capture real simulator shots first and replace the marketing fallbacks one-for-one.)
6. **Xcode → Archive → Distribute App → Upload to App Store Connect**. Wait ~15–30 min for processing.
7. **Attach the build + the two subscriptions** to version 1.0 in App Store Connect, then **Submit for Review**.

---
