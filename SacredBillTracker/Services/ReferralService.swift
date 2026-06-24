//
//  ReferralService.swift
//  SacredBillTracker
//
//  Client for the Supabase referral backend:
//    get_or_create_referral_code · apply_referral_code · referral_dashboard
//  Fraud rules (self-referral, dup user, device dedup, 30-day qualification,
//  refund/cancel void) are enforced server-side.
//

import Foundation
#if os(iOS)
import UIKit
#endif
#if canImport(Supabase)
import Supabase
#endif

struct ReferralRewardItem: Identifiable, Decodable {
    let date: String
    let role: String
    let amount_cents: Int
    let status: String
    let reason: String?
    var id: String { date + role + String(amount_cents) }

    var amountDisplay: String { String(format: "$%.2f", Double(amount_cents) / 100.0) }
}

struct ReferralDashboard: Decodable {
    let code: String
    let referrals: Int
    let credits_cents: Int
    let pending: Int
    let history: [ReferralRewardItem]

    var creditsDisplay: String { String(format: "$%.2f", Double(credits_cents) / 100.0) }
    static let empty = ReferralDashboard(code: "—", referrals: 0, credits_cents: 0, pending: 0, history: [])
}

@MainActor
final class ReferralService: ObservableObject {
    static let shared = ReferralService()

    @Published private(set) var dashboard: ReferralDashboard = .empty
    @Published var isLoading = false
    @Published var lastError: String?

    /// Stable per-install fingerprint for device-abuse dedup (best effort).
    private var deviceFingerprint: String? {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    func refresh() async {
        #if canImport(Supabase)
        isLoading = true
        defer { isLoading = false }
        do {
            let result: ReferralDashboard = try await SupabaseConfig.client
                .rpc("referral_dashboard").execute().value
            dashboard = result
        } catch {
            lastError = error.localizedDescription
        }
        #endif
    }

    /// Apply a referral code entered by a new user. Returns nil on success,
    /// or a user-facing error string.
    func applyCode(_ code: String) async -> String? {
        #if canImport(Supabase)
        struct Params: Encodable { let p_code: String; let p_device: String? }
        struct Result: Decodable { let ok: Bool; let error: String? }
        do {
            let res: Result = try await SupabaseConfig.client
                .rpc("apply_referral_code",
                     params: Params(p_code: code.uppercased(), p_device: deviceFingerprint))
                .execute().value
            if res.ok {
                await AnalyticsService.shared.log(.referralCodeApplied, source: "onboarding")
                return nil
            }
            switch res.error {
            case "invalid_code":        return "That code wasn't found."
            case "self_referral":       return "You can't use your own code."
            case "already_referred":    return "A referral code was already applied to this account."
            case "device_already_used": return "This device has already used a referral code."
            default:                    return "Couldn't apply that code. Please try again."
            }
        } catch {
            return error.localizedDescription
        }
        #else
        return "Referrals are unavailable."
        #endif
    }
}
