//
//  Theme.swift
//  SacredBillTracker
//
//  Centralized design tokens used by the Partner Budgeting & Account
//  surfaces. Aligned with the existing Color+Theme.swift palette so the
//  Sacred brand (gold accent) is preserved.
//

import SwiftUI
import UIKit

enum Theme {

    enum Color {
        /// App background — system grouped surface (adapts Light/Dark).
        static let background      = SwiftUI.Color.appBackground
        /// Elevated card surface on top of the background.
        static let card            = SwiftUI.Color.appCardSurface
        static let primaryText     = SwiftUI.Color.primary
        static let secondaryText   = SwiftUI.Color.secondary

        /// Leaf-green canopy tint — retained for category tints / success.
        static let accentGreen     = SwiftUI.Color.appHousehold

        /// Sacred gold — used for solid fills, borders, and large
        /// graphical accents (button backgrounds, hairlines).
        static let accentGold      = SwiftUI.Color.appAccent

        /// Adaptive gold safe for TEXT and small icons — darkens on
        /// light backgrounds, brightens on dark — so gold labels clear
        /// WCAG AA in both appearances.
        static let accentGoldText  = SwiftUI.Color.appAccentText

        /// Gold-tinted hairline used for card borders & dividers.
        static let hairline        = SwiftUI.Color.appHairline

        /// Readable label color on a solid gold fill.
        static let onGold          = SwiftUI.Color.appOnGold

        /// Stronger true red for alerts / destructive / overdue.
        static let danger          = SwiftUI.Color.appDanger
        /// Red safe as text/label.
        static let dangerText      = SwiftUI.Color.appDangerText
        static let success         = SwiftUI.Color.appHousehold
        static let cardShadow      = SwiftUI.Color.black.opacity(0.08)
    }

    enum Radius {
        static let card: CGFloat   = 16
        static let pill: CGFloat   = 999
        static let button: CGFloat = 12
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s:  CGFloat = 8
        static let m:  CGFloat = 12
        static let l:  CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Font {
        static let sectionTitle = SwiftUI.Font.system(.subheadline, design: .rounded).weight(.semibold)
        static let cardTitle    = SwiftUI.Font.system(.headline,    design: .rounded).weight(.semibold)
        static let largeTitle   = SwiftUI.Font.system(.largeTitle,  design: .rounded).weight(.bold)
        static let body         = SwiftUI.Font.system(.body,        design: .rounded)
        static let caption      = SwiftUI.Font.system(.caption,     design: .rounded)
    }
}

// MARK: - Global UIKit appearance (nav bar, tab bar, list backgrounds)

enum ThemeAppearance {

    /// Adaptive premium gold for bar tint — matches `appAccentText` so
    /// bar buttons stay readable on the light canvas and bright on dark.
    private static var goldUIColor: UIColor {
        UIColor { trait in
            switch trait.userInterfaceStyle {
            case .dark:
                return UIColor(red: 0.902, green: 0.761, blue: 0.361, alpha: 1) // #E6C25C
            default:
                return UIColor(red: 0.541, green: 0.416, blue: 0.071, alpha: 1) // #8A6A12
            }
        }
    }

    /// Call once at app launch. Keeps the system's default nav/tab/list
    /// backgrounds (original neutral layout untouched) and only applies
    /// the premium gold tint to bar buttons and the selected tab.
    static func apply() {
        UINavigationBar.appearance().tintColor = goldUIColor // gold back/bar buttons
        UITabBar.appearance().tintColor        = goldUIColor // selected tab = gold
    }
}

// MARK: - Card Modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = Theme.Spacing.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.Color.card)
            )
            .overlay(
                // Gold hairline border so card edges read as gold accents.
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Color.hairline, lineWidth: 1)
            )
            .shadow(color: Theme.Color.cardShadow, radius: 10, x: 0, y: 4)
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Spacing.l) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Color.accentGoldText)
            }
            Text(title.uppercased())
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.Color.secondaryText)
                .tracking(0.6)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.xs)
    }
}

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    /// Primary CTAs are premium gold. Label is near-black for strong
    /// contrast on the gold fill (gold is light, so dark text reads best).
    var color: Color = Theme.Color.accentGold
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundColor(Theme.Color.onGold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.85 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundColor(Theme.Color.accentGoldText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Color.accentGold.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.Color.accentGold.opacity(0.5), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
