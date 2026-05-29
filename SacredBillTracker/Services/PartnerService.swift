//
//  PartnerService.swift
//  SacredBillTracker
//
//  Handles partner invitations against Supabase `partner_invites` table.
//
//  Backend live as of v1.0.5. Schema + RLS in
//  `partner_invites_migration.sql`. RPC: `accept_partner_invite(p_invite_id uuid)`.
//
//  Each partner manages their own subscription separately — there is
//  NO partner discount.
//

import Foundation
import Combine

#if canImport(Supabase)
import Supabase
#endif

@MainActor
final class PartnerService: ObservableObject {

    /// Backend is live. Keep this flag so tests / previews can flip it
    /// off if Supabase is unreachable.
    static let isBackendReady: Bool = true

    /// The user's OUTGOING invite (most recent one they sent).
    @Published private(set) var invite: PartnerInvite?
    @Published private(set) var status: PartnerStatus = .none

    /// An INCOMING pending invite addressed to this user's email that
    /// they have not accepted yet. Surfaced as a banner with [Accept]
    /// in PartnerBudgetingView. RLS allows the user to SELECT this row
    /// because policy `select own invites` matches by JWT email.
    @Published private(set) var incomingInvite: PartnerInvite?

    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    private let currentUserId: String
    private let table = "partner_invites"

    init(currentUserId: String) {
        // Critical normalization — Postgres stores UUIDs lowercase and the
        // Supabase REST API echoes them back lowercase. Swift's
        // `UUID.uuidString` returns UPPERCASE. If we don't lowercase here,
        // every `invite.inviterId == currentUserId` comparison fails after
        // a fresh `loadCurrentInvite()` and the UI reverts to "No partner
        // connected" even though the row exists. (Build 20 fix.)
        self.currentUserId = currentUserId.lowercased()
    }

    // MARK: - Public API

    /// Loads BOTH outgoing and incoming invites in one round-trip.
    /// RLS handles row visibility: the user sees rows where they are
    /// inviter, invitee_user_id, OR (for pending invites) where their
    /// JWT email matches `invited_email`.
    func loadCurrentInvite() async {
        guard Self.isBackendReady else { return }
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        do {
            // No client-side filter — RLS does the scoping. This is the
            // critical fix for build 16: pending invites have
            // `invited_user_id = NULL`, so the previous query
            // `inviter_id.eq.X,invited_user_id.eq.X` filtered them out
            // and the invitee never saw their incoming invite.
            let rows: [PartnerInvite] = try await SupabaseConfig.client
                .from(table)
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value

            // Split rows into outgoing vs incoming relative to current user.
            // Both inviterId and invitedUserId are String (UUID-as-string)
            // in the model, so plain string equality is correct.
            let me = currentUserId

            let outgoing = rows.first(where: { invite in
                invite.inviterId == me
            })

            let incoming = rows.first(where: { invite in
                // Incoming = sent by someone else AND addressed to me by
                // either email (pending) or user_id (already-accepted
                // connection from the partner side).
                guard invite.inviterId != me else { return false }
                return invite.status == .pending
                    || invite.invitedUserId == me
            })

            self.invite          = outgoing
            self.status          = outgoing?.status ?? .none
            self.incomingInvite  = incoming
            self.lastError       = nil

            // If the user has no outgoing invite but DOES have an
            // already-connected incoming partnership, surface that as
            // their connection status so Settings shows "Partner joined".
            if outgoing == nil,
               let connected = rows.first(where: { row in
                   row.status == .connected && row.invitedUserId == me
               }) {
                self.invite          = connected
                self.status          = .connected
                self.incomingInvite  = nil
            }
        } catch {
            self.lastError = userFacingMessage(from: error)
        }
        #endif
    }

    /// Send an invite to a partner email.
    /// Returns true if sent, false if validation failed or backend errored.
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
        defer { isLoading = false }

        #if canImport(Supabase)
        struct InsertRow: Encodable {
            let inviter_id: String
            let invited_email: String
            let status: String
        }

        do {
            let payload = InsertRow(
                inviter_id: currentUserId,
                invited_email: trimmed.lowercased(),
                status: "pending"
            )
            let inserted: [PartnerInvite] = try await SupabaseConfig.client
                .from(table)
                .insert(payload, returning: .representation)
                .select()
                .execute()
                .value

            self.invite    = inserted.first
            self.status    = .pending
            self.lastError = nil
            return true
        } catch {
            self.lastError = userFacingMessage(from: error)
            return false
        }
        #else
        lastError = "Supabase SDK not linked."
        return false
        #endif
    }

    /// Invitee-side: link self to a pending invite addressed to my email.
    /// On success the incoming-invite banner is cleared and the
    /// connected partnership becomes the surfaced state. We also kick
    /// off `loadCurrentInvite()` so the view re-renders with the
    /// authoritative server state (eliminates stale-cache display
    /// like "still pending" after acceptance).
    @discardableResult
    func acceptInvite(id: UUID) async -> Bool {
        guard Self.isBackendReady else { return false }
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        struct Args: Encodable { let p_invite_id: UUID }
        do {
            let row: PartnerInvite = try await SupabaseConfig.client
                .rpc("accept_partner_invite", params: Args(p_invite_id: id))
                .execute()
                .value

            // Build 17 fix — banner persistence:
            // 1. Drop the incoming-invite ref so the green banner unmounts immediately
            // 2. Set connected state from RPC result so the connected card mounts
            // 3. Re-load to reconcile with server (defensive against any
            //    other concurrent mutation)
            self.incomingInvite = nil
            self.invite  = row
            self.status  = .connected
            self.lastError = nil

            // Fire-and-forget reconcile; we already have authoritative
            // state from the RPC, this just guarantees the rest of the
            // UI (connected partner email, status footer, etc.) is in sync.
            Task { await self.loadCurrentInvite() }
            return true
        } catch {
            self.lastError = userFacingMessage(from: error)
            return false
        }
        #else
        return false
        #endif
    }

    /// Invitee-side: decline a pending incoming invite. The invitee can
    /// only delete an invite addressed to their email/uid (RLS-enforced).
    /// Falls back gracefully if the row was already removed by the inviter.
    @discardableResult
    func declineInvite(id: UUID) async -> Bool {
        guard Self.isBackendReady else { return false }
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        do {
            try await SupabaseConfig.client
                .from(table)
                .delete()
                .eq("id", value: id)
                .execute()
            self.incomingInvite = nil
            self.lastError = nil
            return true
        } catch {
            self.lastError = userFacingMessage(from: error)
            return false
        }
        #else
        return false
        #endif
    }

    func cancelInvite() async {
        guard Self.isBackendReady, let inviteId = invite?.id else { return }
        isLoading = true
        defer { isLoading = false }

        #if canImport(Supabase)
        do {
            try await SupabaseConfig.client
                .from(table)
                .delete()
                .eq("id", value: inviteId)
                .eq("inviter_id", value: currentUserId)
                .execute()
            self.invite = nil
            self.status = .none
            self.lastError = nil
        } catch {
            self.lastError = userFacingMessage(from: error)
        }
        #endif
    }

    // MARK: - Helpers

    private func isValidEmail(_ email: String) -> Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: pattern, options: .regularExpression) != nil
    }

    /// Map a thrown error into a user-facing string. Cancellations and
    /// "operation cancelled" URLErrors are NEVER surfaced — they happen
    /// in normal flow when SwiftUI re-fires `.task { ... }` or the user
    /// taps Cancel mid-request, and showing them produces the dreaded
    /// "Swift.CancellationError error 1." red text on screen.
    /// Returns nil if the error should be silently swallowed.
    private func userFacingMessage(from error: Error) -> String? {
        if error is CancellationError { return nil }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return nil
        }
        // NSError equivalent of CancellationError that some SDKs surface.
        let ns = error as NSError
        if ns.domain == "Swift.CancellationError" { return nil }
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            return nil
        }
        return error.localizedDescription
    }
}
