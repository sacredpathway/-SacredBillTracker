# Sacred Bill Tracker (iOS)

A SwiftUI app for tracking both **household** and **business** bills in one place.
Visual identity: Tree of Life — gold trunk/roots, green canopy, sacred black.

## App overview

| Field              | Value                              |
|--------------------|------------------------------------|
| Display name       | Sacred Bill Tracker                |
| Target name        | SacredBillTracker                  |
| Bundle identifier  | `com.sacredbilltracker.app`        |
| Deployment target  | iOS **17.0**                       |
| Swift version      | 5.0                                |
| Device family      | iPhone + iPad (1,2)                |
| Orientations       | Portrait + Landscape Left/Right    |

## Requirements

- **Xcode 15+** (uses `@Previewable`, the 2-parameter `onChange(of:_:)`, and `#Preview` macro).
- **macOS** with iOS 17 Simulator or a physical iOS 17 device.

## Branding — Tree of Life palette

| Role          | Hex       | Where it shows up                                |
|---------------|-----------|--------------------------------------------------|
| Primary gold  | `#C89B4B` | App accent, tab bar tint, "Upcoming" stat, CTA   |
| Secondary amber| `#B8782F`| Business category, "Due Today" stat              |
| Leaf green    | `#5B9943` | Household category                               |
| Highlight lime| `#AFD250` | Logo ring accent, "This Week" stat               |
| Sacred black  | `#0D0D0F` | Brand header backdrop, dark surfaces             |

All colors live in `SacredBillTracker/Extensions/Color+Theme.swift`.

## Features

- Tabs: **Dashboard**, **Bills**, **Calendar**, **Reports**, **Settings**.
- Add / edit / delete bills with name, amount, due date, category, recurrence, household-or-business, auto-pay, notes.
- Mark bills **Paid**, **Unpaid**, or **Overdue** (overdue is derived automatically once the due date passes).
- Dashboard stats: bills due today, bills due this week, overdue, upcoming, household total this month, business total this month.
- Filters across every screen: **Household**, **Business**, **All**.
- Monthly calendar view with per-day bill markers.
- Reports with monthly totals and category breakdown (horizontal bars).
- Local notifications for upcoming due dates, configurable lead time (0–14 days) in Settings.
- Local persistence via `UserDefaults` (JSON-encoded) through a `BillRepository` protocol.
- Supabase-ready: drop-in `SupabaseBillRepository` stub with schema comments.

## Project structure

```
SacredBillTracker.xcodeproj/          # Xcode project (hand-generated, shared scheme included)
SacredBillTracker/
├── SacredBillTrackerApp.swift
├── ContentView.swift
├── Assets.xcassets/
│   ├── AppLogo.imageset/
│   ├── AppIcon.appiconset/
│   └── AccentColor.colorset/
├── Models/
│   ├── Bill.swift
│   ├── BillType.swift          # household / business
│   ├── BillCategory.swift
│   ├── PaymentStatus.swift
│   └── RecurrenceType.swift
├── Services/
│   ├── BillRepository.swift    # protocol
│   ├── LocalBillRepository.swift
│   ├── SupabaseBillRepository.swift
│   ├── BillStore.swift         # @MainActor ObservableObject
│   ├── NotificationManager.swift
│   └── SampleData.swift
├── Views/
│   ├── Dashboard/DashboardView.swift
│   ├── Bills/
│   │   ├── BillsView.swift
│   │   ├── BillRowView.swift
│   │   ├── AddEditBillView.swift
│   │   └── BillDetailView.swift
│   ├── Calendar/CalendarView.swift
│   ├── Reports/ReportsView.swift
│   ├── Settings/SettingsView.swift
│   └── Components/
│       ├── StatCard.swift
│       ├── FilterPicker.swift
│       ├── EmptyStateView.swift
│       └── BrandHeaderView.swift
└── Extensions/
    ├── Color+Theme.swift
    └── Date+Helpers.swift
```

## One-time setup

1. **Open the project** — double-click `SacredBillTracker.xcodeproj` in Finder. The shared scheme (`SacredBillTracker`) loads automatically.
2. **Add the logo image.** Save your Tree-of-Life artwork as:
   - `SacredBillTracker/Assets.xcassets/AppLogo.imageset/logo.png` (1024×1024 PNG; transparent or black background)
3. **Add the app icon.** Save an opaque 1024×1024 PNG as:
   - `SacredBillTracker/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png`
4. **Delete the `PLACE_*.txt` placeholder files** inside those imagesets.
5. **Signing.** Select the `SacredBillTracker` target → *Signing & Capabilities* → choose your development team. The `CODE_SIGN_STYLE` is set to Automatic.
6. **Build & run.** Pick an iOS 17 simulator (or device), press ⌘R.

## Notifications

The app requests local-notification permission on first launch. You can change the reminder lead time in **Settings → Notifications → Remind**. No server push is used, so no entitlement is required unless you add remote push later.

## Supabase integration (future)

`Services/SupabaseBillRepository.swift` is a stub that currently forwards to the local repository. The file includes:
- A suggested `bills` table schema (Postgres).
- TODO markers for each CRUD call.
- Wiring instructions: add the [supabase-swift](https://github.com/supabase/supabase-swift) SPM package, then swap the repo in `SacredBillTrackerApp.swift`:
  ```swift
  let repo: BillRepository = SupabaseBillRepository(client: myClient)
  ```
Because `BillStore` consumes a `BillRepository`, no UI code changes.

## Paywall (StoreKit 2)

The app ships with a native StoreKit 2 paywall — no third-party SDKs.

### Files

| File | Role |
|------|------|
| `Services/StoreKit/ProductIdentifiers.swift` | Product IDs + subscription group ID |
| `Services/StoreKit/Entitlements.swift` | `SubscriptionTier`, `FreeTierLimits`, `ProFeature` list |
| `Services/StoreKit/SubscriptionManager.swift` | StoreKit 2 wrapper. Exposed as `@EnvironmentObject` |
| `Views/Paywall/PaywallView.swift` | Full-screen upgrade sheet with yearly/monthly picker |
| `Views/Paywall/ProLockCard.swift` | Reusable "this feature is Pro" card + `ProBadge` pill |
| `Configuration.storekit` | Local StoreKit test configuration (used by the scheme) |

### Product IDs

| Tier    | Product ID                                      | Suggested price |
|---------|-------------------------------------------------|-----------------|
| Monthly | `com.sacredbilltracker.app.pro.monthly`         | $4.99 / month   |
| Yearly  | `com.sacredbilltracker.app.pro.yearly`          | $39.99 / year   |

Both include a **7-day free trial** as an introductory offer.

### Free-tier gates (`FreeTierLimits`)

- **5 bill cap** — tapping `+` beyond 5 bills opens the paywall.
- **Household only** — the Type picker in Add Bill shows a PRO badge for Business.
- **Reports tab locked** — shows a `ProLockCard` until upgraded.
- **Cloud sync disabled** — free stays local (toggle `allowCloudSync` when you're ready).

### Testing locally (no App Store Connect needed)

1. Open the scheme (`Product → Scheme → Edit Scheme…`).
2. In the **Run** action → **Options** tab, set **StoreKit Configuration** to `Configuration.storekit`.
3. Run the app. Tap **Settings → Upgrade to Pro**. The paywall will show real-looking prices from the `.storekit` file.
4. Tap **Start 7 days free**. StoreKit will simulate a purchase locally (no Apple ID charged).
5. Use **Debug → StoreKit → Manage Transactions…** in the simulator to revoke / refund for re-testing.

### Shipping for real (App Store Connect)

1. On **appstoreconnect.apple.com → your app → Monetization → Subscriptions**:
   - Create a subscription group called **"Sacred Bill Tracker Pro"**.
   - Inside it, add two subscriptions with the product IDs above. Set prices + 7-day Introductory Offer (Free).
   - Paste the same **subscription group ID** back into `ProductIdentifiers.swift` (replaces the placeholder).
2. Fill the **App Privacy** and **Paid Apps Agreement** sections if you haven't already.
3. Add a **Privacy Policy URL** and **Terms URL** — StoreKit requires both for subscriptions. Update the links at the bottom of `PaywallView.swift` to match.
4. Archive → Upload → the subscriptions will flip to "Ready to Submit" once the build processes.
5. Submit the subscriptions alongside your first App Store release (or after, if you're using TestFlight only).

### Testing on TestFlight

TestFlight uses the **sandbox** environment automatically. Testers will see a "Sandbox" label in the Apple purchase sheet and won't be charged — transactions are simulated end-to-end, including renewals (1 month = 5 min in sandbox).

## Known limitations & manual steps

- **Logo image file is not bundled.** The code references `UIImage(named: "AppLogo")` and the `AppLogo` imageset exists, but you must drop the actual PNG in. Until you do, the Dashboard header shows a graceful fallback (gold tree SF Symbol on sacred-black disc with lime ring).
- **App icon is not bundled.** Until you add `app-icon-1024.png` to `AppIcon.appiconset`, Xcode will show a build warning about a missing icon. The app still builds and runs.
- **`.xcodeproj` was generated by hand** (deterministic UUIDs). It is a standard Xcode project that opens and builds in Xcode 15+, but if you want to regenerate it from scratch, the generator script used is `generator.py` logic built around file walks + MD5-derived UUIDs.
- **No unit tests are bundled** — the scope was MVP app code only.
