//
//  NotificationCategories.swift
//  Sacred Pathway Driver Hub — P5 (Notifications)
//
//  Single source of truth for what kinds of notifications we send.
//  Each category has a stable ID (used for prefs + dedupe), display name, and default state.
//

import Foundation

enum NotificationCategory: String, CaseIterable, Identifiable, Codable {

    case settlementCreated      = "settlement.created"
    case settlementSynced       = "settlement.synced"
    case syncFailed             = "sync.failed"
    case shareLinkExpiringSoon  = "share.expiring_soon"
    case shareLinkExpired       = "share.expired"
    case exportCompleted        = "export.completed"
    case earningsSummaryWeekly  = "earnings.summary.weekly"
    case earningsSummaryMonthly = "earnings.summary.monthly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settlementCreated:      return "New Settlement"
        case .settlementSynced:       return "Settlements Synced"
        case .syncFailed:             return "Sync Issue"
        case .shareLinkExpiringSoon:  return "Share Link Expiring"
        case .shareLinkExpired:       return "Share Link Expired"
        case .exportCompleted:        return "Export Ready"
        case .earningsSummaryWeekly:  return "Weekly Earnings Summary"
        case .earningsSummaryMonthly: return "Monthly Earnings Summary"
        }
    }

    var description: String {
        switch self {
        case .settlementCreated:      return "When a new paystub or settlement is generated."
        case .settlementSynced:       return "When new settlements arrive from another device."
        case .syncFailed:             return "When the app can't reach the cloud (debounced)."
        case .shareLinkExpiringSoon:  return "24 hours before a lender share link expires."
        case .shareLinkExpired:       return "When a lender share link expires or is auto-revoked."
        case .exportCompleted:        return "When a CSV or ZIP export finishes generating."
        case .earningsSummaryWeekly:  return "Friday afternoon summary of the past week's earnings."
        case .earningsSummaryMonthly: return "First of each month, summary of the previous month."
        }
    }

    var defaultEnabled: Bool {
        switch self {
        // Spammy candidates — off by default
        case .syncFailed,
             .earningsSummaryWeekly,
             .earningsSummaryMonthly:
            return false
        // Actionable / business-critical — on by default
        default:
            return true
        }
    }

    /// Apple's interruption level. Time-sensitive raises priority above quiet hours
    /// (only used by the OS — we still respect our own quiet-hours setting in app code).
    var interruptionLevel: NotificationInterruptionLevel {
        switch self {
        case .settlementCreated,
             .shareLinkExpiringSoon,
             .shareLinkExpired,
             .syncFailed:
            return .timeSensitive
        case .exportCompleted,
             .settlementSynced:
            return .active
        case .earningsSummaryWeekly,
             .earningsSummaryMonthly:
            return .passive
        }
    }

    /// True for notifications that MIGHT contain dollar amounts in the body.
    /// When user enables Lock-Screen Privacy, these get a redacted body.
    var canContainSensitiveData: Bool {
        switch self {
        case .settlementCreated,
             .settlementSynced,
             .earningsSummaryWeekly,
             .earningsSummaryMonthly:
            return true
        case .shareLinkExpiringSoon,
             .shareLinkExpired,
             .exportCompleted,
             .syncFailed:
            return false
        }
    }

    var deepLink: NotificationDeepLink {
        switch self {
        case .settlementCreated:      return .settlementDetail
        case .settlementSynced:       return .settlementHistory
        case .syncFailed:             return .settlementHistory
        case .shareLinkExpiringSoon,
             .shareLinkExpired:       return .shareLinks
        case .exportCompleted:        return .settlementHistory
        case .earningsSummaryWeekly,
             .earningsSummaryMonthly: return .earningsSummary
        }
    }
}

/// Cross-iOS-version stand-in so this file compiles standalone.
enum NotificationInterruptionLevel {
    case passive, active, timeSensitive, critical
}

// MARK: - Deep link
enum NotificationDeepLink: String, Codable {
    case settlementHistory = "/history"
    case settlementDetail  = "/history/detail"
    case earningsSummary   = "/summary"
    case shareLinks        = "/shares"
}
