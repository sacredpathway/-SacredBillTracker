//
//  AppearancePreference.swift
//  SacredBillTracker
//
//  v1.0.9 — User-controlled Light / Dark / System appearance. Stored
//  in AppStorage under `sbt.appearance.v1` and applied at the app root
//  via `.preferredColorScheme(_:)`.
//

import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable, Codable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Use System Setting"
        case .light:  return "Light Mode"
        case .dark:   return "Dark Mode"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// SwiftUI scheme to feed `.preferredColorScheme`. nil means
    /// follow the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    static func from(rawValue: String) -> AppearancePreference {
        AppearancePreference(rawValue: rawValue) ?? .system
    }
}
