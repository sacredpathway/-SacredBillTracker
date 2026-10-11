//
//  AnalyticsService.swift
//  SacredBillTracker
//
//  Thin client over the Supabase `log_analytics_event` RPC. Fire-and-forget;
//  failures never block the UI. Powers paywall funnel + conversion dashboards.
//

import Foundation
#if canImport(Supabase)
import Supabase
#endif

enum AnalyticsEvent: String {
    case educationViewed = "education_viewed"
    case educationSaved = "education_saved"
    case educationShared = "education_shared"
    case retentionStarted = "retention_started"
    case discountShown = "discount_shown"
    case discountAccepted = "discount_accepted"
    case discountDeclined = "discount_declined"
    case lifetimeShown = "lifetime_shown"
    case lifetimeAccepted = "lifetime_accepted"
    case lifetimeDeclined = "lifetime_declined"
    case subscriptionManagementOpened = "subscription_management_opened"
    case marketingOptIn = "marketing_opt_in"
    case marketingOptOut = "marketing_opt_out"
    case paywallView         = "paywall_view"
    case planSelected        = "plan_selected"
    case purchase            = "purchase"
    case upgrade             = "upgrade"
    case downgrade           = "downgrade"
    case restore             = "restore"
    case trialStart          = "trial_start"
    case referralConversion  = "referral_conversion"
    case referralCodeApplied = "referral_code_applied"
    case referralShared      = "referral_shared"
    case upsellShown         = "upsell_shown"
    case upsellTapped        = "upsell_tapped"
    // v1.1 (Milestone 1) — first-run / activation funnel.
    case onboardingStarted   = "onboarding_started"
    case onboardingCompleted = "onboarding_completed"
    case onboardingSkipped   = "onboarding_skipped"
    case sampleDataPreviewed = "sample_data_previewed"
    case firstBillStarted    = "first_bill_started"
    case firstBillCreated    = "first_bill_created"
}

final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    /// Log an event. `tier` and `source` are optional dimensions.
    func log(_ event: AnalyticsEvent,
             tier: String? = nil,
             source: String? = nil,
             properties: [String: String] = [:]) async {
        guard UserDefaults.standard.bool(forKey: AnalyticsPrivacy.consentKey) else { return }
        // Deliberate allowlist: never forward free-form values, identifiers or financial data.
        let safe = AnalyticsPrivacy.dimensions(tier: tier, source: source)
        #if canImport(Supabase)
        struct Params: Encodable {
            let p_event_type: String
            let p_tier: String?
            let p_source: String?
            let p_properties: [String: String]
        }
        let params = Params(p_event_type: event.rawValue,
                            p_tier: safe.tier, p_source: safe.source, p_properties: [:])
        do {
            try await SupabaseConfig.client.rpc("log_analytics_event", params: params).execute()
        } catch {
            #if DEBUG
            print("[Analytics] \(event.rawValue) failed: \(error)")
            #endif
        }
        #endif
    }

    /// Convenience non-async fire-and-forget for view callbacks.
    func track(_ event: AnalyticsEvent, tier: String? = nil, source: String? = nil) {
        Task { await log(event, tier: tier, source: source) }
    }
}

/// Analytics consent is separate from sign-in and marketing; absent means OFF.
enum AnalyticsPrivacy {
    static let consentKey = "sbt.analytics.consent.v1"
    static func dimensions(tier: String?, source: String?) -> (tier: String?, source: String?) {
        let tiers: Set<String> = ["free", "essential", "business", "unlimited"]
        let sources: Set<String> = ["paywall", "settings", "education", "retention", "onboarding"]
        return (tier.flatMap { tiers.contains($0) ? $0 : nil },
                source.flatMap { sources.contains($0) ? $0 : nil })
    }
}
