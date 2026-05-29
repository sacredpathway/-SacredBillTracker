# SacredBillTracker — Premium Polish (Change Report)

**Goal:** same app, same layout — just more premium. Upgrade the brown/muddy accent to a clean premium gold, make red alerts a stronger true red, refine cards (subtle gold hairline + softer shadow), keep contrast strong in Light & Dark. No structure, navigation, logic, saving, StoreKit, or data changes.

**Note:** the earlier dark-green canvas experiment has been fully reverted — backgrounds are back to the original system surfaces. (The old `THEME_DARKGREEN_GOLD_*` files are superseded by this one.)

---

## Color upgrades (centralized in `Extensions/Color+Theme.swift`)

| Token | Before | After | Why |
|------|--------|-------|-----|
| `appAccent` (gold) | `#C89B4B` muddy brown-gold | **`#D4AF37`** premium gold | core accent / buttons / icons |
| `appAccentText` (gold text) | `#835C19` / `#EBBC66` | `#8A6A12` / `#E6C25C` | readable gold for text & small icons |
| `appAmber` (emphasis) | `#B8782F` brown | `#C28A22` | refined warm gold |
| `appBusiness` (category) | `#B8782F` brown | `#C49A3A` | cleaner antique gold |
| `appBackground` | (system) | system grouped — **unchanged layout** | neutral canvas restored |
| `appCardSurface` | (system) | secondary system grouped | neutral cards restored |
| `appHairline` | — | gold @ 18% | subtle premium card edge |
| `appOnGold` | — | `#1C1C1E` | near-black label on gold buttons |
| `appDanger` (NEW) | system `.red` | **`#D70015` light / `#FF453A` dark** | stronger true red for fills/status |
| `appDangerText` (NEW) | — | `#D70015` light / `#FF6961` dark | stronger red for error text |

## WCAG contrast (computed)

| Pair | Ratio | Result |
|------|-------|--------|
| onGold label on gold button | 8.1:1 | AA ✓ |
| gold text (light) on white | 5.1:1 | AA ✓ |
| gold text (dark) on dark grey | 9.9:1 | AA ✓ |
| white on danger-red button (light) | 5.4:1 | AA ✓ |
| white on danger-red button (dark) | 3.4:1 | AA-large ✓ (bold button text) |
| danger text (light) on white | 5.4:1 | AA ✓ |
| danger text (dark) on dark grey | 6.0:1 | AA ✓ |

Body text stays on the system `.primary`/`.secondary` semantics, so it remains fully readable in both Light and Dark. The Light/Dark/System picker is untouched.

---

## Files changed (11)

Centralized tokens & styles:
1. `Extensions/Color+Theme.swift` — premium gold family; reverted surfaces to system; added `appHairline`, `appOnGold`, `appDanger`, `appDangerText`.
2. `DesignSystem/Theme.swift` — `danger` → strong red; added `dangerText`; card shadow softened (0.08); gold hairline on `CardStyle`; gold section-header icons; gold buttons (gold fill + near-black label, gold outline secondary); `ThemeAppearance.apply()` now only applies the gold bar tint (default system bar/list backgrounds — original chrome preserved).
3. `SacredBillTrackerApp.swift` — calls `ThemeAppearance.apply()`; root `.tint` = adaptive gold.

Stronger true red routed into status/error spots:
4. `Models/PaymentStatus.swift` — overdue status color → `appDanger` *(color-only display property; no data/logic touched)*.
5. `Views/Bills/BillRowView.swift` — overdue due-tint + overdue insight tag → `appDangerText`.
6. `Views/Components/PrioritySection.swift` — rank-1 + overdue tints → `appDangerText`.
7. `Views/Reports/CategoryDetailView.swift` — Overdue tile + status badge → `appDanger`.
8. `Views/Auth/ForgotPasswordView.swift` — error text → `appDangerText`.
9. `Views/Partner/PartnerBudgetingView.swift` — error label → `appDangerText`.

(Plus the page-background references on Dashboard, Bills, Calendar, Reports, Income, Paywall, Daily Focus, and Needs-Attention now route through `Theme.Color.background`, which maps to the original system surface — same look, but centralized.)

## Screen coverage (premium accents applied)
Dashboard · Bills · Add/Edit Bill · Calendar · Reports · Income · Paywall · Settings · Sacred Focus — all pick up the gold accent (buttons, section icons, tints, card hairline) and the stronger overdue/error red. Layout, tabs, cards, and navigation are unchanged.

## Safety
- No logic, saving, subscriptions, StoreKit, navigation, or data-model *data* touched. The one model-file edit (`PaymentStatus.color`) changes only a SwiftUI `Color` display value.
- Light/Dark/System appearance picker preserved.
- Colors centralized — future tweaks live in `Color+Theme.swift` / `Theme.swift`.

---

## ⚠️ Build + screenshots need Xcode (can't run iOS here)
This is a Linux environment with no Xcode/Swift-iOS toolchain, so I could not compile, run the simulator, or capture real screenshots. Verify on a build:

```bash
cd "/Users/demarquishinton/Documents/Claude/Projects/SACRED BILL TRACKER"
xcodebuild -project SacredBillTracker.xcodeproj -scheme SacredBillTracker \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
Then run, toggle Light/Dark, and check: Dashboard, Bills, Add/Edit Bill, Calendar, Reports, Income, Paywall, Settings, Sacred Focus. Confirm gold accents read premium, overdue/error reds are bold, and card hairlines look clean (not heavy). The included `PREMIUM_POLISH_PREVIEW.html` shows the intended look.
