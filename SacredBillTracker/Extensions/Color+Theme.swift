//
//  Color+Theme.swift
//  SacredBillTracker
//
//  Palette derived from the Tree-of-Life brand mark:
//   - Black background
//   - Gold / amber trunk and roots
//   - Deep leaf green canopy
//   - Bright lime-chartreuse ring accent
//

import SwiftUI

extension Color {

    // MARK: - Core brand

    /// Primary brand accent — premium gold (upgraded from the old muddy
    /// #C89B4B brown-gold to a cleaner, richer metallic gold).
    static let appAccent = Color(red: 0.831, green: 0.686, blue: 0.216)   // #D4AF37 premium gold

    /// Emphasis gold — fully gold now (was a brownish amber). Matches the
    /// premium accent so no warm accent reads as brown.
    static let appAmber  = Color(red: 0.831, green: 0.686, blue: 0.216)   // #D4AF37 gold

    /// Bright lime / chartreuse ring — reserved for highlights & success.
    static let appLime   = Color(red: 0.69, green: 0.82, blue: 0.31)      // #AFD250

    // MARK: - Category tints

    /// Household tint — leaf green (canopy).
    static let appHousehold = Color(red: 0.36, green: 0.60, blue: 0.26)   // #5B9943

    /// Business tint — clean gold (no brown). Slightly deeper than the
    /// main accent so Business still reads distinct from the gold CTAs.
    static let appBusiness  = Color(red: 0.804, green: 0.643, blue: 0.196) // #CDA432 gold

    // MARK: - Surfaces

    /// Layered card background that adapts to light / dark.
    static let appCard = Color(.secondarySystemBackground)

    /// "Sacred" black for full-bleed headers or dark backdrops.
    static let appSacredBlack = Color(red: 0.05, green: 0.05, blue: 0.06) // #0D0D0F

    // MARK: - Surfaces (premium polish, neutral system canvas)
    //
    // The app keeps its original neutral layout — system grouped
    // backgrounds that adapt to Light / Dark automatically. We only
    // polish on top: gold accents, a subtle gold card hairline, cleaner
    // shadows, and a stronger true-red for alerts.

    /// Primary app background — system grouped (white-ish light / near-black dark).
    static let appBackground = Color(.systemGroupedBackground)

    /// Elevated card surface that sits on top of `appBackground`.
    static let appCardSurface = Color(.secondarySystemGroupedBackground)

    /// Subtle gold hairline for card edges & dividers — refined, not loud.
    static let appHairline = Color.appAccent.opacity(0.18)

    /// Near-black label to place ON a solid gold fill (e.g. primary
    /// buttons) so gold CTAs have strong contrast in both modes.
    static let appOnGold = Color(red: 0.110, green: 0.110, blue: 0.118)      // #1C1C1E

    // MARK: - Strong true red (alerts / destructive / overdue)
    //
    // Replaces the soft default red with a bolder, more saturated true
    // red. Adaptive so it stays vivid on both light and dark canvases.

    /// Solid red for destructive buttons / status fills (white text on top).
    static let appDanger = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 1.0,   green: 0.271, blue: 0.227, alpha: 1)  // #FF453A vivid
        default:
            return UIColor(red: 0.843, green: 0.0,   blue: 0.082, alpha: 1)  // #D70015 strong true red
        }
    })

    /// Red safe as TEXT/label — slightly lighter in dark for legibility.
    static let appDangerText = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 1.0,   green: 0.412, blue: 0.380, alpha: 1)  // #FF6961
        default:
            return UIColor(red: 0.843, green: 0.0,   blue: 0.082, alpha: 1)  // #D70015
        }
    })

    // MARK: - Adaptive text variants (v1.0.9 readability)
    //
    // The decorative `appAccent` / `appHousehold` / `appBusiness` /
    // `appLime` colors are calibrated for icons + tints, not body
    // copy. When used as TEXT on a light background they fall short
    // of WCAG AA contrast. Use these `*Text` variants whenever a
    // brand color drives a number, label, headline, or row text — they
    // automatically darken on light backgrounds and lighten on dark.

    /// Gold accent, safe as text. Darker in light mode, slightly
    /// brighter in dark mode.
    static let appAccentText = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.902, green: 0.761, blue: 0.361, alpha: 1) // #E6C25C brighter premium gold
        default:
            return UIColor(red: 0.541, green: 0.416, blue: 0.071, alpha: 1) // #8A6A12 — readable on white
        }
    })

    /// Household / personal green, safe as text.
    static let appHouseholdText = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.55, green: 0.82, blue: 0.42, alpha: 1) // brighter green
        default:
            return UIColor(red: 0.20, green: 0.42, blue: 0.13, alpha: 1) // #336B21 — readable on white
        }
    })

    /// Business amber/gold, safe as text.
    static let appBusinessText = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.902, green: 0.761, blue: 0.361, alpha: 1) // #E6C25C bright gold
        default:
            return UIColor(red: 0.561, green: 0.431, blue: 0.063, alpha: 1) // #8F6E10 deep gold (was brown #754712)
        }
    })

    /// Lime — never use the raw `appLime` for text on white; it has
    /// 1.7:1 contrast. This variant collapses to a deep moss in light
    /// and stays bright in dark.
    static let appLimeText = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.78, green: 0.90, blue: 0.42, alpha: 1)
        default:
            return UIColor(red: 0.30, green: 0.46, blue: 0.10, alpha: 1) // moss
        }
    })

    /// Body-text-secondary replacement that's slightly darker than
    /// `.secondary` for the rare cases where subtitles need a little
    /// more weight to be legible. Adapts automatically.
    static let appSubtleText = Color(uiColor: UIColor { trait in
        switch trait.userInterfaceStyle {
        case .dark:
            return UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        default:
            return UIColor(red: 0.32, green: 0.32, blue: 0.34, alpha: 1)
        }
    })
}
