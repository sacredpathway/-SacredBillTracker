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
}

final class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}

    /// Log an event. `tier` and `source` are optional dimensions.
    func log(_ event: AnalyticsEvent,
             tier: String? = nil,
             source: String? = nil,
             properties: [String: String] = [:]) async {
        #if canImport(Supabase)
        struct Params: Encodable {
            let p_event_type: String
            let p_tier: String?
            let p_source: String?
            let p_properties: [String: String]
        }
        let params = Params(p_event_type: event.rawValue,
                            p_tier: tier, p_source: source, p_properties: properties)
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
