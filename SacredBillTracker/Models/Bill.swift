//
//  Bill.swift
//  SacredBillTracker
//
//  The core bill entity. Codable for local persistence and future Supabase sync.
//

import Foundation

enum PayoffCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case mortgage
    case autoLoan = "auto_loan"
    case creditCard = "credit_card"
    case personalLoan = "personal_loan"
    case studentLoan = "student_loan"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mortgage:     return "Mortgage"
        case .autoLoan:     return "Auto Loan"
        case .creditCard:   return "Credit Card"
        case .personalLoan: return "Personal Loan"
        case .studentLoan:  return "Student Loan"
        case .other:        return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .mortgage:     return "house.fill"
        case .autoLoan:     return "car.fill"
        case .creditCard:   return "creditcard.fill"
        case .personalLoan: return "doc.text.fill"
        case .studentLoan:  return "graduationcap.fill"
        case .other:        return "tag.fill"
        }
    }
}

enum PayoffPaymentKind: String, Codable, Hashable {
    case manual
    case autoPay = "auto_pay"
    case reversal

    var title: String {
        switch self {
        case .manual:   return "Manual payment"
        case .autoPay:  return "Auto-Pay"
        case .reversal: return "Reversal"
        }
    }
}

struct PayoffPaymentRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var cycleDueDate: Date
    var amount: Decimal
    var remainingBalanceAfter: Decimal
    var kind: PayoffPaymentKind

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        cycleDueDate: Date,
        amount: Decimal,
        remainingBalanceAfter: Decimal,
        kind: PayoffPaymentKind
    ) {
        self.id = id
        self.date = date
        self.cycleDueDate = cycleDueDate
        self.amount = amount
        self.remainingBalanceAfter = remainingBalanceAfter
        self.kind = kind
    }
}

struct Bill: Identifiable, Codable, Hashable {

    // MARK: - Stored

    var id: UUID
    var name: String
    var amount: Decimal
    var dueDate: Date
    var category: BillCategory
    var recurrence: RecurrenceType
    var type: BillType
    var autoPay: Bool
    var notes: String

    /// User-set status. Computed `effectiveStatus` treats auto-pay bills as
    /// paid and promotes uncovered unpaid bills to `overdue` once the due
    /// date has passed.
    var status: PaymentStatus

    /// When this bill (or its previous occurrence) was last paid. Drives
    /// the "Paid recently" insight and recurring-next-due computation.
    var lastPaidDate: Date?

    var createdAt: Date
    var updatedAt: Date

    /// Marks a bill as visible to a connected partner (Partner Budgeting,
    /// v1.2). Defaults to false so the upgrade is non-breaking — every
    /// existing bill stays in the user's "My Bills" scope until they
    /// explicitly toggle it.
    var isShared: Bool

    /// Soft-delete timestamp (v1.3). When non-nil, this bill is in the
    /// Trash and excluded from all normal queries. Cleared by a Restore
    /// action; row is otherwise never hard-deleted from production code.
    /// Maps to `public.bills.deleted_at` (timestamptz null) in Supabase.
    var deletedAt: Date?

    /// Supabase user_id of the row's owner. Populated when bills come
    /// back from `SupabaseBillRepository` so the UI can distinguish a
    /// user's own bills from a connected partner's shared-in bills
    /// (Partner Budgeting, v1.0.5). Nil for purely-local bills.
    var ownerUserID: UUID?

    // MARK: - 15/3 Paydown Plan (v1.4)
    //
    // Optional, opt-in payment-splitting strategy for revolving-credit
    // bills (credit cards / lines of credit). When `isUsing153Plan` is
    // true, `firstPaydownDate` / `firstPaydownAmount` capture the first
    // 50% payment 15 days before the due date, and
    // `secondPaydownDate` / `secondPaydownAmount` capture the remaining
    // 50% 3 days before the due date. All four fields are recomputed
    // by `PaydownPlanService` whenever the amount or due date changes.
    //
    // Persisted as plain `Optional` fields so existing rows decode
    // cleanly (see custom decoder below).
    var isUsing153Plan: Bool
    var firstPaydownDate: Date?
    var secondPaydownDate: Date?
    var firstPaydownAmount: Decimal?
    var secondPaydownAmount: Decimal?

    // MARK: - Payment Link (v1.5)
    //
    // Optional URL the user types in so they can tap "Pay Bill" on the
    // detail screen and open their biller / bank-pay site in Safari.
    // Stored as the user typed it (normalized to include a scheme by the
    // form before save). The app never auto-pays — it only hands the URL
    // off to `UIApplication.shared.open(_:)`.
    //
    // Persisted as Optional<String> so existing JSON / Supabase rows
    // decode cleanly (see custom decoder below).
    var paymentURL: String?

    // MARK: - Payoff Tracking
    //
    // Optional balance tracking for the user's own large recurring bills
    // (mortgage, auto loan, credit card, personal/student loans, etc.).
    // This is separate from Partner/Sacred Duo logic: deductions simply
    // lower the user's remaining balance when a paid cycle is recorded.
    var isPayoffTrackingEnabled: Bool
    var payoffOriginalBalance: Decimal?
    var payoffRemainingBalance: Decimal?
    var payoffPaymentAmount: Decimal?
    var payoffInterestRate: Decimal?
    var payoffGoalDate: Date?
    var payoffCategory: PayoffCategory?
    var payoffHistory: [PayoffPaymentRecord]

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        amount: Decimal,
        dueDate: Date,
        category: BillCategory,
        recurrence: RecurrenceType = .monthly,
        type: BillType,
        autoPay: Bool = false,
        notes: String = "",
        status: PaymentStatus = .unpaid,
        lastPaidDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isShared: Bool = false,
        deletedAt: Date? = nil,
        ownerUserID: UUID? = nil,
        isUsing153Plan: Bool = false,
        firstPaydownDate: Date? = nil,
        secondPaydownDate: Date? = nil,
        firstPaydownAmount: Decimal? = nil,
        secondPaydownAmount: Decimal? = nil,
        paymentURL: String? = nil,
        isPayoffTrackingEnabled: Bool = false,
        payoffOriginalBalance: Decimal? = nil,
        payoffRemainingBalance: Decimal? = nil,
        payoffPaymentAmount: Decimal? = nil,
        payoffInterestRate: Decimal? = nil,
        payoffGoalDate: Date? = nil,
        payoffCategory: PayoffCategory? = nil,
        payoffHistory: [PayoffPaymentRecord] = []
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.category = category
        self.recurrence = recurrence
        self.type = type
        self.autoPay = autoPay
        self.notes = notes
        self.status = status
        self.lastPaidDate = lastPaidDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isShared = isShared
        self.deletedAt = deletedAt
        self.ownerUserID = ownerUserID
        self.isUsing153Plan = isUsing153Plan
        self.firstPaydownDate = firstPaydownDate
        self.secondPaydownDate = secondPaydownDate
        self.firstPaydownAmount = firstPaydownAmount
        self.secondPaydownAmount = secondPaydownAmount
        self.paymentURL = paymentURL
        self.isPayoffTrackingEnabled = isPayoffTrackingEnabled
        self.payoffOriginalBalance = payoffOriginalBalance
        self.payoffRemainingBalance = payoffRemainingBalance
        self.payoffPaymentAmount = payoffPaymentAmount
        self.payoffInterestRate = payoffInterestRate
        self.payoffGoalDate = payoffGoalDate
        self.payoffCategory = payoffCategory
        self.payoffHistory = payoffHistory
    }

    // MARK: - Codable
    //
    // Custom decoder so older JSON (pre-v1.1 / pre-v1.2) decodes cleanly:
    //   - lastPaidDate added in v1.1 → Optional, default nil
    //   - isShared    added in v1.2 → default false
    // Encoding is the synthesized path; only decode is custom.

    private enum CodingKeys: String, CodingKey {
        case id, name, amount, dueDate, category, recurrence, type
        case autoPay, notes, status, lastPaidDate, createdAt, updatedAt
        case isShared, deletedAt, ownerUserID
        // v1.4 — 15/3 Paydown Plan
        case isUsing153Plan, firstPaydownDate, secondPaydownDate
        case firstPaydownAmount, secondPaydownAmount
        // v1.5 — Payment Link
        case paymentURL
        // Payoff Tracking
        case isPayoffTrackingEnabled, payoffOriginalBalance
        case payoffRemainingBalance, payoffPaymentAmount
        case payoffInterestRate, payoffGoalDate, payoffCategory
        case payoffHistory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id           = try c.decode(UUID.self,           forKey: .id)
        self.name         = try c.decode(String.self,         forKey: .name)
        self.amount       = try c.decode(Decimal.self,        forKey: .amount)
        self.dueDate      = try c.decode(Date.self,           forKey: .dueDate)
        self.category     = try c.decode(BillCategory.self,   forKey: .category)
        self.recurrence   = try c.decode(RecurrenceType.self, forKey: .recurrence)
        self.type         = try c.decode(BillType.self,       forKey: .type)
        self.autoPay      = try c.decode(Bool.self,           forKey: .autoPay)
        self.notes        = try c.decode(String.self,         forKey: .notes)
        self.status       = try c.decode(PaymentStatus.self,  forKey: .status)
        self.lastPaidDate = try c.decodeIfPresent(Date.self,  forKey: .lastPaidDate)
        self.createdAt    = try c.decode(Date.self,           forKey: .createdAt)
        self.updatedAt    = try c.decode(Date.self,           forKey: .updatedAt)
        self.isShared     = try c.decodeIfPresent(Bool.self,  forKey: .isShared) ?? false
        self.deletedAt    = try c.decodeIfPresent(Date.self,  forKey: .deletedAt)
        self.ownerUserID  = try c.decodeIfPresent(UUID.self,  forKey: .ownerUserID)
        // 15/3 Paydown Plan — all five default to off/nil for older JSON.
        self.isUsing153Plan      = try c.decodeIfPresent(Bool.self,    forKey: .isUsing153Plan) ?? false
        self.firstPaydownDate    = try c.decodeIfPresent(Date.self,    forKey: .firstPaydownDate)
        self.secondPaydownDate   = try c.decodeIfPresent(Date.self,    forKey: .secondPaydownDate)
        self.firstPaydownAmount  = try c.decodeIfPresent(Decimal.self, forKey: .firstPaydownAmount)
        self.secondPaydownAmount = try c.decodeIfPresent(Decimal.self, forKey: .secondPaydownAmount)
        // v1.5 — Payment Link. Decode as Optional so older JSON / DB rows
        // without the column still parse cleanly (paymentURL stays nil).
        let rawPaymentURL = try c.decodeIfPresent(String.self, forKey: .paymentURL)
        self.paymentURL = rawPaymentURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        // Payoff Tracking — default to off/nil/empty for older JSON.
        self.isPayoffTrackingEnabled = try c.decodeIfPresent(Bool.self, forKey: .isPayoffTrackingEnabled) ?? false
        self.payoffOriginalBalance   = try c.decodeIfPresent(Decimal.self, forKey: .payoffOriginalBalance)
        self.payoffRemainingBalance  = try c.decodeIfPresent(Decimal.self, forKey: .payoffRemainingBalance)
        self.payoffPaymentAmount     = try c.decodeIfPresent(Decimal.self, forKey: .payoffPaymentAmount)
        self.payoffInterestRate      = try c.decodeIfPresent(Decimal.self, forKey: .payoffInterestRate)
        self.payoffGoalDate          = try c.decodeIfPresent(Date.self, forKey: .payoffGoalDate)
        self.payoffCategory          = try c.decodeIfPresent(PayoffCategory.self, forKey: .payoffCategory)
        self.payoffHistory           = try c.decodeIfPresent([PayoffPaymentRecord].self, forKey: .payoffHistory) ?? []
    }

    // MARK: - Derived

    /// Treat auto-pay as covered for the current due cycle, otherwise promote
    /// an unpaid bill whose due date has passed to overdue.
    var effectiveStatus: PaymentStatus {
        if isPaid { return .paid }
        let cal = Calendar.current
        return cal.startOfDay(for: dueDate) < cal.startOfDay(for: Date())
            ? .overdue : .unpaid
    }

    var isAutoPaid: Bool { autoPay }
    var isPaid: Bool     { status == .paid || isAutoPaid }
    var isOverdue: Bool  { effectiveStatus == .overdue }
    var isDueToday: Bool { Calendar.current.isDateInToday(dueDate) }

    var isDueThisWeek: Bool {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return false }
        return interval.contains(dueDate) || isDueToday
    }

    var isDueThisMonth: Bool {
        let cal = Calendar.current
        let now = Date()
        return cal.component(.month, from: dueDate) == cal.component(.month, from: now)
            && cal.component(.year,  from: dueDate) == cal.component(.year,  from: now)
    }

    /// Days until due (negative = overdue by N days). Uses start-of-day
    /// comparison so "today" = 0 and "tomorrow" = 1.
    var daysUntilDue: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due   = cal.startOfDay(for: dueDate)
        return cal.dateComponents([.day], from: today, to: due).day ?? 0
    }

    /// Days overdue. Zero if not overdue.
    var daysOverdue: Int {
        max(0, -daysUntilDue)
    }

    /// Was the most recent payment within the last 7 days?
    var paidRecently: Bool {
        guard let last = lastPaidDate else { return false }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: Date())).day ?? 0
        return isPaid && days >= 0 && days <= 7
    }

    var formattedAmount: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    var payoffOriginalBalanceValue: Decimal {
        payoffOriginalBalance ?? payoffRemainingBalance ?? Decimal(0)
    }

    var payoffRemainingBalanceValue: Decimal {
        payoffRemainingBalance ?? payoffOriginalBalanceValue
    }

    var payoffEffectivePaymentAmount: Decimal {
        let payment = payoffPaymentAmount ?? amount
        return payment > 0 ? payment : amount
    }

    var payoffPaidDown: Decimal {
        let paid = payoffOriginalBalanceValue - payoffRemainingBalanceValue
        return paid > 0 ? paid : Decimal(0)
    }

    var payoffProgress: Double {
        let original = (payoffOriginalBalanceValue as NSDecimalNumber).doubleValue
        guard original > 0 else { return 0 }
        let paid = (payoffPaidDown as NSDecimalNumber).doubleValue
        return min(max(paid / original, 0), 1)
    }

    var estimatedPayoffPaymentCount: Int? {
        let remaining = (payoffRemainingBalanceValue as NSDecimalNumber).doubleValue
        let payment = (payoffEffectivePaymentAmount as NSDecimalNumber).doubleValue
        guard remaining > 0, payment > 0 else { return nil }
        return Int(ceil(remaining / payment))
    }

    func payoffNetAmount(for cycleDueDate: Date? = nil, calendar: Calendar = .current) -> Decimal {
        let target = calendar.startOfDay(for: cycleDueDate ?? dueDate)
        return payoffHistory.reduce(Decimal(0)) { total, record in
            guard calendar.isDate(record.cycleDueDate, inSameDayAs: target) else { return total }
            switch record.kind {
            case .manual, .autoPay:
                return total + record.amount
            case .reversal:
                return total - record.amount
            }
        }
    }

    func hasPayoffPaymentApplied(for cycleDueDate: Date? = nil, calendar: Calendar = .current) -> Bool {
        payoffNetAmount(for: cycleDueDate, calendar: calendar) > 0
    }

    @discardableResult
    mutating func applyPayoffPaymentIfNeeded(
        kind: PayoffPaymentKind,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isPayoffTrackingEnabled else { return false }

        let startingRemaining = payoffRemainingBalance ?? payoffOriginalBalance
        guard let currentRemaining = startingRemaining, currentRemaining > 0 else { return false }
        guard payoffEffectivePaymentAmount > 0 else { return false }
        guard !hasPayoffPaymentApplied(for: dueDate, calendar: calendar) else { return false }

        let deduction = min(payoffEffectivePaymentAmount, currentRemaining)
        let nextRemaining = max(Decimal(0), currentRemaining - deduction)
        payoffRemainingBalance = nextRemaining
        payoffHistory.append(
            PayoffPaymentRecord(
                date: now,
                cycleDueDate: calendar.startOfDay(for: dueDate),
                amount: deduction,
                remainingBalanceAfter: nextRemaining,
                kind: kind
            )
        )
        return true
    }

    @discardableResult
    mutating func reversePayoffPaymentForCurrentCycle(
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isPayoffTrackingEnabled else { return false }
        let appliedAmount = payoffNetAmount(for: dueDate, calendar: calendar)
        guard appliedAmount > 0 else { return false }

        let currentRemaining = payoffRemainingBalance ?? Decimal(0)
        let uncappedRemaining = currentRemaining + appliedAmount
        let restoredRemaining: Decimal
        if let original = payoffOriginalBalance, original > 0 {
            restoredRemaining = min(original, uncappedRemaining)
        } else {
            restoredRemaining = uncappedRemaining
        }

        payoffRemainingBalance = restoredRemaining
        payoffHistory.append(
            PayoffPaymentRecord(
                date: now,
                cycleDueDate: calendar.startOfDay(for: dueDate),
                amount: appliedAmount,
                remainingBalanceAfter: restoredRemaining,
                kind: .reversal
            )
        )
        return true
    }

    var isRecurring: Bool { recurrence.isRecurring }

    /// Priority score — higher = pay first.
    ///   +1000 per overdue day (capped)
    ///   + amount magnitude
    ///   + 300 if due in ≤3 days and unpaid
    ///   - 500 if autopay is on (less manual urgency)
    ///   - 800 if already paid
    var priorityScore: Double {
        let amt = (amount as NSDecimalNumber).doubleValue
        var score: Double = 0
        if isOverdue {
            score += Double(min(daysOverdue, 30)) * 40
            score += amt * 1.1
        } else if !isPaid && daysUntilDue <= 3 {
            score += 300
            score += amt
        } else if !isPaid {
            score += max(0, 200 - Double(daysUntilDue) * 5)
            score += amt * 0.4
        }
        if autoPay { score -= 500 }
        if isPaid  { score -= 800 }
        return score
    }
}

// MARK: - Insights

/// Lightweight, user-facing tags that surface on bill rows and the dashboard.
enum BillInsight: String, CaseIterable, Identifiable, Hashable {
    case overdue
    case dueSoon
    case highestAmount
    case autoPay
    case paidRecently
    case recurring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue:       return "Overdue"
        case .dueSoon:       return "Due soon"
        case .highestAmount: return "Highest amount"
        case .autoPay:       return "Autopay enabled"
        case .paidRecently:  return "Paid recently"
        case .recurring:     return "Recurring"
        }
    }

    var systemImage: String {
        switch self {
        case .overdue:       return "exclamationmark.triangle.fill"
        case .dueSoon:       return "clock.badge.exclamationmark.fill"
        case .highestAmount: return "chart.bar.fill"
        case .autoPay:       return "arrow.triangle.2.circlepath.circle.fill"
        case .paidRecently:  return "checkmark.seal.fill"
        case .recurring:     return "repeat.circle.fill"
        }
    }
}

extension Bill {
    /// Compute the active insight tags for this bill, optionally in the
    /// context of the full list so we can flag the "highest amount" one.
    func insights(maxAmountInScope: Decimal? = nil) -> [BillInsight] {
        var out: [BillInsight] = []
        if isOverdue { out.append(.overdue) }
        else if !isPaid && daysUntilDue >= 0 && daysUntilDue <= 3 { out.append(.dueSoon) }
        if let maxAmt = maxAmountInScope, amount >= maxAmt && !isPaid {
            out.append(.highestAmount)
        }
        if autoPay { out.append(.autoPay) }
        if paidRecently { out.append(.paidRecently) }
        if isRecurring && !out.contains(.autoPay) { out.append(.recurring) }
        return out
    }
}
