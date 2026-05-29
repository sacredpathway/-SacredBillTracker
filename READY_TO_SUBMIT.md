# Sacred Bill Tracker — Ready-to-Submit Status

**Generated:** 2026-05-02
**Bundle ID:** `com.sacredbilltracker.app`
**Version:** 1.0.2 (build 6)
**Min iOS:** 17.0  •  **Devices:** iPhone + iPad
**Team:** DCCSGYD5A4  •  **Sign:** Automatic

---

## Verified clean (no action needed)

- [x] Swift sources: 7,754 LOC across Models / Services / Views — no TODO / FIXME / XXX markers
- [x] Imports resolve to: SwiftUI, Foundation, UIKit, StoreKit, AuthenticationServices, CryptoKit, UserNotifications, Supabase, Auth, Realtime
- [x] `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` set in pbxproj (no export compliance prompt)
- [x] `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad universal)
- [x] Product IDs match across all 3 sources:
  - `Services/StoreKit/ProductIdentifiers.swift`
  - `Configuration.storekit`
  - `FINAL_SUBMISSION/Subscriptions/ProductIDs.txt`
  - `com.sacredbilltracker.app.pro.monthly`  •  `com.sacredbilltracker.app.pro.yearly`
  - Subscription Group ID: `22047990`
- [x] App Store metadata within Apple character limits:
  - Subtitle 26/30  •  Keywords 100/100  •  Promo 155/170  •  Description 946/4000
- [x] Screenshots at exact Apple-required pixel sizes:
  - iPhone 6.9": **1320×2868** (6 PNGs)
  - iPad 13":  **2048×2732** (6 PNGs)
- [x] Privacy Policy + Terms of Service HTML drafted

---

## Manual steps you must do (cannot be automated from this folder)

### 1. Archive + Upload via Xcode
```
open "SacredBillTracker.xcodeproj"
# Destination: Any iOS Device (arm64)
# Product → Archive → Distribute App → App Store Connect → Upload
```

### 2. Host privacy policy
Upload `FINAL_SUBMISSION/Legal/PrivacyPolicy.html` to:
`https://www.sacredpathway.org/sacred-bill-tracker-privacy`
(URL is already declared in metadata — must return 200 OK before submission.)

### 3. App Store Connect — paste metadata
App Store tab → Version 1.0.2 → paste each file's contents:
- `AppStoreMetadata/Subtitle.txt` → Subtitle
- `AppStoreMetadata/PromotionalText.txt` → Promotional Text
- `AppStoreMetadata/Keywords.txt` → Keywords
- `AppStoreMetadata/Description.txt` → Description
- `AppStoreMetadata/PrivacyURL.txt` → Privacy Policy URL
- `AppStoreMetadata/AppReviewNotes.txt` → App Review Information → Notes

### 4. App Store Connect — create subscriptions
Monetization → Subscriptions → Group `Sacred Bill Tracker Pro` (id 22047990):
- `com.sacredbilltracker.app.pro.monthly` — $4.99/mo, 7-day free trial
- `com.sacredbilltracker.app.pro.yearly`  — $39.99/yr, 7-day free trial
- Attach `Screenshots/iPhone_6_9/06_Paywall.png` to each as the review screenshot.

### 5. App Store Connect — upload screenshots
Drag the 6 PNGs from each folder into matching display set:
- `Screenshots/iPhone_6_9/*.png` → 6.9" iPhone display
- `Screenshots/iPad_13/*.png`    → 13" iPad display
(Apple auto-derives 6.7" iPhone from the 6.9" set.)

### 6. Supabase — seed demo account
Follow `FINAL_SUBMISSION/DemoAccount/SeedInstructions.txt`. Reviewer credentials are in `DemoAccount/DemoLogin.txt`.

### 7. Contact info
App Store Connect → App Review Information → Contact Information → fill in your phone number directly (not stored in repo).

---

## Final pre-submit gate

Before clicking **Submit for Review**:
```
[ ] Privacy URL returns 200 OK over HTTPS
[ ] Demo account logs in and shows seeded bills
[ ] Build appears in TestFlight tab and finishes processing
[ ] Both subscriptions show "Ready to Submit" status
[ ] All 12 screenshots uploaded
[ ] Phone number filled in contact info
```

Hit Submit when all 6 checkboxes pass.
