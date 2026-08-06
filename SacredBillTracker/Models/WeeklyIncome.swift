//
//  WeeklyIncome.swift
//  SacredBillTracker
//
//  A single weekly-income entry: how much the user earned during a
//  defined week, plus optional source / note / type. Persisted locally
//  via UserDefaults (same offline-first pattern as Bill /
//  LocalBillRepository) AND mirrored to iCloud KVS for cross-device.
//
//  v1.0.9 adds:
//    - `type` (Business / Personal) for the dashboard income split
//    - `sourceName` (e.g. "BrokerX", "Side hustle") as a structured
//      first-class field separate from `note`
//
//  Backward-compatible decoder: entries written before v1.0.9 simply
//  don't carry these keys and decode as `.business` + empty source.
//

import Foundation

struct WeeklyIncome: Identifiable, Codable, Hashable {

    // MARK: - Stored

    var id: UUID
    var amount: Decimal
    var weekStart: Date
    var weekEnd: Date

    /// Business vs Personal. Drives the dashboard income split, the
    /// percentage comparison, and the Type column in CPA Export.
    /// v1.0.9+
    var type: IncomeType

    /// First-class "where did this money come from" field. v1.0.9+
    /// (Pre-v1.0.9 entries surface their old `note` here automatically.)
    var sourceName: String

    /// Free-form note — "Heavy haul Monday", "Detention pay", etc.
    /// Optional, separate from `sourceName`.
    var note: String

    /// Stable external identifier for bank-imported income. Holds the Plaid
    /// `plaid_transaction_id` for entries created automatically from a
    /// connected bank via AutoTrack. `nil` for manually-entered income.
    /// Used so re-syncing replaces bank entries cleanly instead of
    /// duplicating them. v1.8+
    var externalRef: String?

    /// Business / personal classification of the *source bank account* for
    /// imported income (mirrors `plaid_accounts.usage_type`). `nil` for
    /// manually-entered income. Drives the All / Personal / Business tabs so
    /// business income is never summed into Personal totals. v1.9+
    var bankUsage: AccountUsageType?

    /// True when this entry was imported from a connected bank account
    /// (i.e. carries a Plaid transaction reference) rather than typed in.
    var isBankImported: Bool { externalRef != nil }

    /// Which dashboard tab (All / Personal / Business) this entry belongs to.
    /// Bank-imported entries follow their account's classification; manual
    /// entries follow their `type`. Ensures business income never lands in
    /// Personal totals and `unknown` bank income only appears under "All".
    var usageTab: AccountUsageType {
        if isBankImported { return bankUsage ?? .unknown }
        return type == .business ? .business : .personal
    }

    /// Account-owned financial profile. Nil is treated as the owner's
    /// default profile for backward compatibility with older income JSON.
    var profileID: UUID?

    /// Signed-in account that owns this income entry. Managed profiles
    /// are not separate auth users, so every profile-scoped income row
    /// still belongs to the main subscriber account.
    var ownerUserID: UUID?

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        amount: Decimal,
        weekStart: Date,
        weekEnd: Date,
        type: IncomeType = .business,
        sourceName: String = "",
        note: String = "",
        externalRef: String? = nil,
        bankUsage: AccountUsageType? = nil,
        profileID: UUID? = nil,
        ownerUserID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.amount = amount
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.type = type
        self.sourceName = sourceName
        self.note = note
        self.externalRef = externalRef
        self.bankUsage = bankUsage
        self.profileID = profileID
        self.ownerUserID = ownerUserID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable
    //
    // Synthesized encode + custom decode so older JSON without
    // `type` / `sourceName` / `note` still loads cleanly.

    private enum CodingKeys: String, CodingKey {
        case id, amount, weekStart, weekEnd, type, sourceName, note
        case externalRef, bankUsage, profileID, ownerUserID, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = try c.decode(UUID.self,    forKey: .id)
        self.amount    = try c.decode(Decimal.self, forKey: .amount)
        self.weekStart = try c.decode(Date.self,    forKey: .weekStart)
        self.weekEnd   = try c.decode(Date.self,    forKey: .weekEnd)

        // v1.0.9 fields — fall back gracefully for older payloads.
        let decodedNote = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        let resolvedSource: String
        let resolvedNote: String
        if let storedSource = try c.decodeIfPresent(String.self, forKey: .sourceName) {
            resolvedSource = storedSource
            resolvedNote = decodedNote
        } else {
            // Migrate: pre-v1.0.9 records used `note` as a combined
            // source/note. Promote it into `sourceName` so the new UI
            // displays it in the right slot.
            resolvedSource = decodedNote
            resolvedNote = ""
        }
        self.sourceName = resolvedSource
        self.note = resolvedNote
        self.externalRef = try c.decodeIfPresent(String.self, forKey: .externalRef)
        self.bankUsage = try c.decodeIfPresent(AccountUsageType.self, forKey: .bankUsage)
        self.profileID = try c.decodeIfPresent(UUID.self, forKey: .profileID)
        self.ownerUserID = try c.decodeIfPresent(UUID.self, forKey: .ownerUserID)

        // Type: respect any explicitly-saved value; otherwise classify
        // by scanning the source/note for business indicators. Falls
        // back to `.personal` when no signal is present so the user is
        // free to edit later instead of being silently mis-tagged.
        if let stored = try c.decodeIfPresent(IncomeType.self, forKey: .type) {
            self.type = stored
        } else {
            let combined = (resolvedSource + " " + resolvedNote)
                .trimmingCharacters(in: .whitespaces)
            self.type = IncomeType.inferLegacyType(from: combined)
        }

        self.createdAt = try c.decode(Date.self,    forKey: .createdAt)
        self.updatedAt = try c.decode(Date.self,    forKey: .updatedAt)
    }

    // MARK: - Derived

    /// The date this entry's income is attributed to when bucketing into
    /// a week / month / year.
    ///
    /// Every entry created since the single-Date Add Income flow, and every
    /// Plaid import, stores `weekStart == weekEnd`, so this is simply that
    /// day. Only *legacy* week-range rows (Mon→Sun) differ, and those are
    /// attributed to `weekEnd` — the settlement date the week pays out on.
    ///
    /// This is what fixes the "This Month income = $0" bug: a legacy week
    /// like Mon Jun 29 → Sun Jul 5 previously bucketed under `weekStart`
    /// (June), so it fell outside July's range and disappeared from the
    /// current month until the first Monday landed inside that month.
    /// Attributing by `weekEnd` puts it in exactly one month — July —
    /// so months never double-count and never drop a straddling week.
    ///
    /// `max` guards against any corrupt row where `weekEnd < weekStart`.
    var incomeDate: Date { max(weekStart, weekEnd) }

    /// The "anchor" date used when bucketing into a month.
    var bucketDate: Date { incomeDate }

    /// Single-date convenience — the Add Income flow now stores one
    /// date per entry. The model keeps a week range under the hood so
    /// existing weekly / 30-day calculations keep working.
    var entryDate: Date { weekStart }

    var formattedAmount: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    /// "May 11 – May 17" style range label. If start == end, returns
    /// the single-date form ("May 17") used by entries created via the
    /// new single-Date Add Income flow.
    var rangeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let cal = Calendar.current
        if cal.isDate(weekStart, inSameDayAs: weekEnd) {
            return fmt.string(from: weekStart)
        }
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: weekEnd))"
    }

    /// "May 11 – May 17, 2026" — includes year. Used by the PDF.
    var rangeLabelWithYear: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let yfmt = DateFormatter()
        yfmt.dateFormat = "yyyy"
        let cal = Calendar.current
        if cal.isDate(weekStart, inSameDayAs: weekEnd) {
            return "\(fmt.string(from: weekStart)), \(yfmt.string(from: weekEnd))"
        }
        return "\(fmt.string(from: weekStart)) – \(fmt.string(from: weekEnd)), \(yfmt.string(from: weekEnd))"
    }

    // MARK: - Defaults

    /// Returns the current Monday → Sunday week for the user's calendar.
    /// Used as the default range in the "Add Income" form.
    static func currentWeekBounds(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let now = Date()
        var cal = calendar
        // Force Monday-start regardless of locale — most owner-operator
        // settlement statements run Mon→Sun.
        cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else {
            return (now, now)
        }
        // `dateInterval(of:.weekOfYear)` returns [start, endExclusive),
        // so subtract one second so weekEnd reads "Sun 23:59:59".
        let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        return (cal.startOfDay(for: interval.start), end)
    }
}

// MARK: - AccountUsageType (v1.9 — bank account business/personal classification)

/// Business vs personal classification of a *connected bank account*
/// (mirrors `plaid_accounts.usage_type`). Distinct from `IncomeType`: an
/// account can be `unknown` until the auto-classifier or the user decides,
/// whereas every income entry still carries a binary Business/Personal label.
/// This type drives the All / Personal / Business dashboard tabs.
enum AccountUsageType: String, Codable, CaseIterable, Identifiable, Hashable {
    case personal
    case business
    case unknown

    var id: String { rawValue }

    /// Decodes leniently — any unrecognized / missing value becomes `.unknown`.
    init(safe raw: String?) {
        self = AccountUsageType(rawValue: (raw ?? "").lowercased()) ?? .unknown
    }

    var title: String {
        switch self {
        case .personal: return "Personal"
        case .business: return "Business"
        case .unknown:  return "Needs review"
        }
    }

    var systemImage: String {
        switch self {
        case .personal: return "house.fill"
        case .business: return "briefcase.fill"
        case .unknown:  return "questionmark.circle.fill"
        }
    }

    /// Binary income label used by the rest of the app. `unknown` falls back
    /// to `.business` (the owner-operator default) only as a placeholder for
    /// `WeeklyIncome.type`; tab filtering always uses `usageTab`, never this,
    /// so unknown income is never counted as Business in the Business tab.
    var incomeType: IncomeType {
        switch self {
        case .business: return .business
        case .personal: return .personal
        case .unknown:  return .business
        }
    }
}
