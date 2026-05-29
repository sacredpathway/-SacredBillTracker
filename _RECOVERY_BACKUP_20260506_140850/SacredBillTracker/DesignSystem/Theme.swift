//
//  Theme.swift
//  SacredBillTracker
//
//  Centralized design tokens used by the Partner Budgeting & Account
//  surfaces. Aligned with the existing Color+Theme.swift palette so the
//  Sacred brand (gold accent) is preserved.
//

import SwiftUI

enum Theme {

    enum Color {
        static let background      = SwiftUI.Color(.systemGroupedBackground)
        static let card            = SwiftUI.Color(.secondarySystemGroupedBackground)
        static let primaryText     = SwiftUI.Color.primary
        static let secondaryText   = SwiftUI.Color.secondary

        /// Maps to the existing leaf-green canopy tint so partner surfaces
        /// feel native to the Sacred palette.
        static let accentGreen     = SwiftUI.Color.appHousehold

        /// Maps to the existing sacred gold so primary CTAs match brand.
        static let accentGold      = SwiftUI.Color.appAccent

        static let danger          = SwiftUI.Color.red
        static let success         = SwiftUI.Color.appHousehold
        static let cardShadow      = SwiftUI.Color.black.opacity(0.06)
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
                    .foregroundStyle(Theme.Color.accentGreen)
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
    var color: Color = Theme.Color.accentGreen
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundColor(.white)
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
            .foregroundColor(Theme.Color.accentGreen)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(Theme.Color.accentGreen.opacity(0.10))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
