//
//  PartnerService.swift
//  SacredBillTracker
//
//  Handles partner invitations.
//
//  Note: there is NO partner discount in this app. Each partner manages
//  their own subscription separately. If you see a TODO about discounts,
//  you're looking at an old branch — strip it.
//
//  IMPORTANT (per integration spec):
//    If `isBackendReady` is false, we DO NOT fake working logic. The UI
//    shows a "Partner invites are coming soon." banner and `sendInvite`
//    short-circuits with that same message.
//
//  When the Supabase tables + RPC exist, flip `isBackendReady` to true
//  and replace the TODO blocks with real network calls.
//

import Foundation
import Combine

@MainActor
final class PartnerService: ObservableObject {

    // Flip to true ONLY when backend tables + RPCs exist.
    static let isBackendReady: Bool = false

    @Published private(set) var invite: PartnerInvite?
    @Published private(set) var status: PartnerStatus = .none
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    private let currentUserId: String

    init(currentUserId: String) {
        self.currentUserId = currentUserId
    }

    // MARK: - Public API

    func loadCurrentInvite() async {
        guard Self.isBackendReady else { return }
        isLoading = true
        // TODO: SELECT * FROM partner_invites
        //       WHERE inviter_id = currentUserId OR invited_user_id = currentUserId
        //       LIMIT 1
        isLoading = false
    }

    /// Send an invite to a partner email.
    /// Returns true if sent, false if backend not ready or validation failed.
    @discardableResult
    func sendInvite(toEmail email: String) async -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidEmail(trimmed) else {
            lastError = "Please enter a valid email address."
            return false
        }
        guard Self.isBackendReady else {
            lastError = "Partner invites are coming soon."
            return false
        }

        isLoading = true

        // TODO: INSERT INTO partner_invites (inviter_id, invited_email, status)
        //       VALUES (currentUserId, trimmed, 'pending')
        //       Trigger email via Supabase Edge Function or Resend.

        isLoading = false
        return true
    }

    func cancelInvite() async {
        guard Self.isBackendReady else { return }
        // TODO: DELETE FROM partner_invites WHERE id = invite.id
        invite = nil
        status = .none
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }
}
