//
//  IncomeType.swift
//  SacredBillTracker
//
//  v1.0.9 — Income entries are now typed as Business or Personal so
//  the dashboard can show a true Business-vs-Personal split (alongside
//  the existing weekly / 30-day totals). Existing entries that
//  pre-date this field decode as `.business` since the app's primary
//  audience is owner-operators tracking trucking income.
//

import Foundation
import SwiftUI

enum IncomeType: String, Codable, CaseIterable, Identifiable, Hashable {
    case business
    case personal

    var id: String { rawValue }

    /// Picker / card label.
    var title: String {
        switch self {
        case .business: return "Business"
        case .personal: return "Personal"
        }
    }

    /// Sentence-cased label used in dashboard subtitles.
    var cardTitle: String {
        switch self {
        case .business: return "Business Income"
        case .personal: return "Personal Income"
        }
    }

    /// Card subtitle.
    var subtitle: String {
        switch self {
        case .business: return "Income earned from business activities"
        case .personal: return "Income earned from personal sources"
        }
    }

    /// Glyph used on the dashboard card + Add-Income picker.
    var systemImage: String {
        switch self {
        case .business: return "briefcase.fill"
        case .personal: return "house.fill"
        }
    }

    /// Accent color safe for text + icons. v1.0.9 routes through the
    /// adaptive `*Text` variants so numbers and labels stay legible on
    /// light backgrounds. (The decorative `appBusiness` / `appHousehold`
    /// raw values are still available; use those for backgrounds /
    /// tints where high contrast on white isn't required.)
    var accent: Color {
        switch self {
        case .business: return .appBusinessText
        case .personal: return .appHouseholdText
        }
    }

    /// Fallback used when decoding entries that pre-date the field and
    /// carry no detectable business signal.
    static let legacyDefault: IncomeType = .personal

    /// Heuristic-based classifier for legacy entries that have no
    /// `type` field saved. Looks at the source/note text for trucking
    /// & business indicators. If any match → `.business`. Otherwise
    /// fall back to `.personal` so the user is free to edit it later
    /// without us silently mis-tagging real personal income as
    /// business.
    ///
    /// Keywords were chosen from the actual notes pattern in the
    /// trucking version of this app: broker, load, freight, haul,
    /// settlement, factoring, dispatch, detention, layover, lumper,
    /// 1099, fuel, miles, rate con, paystub, owner-operator.
    static func inferLegacyType(from text: String) -> IncomeType {
        let haystack = text.lowercased()
        guard !haystack.isEmpty else { return .personal }
        for kw in businessKeywords where haystack.contains(kw) {
            return .business
        }
        return .personal
    }

    private static let businessKeywords: [String] = [
        "broker", "brokerx",
        "load", "loads",
        "haul", "hauling",
        "freight",
        "settlement",
        "factoring", "factor",
        "dispatch",
        "detention",
        "layover",
        "lumper",
        "1099",
        "fuel",
        "mile", "miles", "mileage",
        "rate con", "ratecon",
        "paystub",
        "owner-operator", "owner operator",
        "trucking", "trucker",
        "carrier",
        "trip pay", "trip",
        "ifta",
        "business",
        "llc", "inc.",
    ]
}
