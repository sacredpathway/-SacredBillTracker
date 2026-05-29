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

    /// Primary brand accent — sacred gold (tree trunk).
    static let appAccent = Color(red: 0.78, green: 0.61, blue: 0.29)      // #C89B4B

    /// A deeper, warmer amber — used sparingly for emphasis.
    static let appAmber  = Color(red: 0.72, green: 0.47, blue: 0.18)      // #B8782F

    /// Bright lime / chartreuse ring — reserved for highlights & success.
    static let appLime   = Color(red: 0.69, green: 0.82, blue: 0.31)      // #AFD250

    // MARK: - Category tints

    /// Household tint — leaf green (canopy).
    static let appHousehold = Color(red: 0.36, green: 0.60, blue: 0.26)   // #5B9943

    /// Business tint — amber / gold (roots).
    static let appBusiness  = Color(red: 0.72, green: 0.47, blue: 0.18)   // #B8782F

    // MARK: - Surfaces

    /// Layered card background that adapts to light / dark.
    static let appCard = Color(.secondarySystemBackground)

    /// "Sacred" black for full-bleed headers or dark backdrops.
    static let appSacredBlack = Color(red: 0.05, green: 0.05, blue: 0.06) // #0D0D0F
}
