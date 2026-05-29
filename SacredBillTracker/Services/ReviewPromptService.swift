//
//  ReviewPromptService.swift
//  SacredBillTracker
//
//  Centralised gate for Apple's in-app review prompt
//  (`RequestReviewAction` / `SKStoreReviewController`).
//
//  Trigger rules (per Apple's HIG + App Store Review Guideline 1.1.7):
//    - Only after a "positive moment" — adding the 3rd bill, marking a
//      bill as paid, or another upbeat user action.
//    - NEVER on first launch — the user must have come back at least once.
//    - At most once per app version (Apple itself caps to 3/365 days, but
//      we add a per-version + 30-day floor so we don't ask twice in the
//      same release cycle).
//    - The actual "Rate this app?" sheet is rendered by the system —
//      we never show a custom replacement.
//
//  How call sites use it:
//
//    1. Once per cold launch:
//          ReviewPromptService.shared.recordAppLaunch()
//
//    2. At a positive moment in BillStore:
//          ReviewPromptService.shared.recordPositiveMoment()
//
//    3. SwiftUI scene observes `pendingReviewRequest`. When it flips
//       non-nil, the view calls `@Environment(\.requestReview)` and
//       then `markRequested()` to clear the flag.
//

import Foundation
import SwiftUI

@MainActor
final class ReviewPromptService: ObservableObject {

    static let shared = ReviewPromptService()

    /// Set to a fresh UUID when a prompt should be shown. The scene
    /// observes this and invokes `RequestReviewAction`. Cleared via
    /// `markRequested()`.
    @Published var pendingReviewRequest: UUID?

    // MARK: - UserDefaults keys

    private let launchCountKey       = "sbt.review.launchCount.v1"
    private let positiveMomentKey    = "sbt.review.positiveMomentCount.v1"
    private let lastPromptDateKey    = "sbt.review.lastPromptDate.v1"
    private let lastPromptVersionKey = "sbt.review.lastPromptVersion.v1"

    /// Minimum positive moments before we'd ever ask. The user spec
    /// calls out "user adds their 3rd bill" as the trigger threshold.
    private let positiveMomentThreshold = 3

    /// Soft cooldown so two positive moments in the same session don't
    /// double-ask if Apple's own 3-per-365 cap somehow lets it through.
    private let perVersionCooldownDays = 30

    private let defaults = UserDefaults.standard

    private init() {}

    // MARK: - Public API

    /// Call exactly once per cold launch (App `.task`).
    func recordAppLaunch() {
        let n = launchCount + 1
        defaults.set(n, forKey: launchCountKey)
    }

    /// Increment the positive-moment count. If the gate opens, set
    /// `pendingReviewRequest` so the SwiftUI scene shows the prompt.
    func recordPositiveMoment() {
        let count = positiveMomentCount + 1
        defaults.set(count, forKey: positiveMomentKey)
        if shouldRequestReview(positiveMomentCount: count) {
            pendingReviewRequest = UUID()
        }
    }

    /// Called by the scene right after invoking `RequestReviewAction`,
    /// so we don't ask again this version.
    func markRequested() {
        defaults.set(Date(), forKey: lastPromptDateKey)
        defaults.set(currentAppVersion, forKey: lastPromptVersionKey)
        pendingReviewRequest = nil
    }

    // MARK: - Gate

    private func shouldRequestReview(positiveMomentCount count: Int) -> Bool {
        // Never on first launch.
        guard launchCount >= 2 else { return false }

        // Need at least N positive moments overall.
        guard count >= positiveMomentThreshold else { return false }

        // Already asked in this app version → never re-ask in same version.
        if let lastVersion = defaults.string(forKey: lastPromptVersionKey),
           lastVersion == currentAppVersion {
            return false
        }

        // Per-version cooldown floor (defense in depth).
        if let lastDate = defaults.object(forKey: lastPromptDateKey) as? Date {
            let days = Calendar.current
                .dateComponents([.day], from: lastDate, to: Date())
                .day ?? 0
            if days < perVersionCooldownDays { return false }
        }

        return true
    }

    // MARK: - Internals

    private var launchCount: Int {
        defaults.integer(forKey: launchCountKey)
    }

    private var positiveMomentCount: Int {
        defaults.integer(forKey: positiveMomentKey)
    }

    private var currentAppVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0"
    }
}
