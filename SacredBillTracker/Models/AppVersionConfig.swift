//
//  AppVersionConfig.swift
//  SacredBillTracker
//
//  Remote version-gating config fetched from Supabase table
//  `app_version_config`. The single most-recent row controls whether
//  the running build is allowed, prompted to update, or hard-blocked.
//
//  Schema (see migration `app_version_config_migration.sql`):
//    minimum_supported_build  : int  — builds < this are HARD BLOCKED
//    latest_build             : int  — most recent App Store build
//    update_required_message  : text — copy shown on the block screen
//    app_store_url            : text — deep link tapped to update
//    is_force_update_enabled  : bool — master kill-switch (false = never block)
//
//  Public read RLS only — no auth needed for the gate fetch.
//

import Foundation

struct AppVersionConfig: Codable, Equatable {

    let minimumSupportedBuild: Int
    let latestBuild: Int
    let updateRequiredMessage: String
    let appStoreURL: String
    let isForceUpdateEnabled: Bool

    /// Server timestamp — used for cache freshness comparisons. Optional
    /// because older rows may not have it set yet.
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case minimumSupportedBuild  = "minimum_supported_build"
        case latestBuild            = "latest_build"
        case updateRequiredMessage  = "update_required_message"
        case appStoreURL            = "app_store_url"
        case isForceUpdateEnabled   = "is_force_update_enabled"
        case updatedAt              = "updated_at"
    }

    /// Production fallback — used ONLY when no remote config has ever
    /// been cached and the network is unreachable on first launch. Keeps
    /// the app usable. `isForceUpdateEnabled = false` means the gate
    /// stays open under fallback.
    static let safeFallback = AppVersionConfig(
        minimumSupportedBuild: 1,
        latestBuild: 1,
        updateRequiredMessage:
            "A newer version of Sacred Bill Tracker is required to continue. Please update the app to keep using your account safely.",
        appStoreURL: "https://apps.apple.com/app/id6762890363",
        isForceUpdateEnabled: false,
        updatedAt: nil
    )
}
