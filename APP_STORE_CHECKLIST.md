# Sacred Bill Tracker — Final App Store Connect Upload Checklist

Bills-only. No trucking, Driver Hub, paystubs, or loads anywhere in this submission.

---

## 1. Subscriptions — exact values to enter

### Subscription Group

| Field | Value |
|---|---|
| Reference Name | `Sacred Bill Tracker Pro` |
| Group Display Name (English) | `Sacred Bill Tracker Pro` |

### Pro Monthly

| Field | Value |
|---|---|
| Reference Name | `Pro Monthly` |
| **Product ID** | `com.sacredbilltracker.app.pro.monthly` |
| Duration | 1 Month |
| Price (USD) | $4.99 |
| Free Trial | 7 days (Introductory Offer → Pay as you go OFF → "Free") |
| Family Sharing | Off |
| Cleared for Sale | Yes |

### Pro Yearly

| Field | Value |
|---|---|
| Reference Name | `Pro Yearly` |
| **Product ID** | `com.sacredbilltracker.app.pro.yearly` |
| Duration | 1 Year |
| Price (USD) | $39.99 |
| Free Trial | 7 days (Introductory Offer → Pay as you go OFF → "Free") |
| Family Sharing | Off |
| Cleared for Sale | Yes |

> **Both product IDs above MUST match `Services/StoreKit/ProductIdentifiers.swift` exactly. They already do — do not edit.**

---

## 2. Subscription Localizations (English) — Apple-compliant character counts

Apple limits: **Display Name ≤ 30 chars** • **Description ≤ 45 chars**

### Pro Monthly

| Field | Value | Chars |
|---|---|---|
| Display Name | `Pro Monthly` | 11 |
| Description | `Unlimited bills, business + reports.` | 36 |

### Pro Yearly

| Field | Value | Chars |
|---|---|---|
| Display Name | `Pro Yearly (Save 33%)` | 21 |
| Description | `All Pro features. Best value, save 33%.` | 39 |

> Each subscription also requires a **Review Screenshot** (1284×2778 or any iPhone screenshot). Upload `Desktop/SacredBillTracker/AppStoreScreenshots/iPhone_6_7/06_Paywall.png` for both.

---

## 3. App Information — copy/paste blocks

### App Name (30 chars max)

```
Sacred Bill Tracker
```
(19 chars)

### Subtitle (30 chars max)

```
Household + Business Bills
```
(26 chars)

### Primary Category

```
Finance
```

### Secondary Category

```
Productivity
```

### Bundle ID

```
com.sacredbilltracker.app
```

### SKU

```
SBT-IOS-001
```

### Content Rights

> "Yes, contains, uses, or accesses third-party content" → **No** (the app contains no third-party content).
> "You own or have licensed all the rights to the app's content" → **Yes**.

---

## 4. Promotional Text (170 chars max)

```
Track every household and business bill in one app. Get reminders before due dates, see this month's cash flow at a glance, and never miss a payment again.
```
(157 chars)

---

## 5. Description (4000 chars max)

```
Sacred Bill Tracker is the simplest way to manage household AND business bills in one place — built for entrepreneurs, freelancers, side-hustlers, and anyone juggling personal and company expenses.

WHY SACRED BILL TRACKER
• One app for both sides of your life — toggle between Household, Business, or All.
• See what's due today, this week, and this month at a glance.
• Never miss a payment — local reminders fire 0–14 days before each due date.
• Beautiful Tree-of-Life design — calm, focused, no clutter.

CORE FEATURES
• Add bills with name, amount, due date, category, recurrence, auto-pay flag, and notes
• Mark bills Paid, Unpaid, or Overdue (overdue is detected automatically)
• Dashboard: due today, due this week, overdue, upcoming, and monthly totals split by household vs. business
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

---

## 6. Keywords (100 chars max, comma-separated)

```
bill tracker,bills,budget,expenses,due date,reminder,household,business,finance,money,cash flow,debt
```
(99 chars)

---

## 7. URLs

| Field | URL |
|---|---|
| Support URL | `https://www.sacredpathway.org/sacred-bill-tracker-privacy` (or your support page if you have a separate one) |
| Marketing URL (optional) | leave blank, or your own marketing page |
| Privacy Policy URL | `https://www.sacredpathway.org/sacred-bill-tracker-privacy` |

---

## 8. App Privacy (App Privacy → Get Started)

| Question | Answer |
|---|---|
| Do you collect data from this app? | **Yes** |
| Identifiers → User ID | Linked to user · App Functionality |
| User Content → Other (bills) | Linked to user · App Functionality |
| Contact Info → Email | Linked to user · App Functionality (Sign in with Apple) |
| Tracking? | **No** |
| Third-party data sharing? | **No** |

---

## 9. Age Rating

Run the questionnaire — answer **None** to every category. Result: **4+**.

---

## 10. Copyright

```
© 2026 Sacred Bill Tracker
```

---

## 11. App Review Information

### Sign-In Required

**Yes** — Sign in with Apple. A demo email/password account is also provided so the reviewer doesn't have to use Sign in with Apple if they prefer not to.

### Demo Account Credentials

| Field | Value |
|---|---|
| Email | `appreview@sacredbilltracker.com` |
| Password | `ReviewPass2026!` |

### Notes for Reviewer (paste verbatim into App Review Notes)

```
Sacred Bill Tracker is a personal-finance utility for tracking household and business bills.

DEMO ACCOUNT
Sign in with Apple is supported. For review convenience, you can also tap "Continue with Email" and use:
  Email: appreview@sacredbilltracker.com
  Password: ReviewPass2026!
This account has 5 sample bills pre-loaded covering due-today, due-this-week, upcoming, overdue, and auto-pay scenarios.

SUBSCRIPTIONS
Pro features (unlimited bills, business tracking, reports, cloud sync) are gated behind an auto-renewable subscription.
- Pro Monthly: $4.99/mo, 7-day free trial
- Pro Yearly: $39.99/yr, 7-day free trial
The free tier supports up to 5 household bills. Business tracking and reports are Pro-only.
The paywall is reachable from Settings → Upgrade to Pro and from any locked feature.
The paywall has visible Restore Purchases, Terms, and Privacy links. Settings also has a top-level Restore Purchases row.

ACCOUNT DELETION (Guideline 5.1.1(v))
Settings → Delete Account permanently deletes the user's auth record and all of their bills via a Supabase RPC. No support contact required.

PRIVACY
Privacy policy: https://www.sacredpathway.org/sacred-bill-tracker-privacy
EULA: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/

DATA STORAGE
Bills are stored locally by default. Cloud sync via Supabase is opt-in for Pro subscribers.

EXPORT COMPLIANCE
ITSAppUsesNonExemptEncryption = NO (set in Info.plist via project.pbxproj). Uses Apple defaults only.
```

### Contact Info

| Field | Value |
|---|---|
| First Name | Demarquis |
| Last Name | (your last name) |
| Phone | (your phone) |
| Email | demarquishinton@gmail.com |

---

## 12. Demo Account Setup (do this BEFORE submitting)

1. **Supabase Dashboard** → Authentication → Users → **Add user** → **Create new user**
   - Email: `appreview@sacredbilltracker.com`
   - Password: `ReviewPass2026!`
   - Auto Confirm User: **ON**
2. **Supabase Dashboard** → SQL Editor → paste the entire contents of `supabase/seeds/app_review_demo_seed.sql` → **Run**.
3. Verify the bottom of the SQL output lists 5 bills (Rent, Electric Bill, Internet, Adobe Creative Cloud, Quarterly Taxes).
4. (Optional sanity check) Open the app on simulator → Continue with Email → enter the credentials → Dashboard should show 5 bills with mixed statuses.

---

## 13. Screenshot Upload Order

Upload the marketing PNGs from `Desktop/SacredBillTracker/AppStoreScreenshots/` in this exact sequence per device size. Same order across all three devices keeps the App Store listing consistent.

| Slot | Filename | Headline shown |
|---|---|---|
| 1 | `01_Dashboard.png` | Every Bill, Household and business in one place |
| 2 | `02_Bills.png` | Track What's Due, Filter by household or business |
| 3 | `03_Calendar.png` | See the Whole Month, Per-day markers |
| 4 | `04_Reports.png` | Cash Flow at a Glance, Monthly totals + categories |
| 5 | `05_Settings.png` | You're in Control, Reminders, sync, account |
| 6 | `06_Paywall.png` | 7 Days Free, Then Pro |

Upload to these App Store Connect device slots:

| App Store Connect device size | Folder | Pixel size | Required? |
|---|---|---|---|
| iPhone 6.9" Display | `iPhone_6_9/` | 1320 × 2868 | **Required** |
| iPhone 6.7" Display | `iPhone_6_7/` | 1290 × 2796 | **Required** |
| iPad 13" Display | `iPad_13/`    | 2064 × 2752 | **Required** (iPad enabled) |

All 18 PNGs are RGB, no alpha, exact pixel dimensions — verified.

---

## 14. Build Configuration — what's already set

| Setting | Value | Where |
|---|---|---|
| Bundle Identifier | `com.sacredbilltracker.app` | `project.pbxproj` |
| Marketing Version | `1.0` | `project.pbxproj` |
| Build Number | `4` | `project.pbxproj` |
| iOS Deployment Target | `17.0` | `project.pbxproj` |
| Code Sign Style | Automatic | `project.pbxproj` |
| Development Team | `DCCSGYD5A4` | `project.pbxproj` |
| ITSAppUsesNonExemptEncryption | `NO` | `project.pbxproj` (Debug + Release) |
| Sign in with Apple entitlement | Enabled | `SacredBillTracker.entitlements` |
| Supported orientations | Portrait + Landscape (iPhone), all 4 (iPad) | `project.pbxproj` |
| App icon | 1024×1024 RGB no alpha | `Assets.xcassets/AppIcon.appiconset/app-icon-1024.png` |

> Bump `CURRENT_PROJECT_VERSION` (build number) before re-archiving if you upload more than once. App Store Connect rejects duplicate build numbers.

---

## 15. Final Archive & Upload Steps (Xcode)

1. **Update once:** Open `SacredBillTracker.xcodeproj` → Target `SacredBillTracker` → **Signing & Capabilities** → confirm Team is `DCCSGYD5A4` (or your team) and "Automatically manage signing" is checked.
2. **Destination:** Top toolbar → set device to **Any iOS Device (arm64)**.
3. **(Optional) Bump build:** Target → General → Build → increment from 4 if this isn't your first upload.
4. **Archive:** menu **Product → Archive**. Wait until the Organizer window opens.
5. In Organizer: select the new archive → **Validate App** first.
   - "App Store Connect" distribution
   - "Automatically manage signing"
   - Wait for the green check. If validation fails, fix and re-archive — do not skip.
6. After validation passes: same archive → **Distribute App**.
   - Destination: **App Store Connect**
   - Method: **Upload**
   - Signing: Automatic
   - Click **Upload**.
7. Wait 15–30 minutes. App Store Connect → TestFlight tab → the build moves from "Processing" to "Ready to Submit". You'll also get an email when it's ready.
8. App Store Connect → your app → **App Store** tab → **iOS App 1.0**:
   - **Build** section → **+** → select the new build.
   - **In-App Purchases** section → **+** → select **Pro Monthly** and **Pro Yearly** (both must be in "Ready to Submit" status from §1).
9. **Verify everything:**
   - All three screenshot device sizes filled (6 each).
   - App Privacy answered (§8).
   - Age rating set (§9).
   - App Review Notes pasted (§11).
   - Demo account works (§12).
10. Top right → **Add for Review** → **Submit to App Review**.
11. Review typically takes 24–48 hours. Watch email for the result. If rejected, the rejection reason will list the specific guideline; fix, bump build number, archive, upload, resubmit.

---

## 16. Pre-Submit Final Checks (one-pass)

- [ ] Privacy URL `https://www.sacredpathway.org/sacred-bill-tracker-privacy` resolves over HTTPS and shows the Sacred Bill Tracker privacy doc
- [ ] Demo Supabase user exists and seed has run (5 sample bills visible)
- [ ] Subscription group + both subscriptions in "Ready to Submit"
- [ ] All 18 screenshots uploaded
- [ ] App Privacy questionnaire complete
- [ ] App Review Notes pasted
- [ ] Build attached + both subscriptions attached
- [ ] No "beta", "test", "preview" wording anywhere in metadata
- [ ] No mention of trucking, loads, paystubs, or Driver Hub anywhere

When all sixteen are checked: **Submit to App Review.**
