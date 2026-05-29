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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Codable
    //
    // Synthesized encode + custom decode so older JSON without
    // `type` / `sourceName` / `note` still loads cleanly.

    private enum CodingKeys: String, CodingKey {
        case id, amount, weekStart, weekEnd, type, sourceName, note, createdAt, updatedAt
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

    /// The "anchor" date used when bucketing into a month — uses
    /// `weekStart` so a week that straddles two months is reported
    /// under the month it began.
    var bucketDate: Date { weekStart }

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
