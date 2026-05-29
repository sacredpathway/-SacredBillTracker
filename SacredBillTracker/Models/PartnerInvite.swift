//
//  PartnerInvite.swift
//  SacredBillTracker
//
//  Mirror of a future Supabase `partner_invites` table. Currently
//  unused at runtime — `PartnerService.isBackendReady` is false — but
//  kept here so the UI can compile against the real shape.
//

import Foundation

enum PartnerStatus: String, Codable {
    case none           // no partner connected
    case pending        // invite sent, awaiting partner
    case connected      // partner joined
}

struct PartnerInvite: Identifiable, Codable, Hashable {
    let id: UUID
    var inviterId: String
    var invitedEmail: String
    var invitedUserId: String?       // populated when partner signs up
    var status: PartnerStatus
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case inviterId         = "inviter_id"
        case invitedEmail      = "invited_email"
        case invitedUserId     = "invited_user_id"
        case status
        case createdAt         = "created_at"
    }
}
