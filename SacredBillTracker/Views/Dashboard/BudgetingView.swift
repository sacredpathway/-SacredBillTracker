//
//  BudgetingView.swift
//  SacredBillTracker
//
//  Premium monthly budgeting. Plan spending per category, compare budget
//  vs. actual, track goals, and get smart insights — all classification
//  aware (Personal / Business / All never mix). Budgets/goals persist in
//  Supabase (RLS owner-scoped); actuals come from the budget_* RPCs
//  (Plaid transactions + paid bills).
//
//  Self-contained: models, store, notifications, and all screens live here.
//

import SwiftUI
import UserNotifications

#if canImport(Supabase)
import Supabase
#endif

// MARK: - Scope

enum BudgetScope: String, CaseIterable, Identifiable {
    case all, personal, business
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .personal: return "Personal"
        case .business: return "Business"
        }
    }
    var editableScope: BudgetScope { self == .all ? .personal : self }
}

// MARK: - Category keys

enum BudgetCategoryKey: String, CaseIterable, Identifiable {
    case housing, utilities, food, transportation, insurance
    case debt, subscriptions
    case businessExpenses = "business_expenses"
    case savings, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .housing: return "Housing"
        case .utilities: return "Utilities"
        case .food: return "Food"
        case .transportation: return "Transportation"
        case .insurance: return "Insurance"
        case .debt: return "Debt"
        case .subscriptions: return "Subscriptions"
        case .businessExpenses: return "Business Expenses"
        case .savings: return "Savings"
        case .other: return "Other"
        }
    }
    /// Short label for insights ("dining" etc. kept simple).
    var noun: String { title.lowercased() }
    var systemImage: String {
        switch self {
        case .housing: return "house.fill"
        case .utilities: return "bolt.fill"
        case .food: return "cart.fill"
        case .transportation: return "car.fill"
        case .insurance: return "shield.fill"
        case .debt: return "creditcard.fill"
        case .subscriptions: return "repeat.circle.fill"
        case .businessExpenses: return "briefcase.fill"
        case .savings: return "banknote.fill"
        case .other: return "tag.fill"
        }
    }
    static func from(_ raw: String) -> BudgetCategoryKey { BudgetCategoryKey(rawValue: raw) ?? .other }
}

// MARK: - Decode helpers

private func decodeNumeric<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double {
    if let d = try? c.decode(Double.self, forKey: key) { return d }
    if let s = try? c.decode(String.self, forKey: key), let d = Double(s) { return d }
    return 0
}

// MARK: - Rows

struct BudgetRow: Decodable, Identifiable {
    let id: String; let scope: String; let category: String; let amount: Double
    enum K: String, CodingKey { case id, scope, category, amount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        scope = try c.decode(String.self, forKey: .scope)
        category = try c.decode(String.self, forKey: .category)
        amount = decodeNumeric(c, .amount)
    }
}

struct BudgetOverviewRow: Decodable, Identifiable {
    let category: String
    let budgeted: Double
    let plaidSpent: Double
    let billsSpent: Double
    let billsDue: Double
    var id: String { category }
    var key: BudgetCategoryKey { .from(category) }
    var actual: Double { plaidSpent + billsSpent }
    var remaining: Double { budgeted - actual }
    var fraction: Double { budgeted > 0 ? min(actual / budgeted, 1) : (actual > 0 ? 1 : 0) }
    var rawFraction: Double { budgeted > 0 ? actual / budgeted : 0 }
    enum K: String, CodingKey { case category, budgeted, plaid_spent, bills_spent, bills_due }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        category = try c.decode(String.self, forKey: .category)
        budgeted = decodeNumeric(c, .budgeted)
        plaidSpent = decodeNumeric(c, .plaid_spent)
        billsSpent = decodeNumeric(c, .bills_spent)
        billsDue = decodeNumeric(c, .bills_due)
    }
}

struct BudgetSuggestionRow: Decodable, Identifiable {
    let category: String; let basis: Double; let suggested: Double
    var id: String { category }
    var key: BudgetCategoryKey { .from(category) }
    enum K: String, CodingKey { case category, basis, suggested }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        category = try c.decode(String.self, forKey: .category)
        basis = decodeNumeric(c, .basis)
        suggested = decodeNumeric(c, .suggested)
    }
    init(category: String, basis: Double, suggested: Double) {
        self.category = category; self.basis = basis; self.suggested = suggested
    }
}

// MARK: - Goals

enum BudgetGoalKind: String, CaseIterable, Identifiable {
    case emergencyFund = "emergency_fund"
    case vacation
    case house
    case debtPayoff = "debt_payoff"
    case businessExpansion = "business_expansion"
    case custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .emergencyFund: return "Emergency Fund"
        case .vacation: return "Vacation"
        case .house: return "House Down Payment"
        case .debtPayoff: return "Debt Payoff"
        case .businessExpansion: return "Business Expansion"
        case .custom: return "Custom Goal"
        }
    }
    var systemImage: String {
        switch self {
        case .emergencyFund: return "umbrella.fill"
        case .vacation: return "airplane"
        case .house: return "house.lodge.fill"
        case .debtPayoff: return "creditcard.fill"
        case .businessExpansion: return "chart.line.uptrend.xyaxis"
        case .custom: return "target"
        }
    }
    static func from(_ raw: String) -> BudgetGoalKind { BudgetGoalKind(rawValue: raw) ?? .custom }
}

struct BudgetGoal: Decodable, Identifiable {
    let id: String
    let title: String
    let kind: String
    let scope: String?
    let linkedCategory: String?
    let targetAmount: Double
    let currentAmount: Double
    let targetDate: String?

    var goalKind: BudgetGoalKind { .from(kind) }
    var progress: Double { targetAmount > 0 ? min(currentAmount / targetAmount, 1) : 0 }
    var isComplete: Bool { currentAmount >= targetAmount && targetAmount > 0 }

    enum K: String, CodingKey {
        case id, title, kind, scope, linked_category, target_amount, current_amount, target_date
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decode(String.self, forKey: .kind)
        scope = try c.decodeIfPresent(String.self, forKey: .scope)
        linkedCategory = try c.decodeIfPresent(String.self, forKey: .linked_category)
        targetAmount = decodeNumeric(c, .target_amount)
        currentAmount = decodeNumeric(c, .current_amount)
        targetDate = try c.decodeIfPresent(String.self, forKey: .target_date)
    }
}

// MARK: - Health / level / insights

enum BudgetLevel {
    case ok, warn, over
    static func from(fraction: Double, budgeted: Double) -> BudgetLevel {
        guard budgeted > 0 else { return .ok }
        if fraction > 1.0 { return .over }
        if fraction >= 0.8 { return .warn }
        return .ok
    }
    var tint: Color {
        switch self {
        case .ok: return .appAccent
        case .warn: return .appAmber
        case .over: return .red
        }
    }
    var statusText: String {
        switch self {
        case .ok: return "Under Budget"
        case .warn: return "Almost There"
        case .over: return "Over Budget"
        }
    }
}

enum HealthState {
    case excellent, onTrack, warning, over
    var title: String {
        switch self {
        case .excellent: return "Excellent"
        case .onTrack: return "On Track"
        case .warning: return "Warning"
        case .over: return "Over Budget"
        }
    }
    var tint: Color {
        switch self {
        case .excellent: return .appAccent
        case .onTrack: return .appAccent
        case .warning: return .appAmber
        case .over: return .red
        }
    }
    var systemImage: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .onTrack: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .over: return "xmark.octagon.fill"
        }
    }
}

struct BudgetInsight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let tint: Color
}

struct BudgetAlert: Identifiable {
    let id = UUID()
    let category: String
    let level: BudgetLevel
    let message: String
}

// MARK: - Wellness / forecast (v3 — premium)

/// Financial-wellness / budget-health tier (Phase 12 ranges).
enum WellnessTier {
    case excellent, strong, moderate, atRisk
    static func from(score: Int) -> WellnessTier {
        switch score {
        case 90...: return .excellent
        case 75..<90: return .strong
        case 60..<75: return .moderate
        default: return .atRisk
        }
    }
    var title: String {
        switch self {
        case .excellent: return "Excellent"
        case .strong: return "Strong"
        case .moderate: return "Moderate"
        case .atRisk: return "At Risk"
        }
    }
    var tint: Color {
        switch self {
        case .excellent, .strong: return .appAccent
        case .moderate: return .appAmber
        case .atRisk: return .red
        }
    }
    var systemImage: String {
        switch self {
        case .excellent: return "checkmark.seal.fill"
        case .strong: return "checkmark.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .atRisk: return "xmark.octagon.fill"
        }
    }
}

/// Projected end-of-month status for one category (Phase 14).
struct CategoryForecast: Identifiable {
    let key: BudgetCategoryKey
    let projected: Double
    let budgeted: Double
    let confidence: Double   // 0–1
    var id: String { key.rawValue }
    var over: Double { projected - budgeted }
    var willExceed: Bool { budgeted > 0 && projected > budgeted }
}

/// A plain-English "smart action" to raise the wellness score (Phase 15).
struct SmartAction: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

/// One row from budget_cashflow.
struct CashflowDTO: Decodable {
    let upcomingUnpaid: Double
    let overdueUnpaid: Double
    let billsDueCount: Int
    let billsPaidCount: Int
    enum K: String, CodingKey { case upcoming_unpaid, overdue_unpaid, bills_due_count, bills_paid_count }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        upcomingUnpaid = (try? c.decode(Double.self, forKey: .upcoming_unpaid)) ?? 0
        overdueUnpaid = (try? c.decode(Double.self, forKey: .overdue_unpaid)) ?? 0
        billsDueCount = (try? c.decode(Int.self, forKey: .bills_due_count)) ?? 0
        billsPaidCount = (try? c.decode(Int.self, forKey: .bills_paid_count)) ?? 0
    }
}

// MARK: - Store

@MainActor
final class BudgetStore: ObservableObject {

    @Published var scope: BudgetScope = .all { didSet { Task { await load() } } }
    @Published private(set) var overview: [BudgetOverviewRow] = []
    @Published private(set) var prevOverview: [BudgetOverviewRow] = []
    @Published private(set) var budgets: [BudgetRow] = []
    @Published private(set) var goals: [BudgetGoal] = []
    @Published private(set) var income: Double = 0
    @Published private(set) var prevIncome: Double = 0
    // Cash-flow inputs (Phase 11).
    @Published private(set) var upcomingUnpaid: Double = 0
    @Published private(set) var overdueUnpaid: Double = 0
    @Published private(set) var billsDueCount: Int = 0
    @Published private(set) var billsPaidCount: Int = 0
    @Published private(set) var isLoading = false
    @Published var errorText: String?

    private let df: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Period

    func currentPeriod(now: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
        return (start, end)
    }
    func previousPeriod(now: Date = Date()) -> (start: Date, end: Date) {
        let cal = Calendar.current
        let thisStart = currentPeriod(now: now).start
        let start = cal.date(byAdding: .month, value: -1, to: thisStart) ?? thisStart
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return (start, end)
    }
    var periodLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: currentPeriod().start)
    }

    // MARK: Totals

    var totalBudget: Double { overview.reduce(0) { $0 + $1.budgeted } }
    var totalSpent: Double { overview.filter { $0.budgeted > 0 }.reduce(0) { $0 + $1.actual } }
    var totalSpentAll: Double { overview.reduce(0) { $0 + $1.actual } }
    var prevSpentAll: Double { prevOverview.reduce(0) { $0 + $1.actual } }
    var totalRemaining: Double { totalBudget - totalSpent }
    var totalFraction: Double { totalBudget > 0 ? totalSpent / totalBudget : 0 }

    /// Savings rate for the period: (income − all spending) / income.
    var savingsRate: Double {
        guard income > 0 else { return 0 }
        return max(0, (income - totalSpentAll) / income)
    }

    /// Spending trend vs last month (all categories). nil if no prior data.
    var spendTrendPct: Double? {
        guard prevSpentAll > 0 else { return nil }
        return (totalSpentAll - prevSpentAll) / prevSpentAll
    }

    // MARK: Forecast (Phase 11/14)

    private var monthDay: Int { max(1, Calendar.current.component(.day, from: Date())) }
    private var monthDays: Int { Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30 }
    var monthProgress: Double { min(1, Double(monthDay) / Double(monthDays)) }
    var daysLeftInMonth: Int { max(0, monthDays - monthDay) }

    var projectedSpendAll: Double { totalSpentAll / Double(monthDay) * Double(monthDays) }
    var projectedSavings: Double { income - projectedSpendAll }
    /// Cash expected to remain after the rest of the month's spend + unpaid bills.
    var projectedRemainingCash: Double { income - projectedSpendAll - upcomingUnpaid }
    private var dailyBurn: Double { totalSpent / Double(monthDay) }
    /// Days until the (budgeted) spend would exhaust the total budget. nil when no budget.
    var daysUntilDepletion: Int? {
        guard totalBudget > 0 else { return nil }
        let remaining = totalBudget - totalSpent
        if remaining <= 0 { return 0 }
        guard dailyBurn > 0 else { return nil }
        return min(Int((remaining / dailyBurn).rounded()), 365)
    }

    func categoryForecasts() -> [CategoryForecast] {
        overview.filter { $0.budgeted > 0 }.map { r in
            let projected = r.actual / Double(monthDay) * Double(monthDays)
            let conf = min(0.95, 0.35 + monthProgress * 0.5 + (r.actual > 0 ? 0.1 : 0))
            return CategoryForecast(key: r.key, projected: projected, budgeted: r.budgeted, confidence: conf)
        }
        .sorted { abs($0.over) > abs($1.over) }
    }

    // MARK: Wellness / Health Score 2.0 (Phase 12/15)

    var billConsistency: Double { billsDueCount > 0 ? Double(billsPaidCount) / Double(billsDueCount) : 1.0 }
    var debtActual: Double { overview.first(where: { $0.key == .debt })?.actual ?? 0 }
    var debtRatio: Double { debtActual / max(income, totalSpentAll, 1) }
    var avgGoalProgress: Double? { goals.isEmpty ? nil : goals.map { $0.progress }.reduce(0, +) / Double(goals.count) }

    private var factorAdherence: Double { totalBudget <= 0 ? 0.55 : min(max((1.25 - totalFraction) / 0.55, 0), 1) }
    private var factorSavings: Double { min(max(savingsRate / 0.2, 0), 1) }
    private var factorDebt: Double { min(max(1 - debtRatio / 0.4, 0), 1) }
    private var factorTrend: Double {
        guard let t = spendTrendPct else { return 0.6 }
        return min(max(1 - max(0, t) / 0.5, 0), 1)
    }
    private var factorBills: Double { billConsistency }
    private var factorGoals: Double { avgGoalProgress ?? 0.5 }

    /// 0–100, weighted by adherence, savings, debt, trend, bill consistency, goals.
    var wellnessScore: Int {
        let s = 0.25 * factorAdherence + 0.25 * factorSavings + 0.15 * factorDebt
              + 0.10 * factorTrend + 0.15 * factorBills + 0.10 * factorGoals
        return Int((s * 100).rounded())
    }
    /// Back-compat alias used by the header card.
    var healthScore: Int { wellnessScore }
    var wellnessTier: WellnessTier { WellnessTier.from(score: wellnessScore) }

    var wellnessFactors: [(name: String, score: Double)] {
        [("Budget adherence", factorAdherence), ("Savings rate", factorSavings),
         ("Debt level", factorDebt), ("Spending trend", factorTrend),
         ("Bill consistency", factorBills), ("Goal progress", factorGoals)]
    }

    private func listPhrase(_ items: [String]) -> String {
        let a = Array(items.prefix(3))
        if a.count <= 1 { return a.first ?? "" }
        if a.count == 2 { return "\(a[0]) and \(a[1])" }
        return "\(a[0]), \(a[1]), and \(a[2])"
    }

    var healthExplanation: String {
        let over = overview.filter { $0.budgeted > 0 && $0.actual > $0.budgeted }.map { $0.key.title }
        if !over.isEmpty {
            return "Your score is lower because " + listPhrase(over) + (over.count == 1 ? " is" : " are") + " above budget."
        }
        if income > 0 && savingsRate < 0.1 { return "Your score is held back by a low savings rate this month." }
        if debtRatio > 0.3 { return "Debt is a large share of your spending, which lowers your score." }
        if let t = spendTrendPct, t > 0.2 { return "Your spending is up \(Int((t*100).rounded()))% vs last month." }
        return "You're managing money well across budgets, savings, and bills."
    }

    func topActions() -> [SmartAction] {
        var out: [SmartAction] = []
        let over = overview.filter { $0.budgeted > 0 && $0.actual > $0.budgeted }
            .sorted { ($0.actual - $0.budgeted) > ($1.actual - $1.budgeted) }
        if let o = over.first {
            out.append(.init(icon: "scissors", text: "Trim \(o.key.title) — it's \(money(o.actual - o.budgeted)) over budget."))
        }
        if income > 0 && savingsRate < 0.2 {
            let gap = income * 0.2 - (income - totalSpentAll)
            if gap > 0 { out.append(.init(icon: "leaf.fill", text: "Save \(money(gap)) more to reach a 20% savings rate.")) }
        }
        if let subs = overview.first(where: { $0.key == .subscriptions }), subs.actual > 50 {
            out.append(.init(icon: "repeat.circle.fill", text: "Reducing subscriptions by \(money(subs.actual * 0.25))/month would raise your score."))
        }
        if overdueUnpaid > 0 {
            out.append(.init(icon: "calendar.badge.exclamationmark", text: "Pay \(money(overdueUnpaid)) in overdue bills to improve consistency."))
        }
        if let g = goals.first(where: { !$0.isComplete }) {
            out.append(.init(icon: "target", text: "Add to your \(g.title) goal — you're \(Int((g.progress*100).rounded()))% there."))
        }
        if out.isEmpty {
            out.append(.init(icon: "checkmark.seal.fill", text: "Set a budget for any unbudgeted category to go even further."))
        }
        return Array(out.prefix(3))
    }

    var visibleRows: [BudgetOverviewRow] {
        overview.filter { $0.budgeted > 0 || $0.actual > 0 }
            .sorted { $0.budgeted == $1.budgeted ? $0.actual > $1.actual : $0.budgeted > $1.budgeted }
    }

    func budget(for scope: BudgetScope, category: BudgetCategoryKey) -> BudgetRow? {
        budgets.first { $0.scope == scope.editableScope.rawValue && $0.category == category.rawValue }
    }

    // MARK: Insights (premium)

    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.locale = .current; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    func insights() -> [BudgetInsight] {
        var out: [BudgetInsight] = []
        let prevByCat = Dictionary(uniqueKeysWithValues: prevOverview.map { ($0.category, $0.actual) })

        // Biggest month-over-month moves.
        var deltas: [(key: BudgetCategoryKey, delta: Double, prev: Double, cur: Double)] = []
        for r in overview {
            let prev = prevByCat[r.category] ?? 0
            if prev == 0 && r.actual == 0 { continue }
            deltas.append((r.key, r.actual - prev, prev, r.actual))
        }
        if let up = deltas.filter({ $0.delta > 25 }).max(by: { $0.delta < $1.delta }) {
            out.append(.init(icon: "arrow.up.right",
                text: "Your \(up.key.noun) spending increased by \(money(up.delta)).", tint: .appAmber))
        }
        if let down = deltas.filter({ $0.delta < -25 && $0.prev > 0 }).min(by: { $0.delta < $1.delta }) {
            let pct = Int((abs(down.delta) / down.prev * 100).rounded())
            out.append(.init(icon: "arrow.down.right",
                text: "You spent \(pct)% less on \(down.key.noun) this month.", tint: .appAccent))
        }
        // Subscriptions share.
        if totalSpentAll > 0, let subs = overview.first(where: { $0.key == .subscriptions }), subs.actual > 0 {
            let pct = Int((subs.actual / totalSpentAll * 100).rounded())
            if pct >= 5 {
                out.append(.init(icon: "repeat.circle.fill",
                    text: "Subscriptions account for \(pct)% of your spending.", tint: .appAccent))
            }
        }
        // Business trend.
        if scope == .all || scope == .business,
           let bizPrev = prevByCat["business_expenses"], bizPrev > 0,
           let biz = overview.first(where: { $0.key == .businessExpenses }) {
            if biz.actual < bizPrev * 0.95 {
                out.append(.init(icon: "chart.line.downtrend.xyaxis",
                    text: "Business expenses are trending lower.", tint: .appAccent))
            } else if biz.actual > bizPrev * 1.1 {
                out.append(.init(icon: "chart.line.uptrend.xyaxis",
                    text: "Business expenses are trending higher.", tint: .appAmber))
            }
        }
        // On pace to save.
        let cal = Calendar.current
        let now = Date()
        let day = max(1, cal.component(.day, from: now))
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        if income > 0 {
            let projectedSpend = totalSpentAll / Double(day) * Double(days)
            let projectedSave = income - projectedSpend
            if projectedSave > 0 {
                out.append(.init(icon: "leaf.fill",
                    text: "You're on pace to save \(money(projectedSave)) this month.", tint: .appAccent))
            } else {
                out.append(.init(icon: "exclamationmark.triangle.fill",
                    text: "At this pace you'll overspend by \(money(-projectedSave)) this month.", tint: .red))
            }
        }
        return Array(out.prefix(5))
    }

    /// Premium "forecasting": projected end-of-month spend within budgeted cats.
    var projectedSpend: Double {
        let cal = Calendar.current; let now = Date()
        let day = max(1, cal.component(.day, from: now))
        let days = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        return totalSpent / Double(day) * Double(days)
    }

    // MARK: Alerts

    func pendingAlerts() -> [BudgetAlert] {
        var out: [BudgetAlert] = []
        for r in overview where r.budgeted > 0 {
            switch BudgetLevel.from(fraction: r.rawFraction, budgeted: r.budgeted) {
            case .over:
                out.append(.init(category: r.category, level: .over,
                    message: "\(r.key.title) is over budget by \(money(r.actual - r.budgeted))."))
            case .warn:
                out.append(.init(category: r.category, level: .warn,
                    message: "\(r.key.title) is at \(Int(r.rawFraction * 100))% of budget."))
            case .ok: break
            }
        }
        return out
    }

    // MARK: Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        #if canImport(Supabase)
        do {
            let cur = currentPeriod(); let prev = previousPeriod()
            struct OV: Encodable { let p_scope: String; let p_start: String; let p_end: String }
            struct IN: Encodable { let p_scope: String; let p_start: String; let p_end: String }
            let client = SupabaseConfig.client
            async let ov: [BudgetOverviewRow] = client.rpc("budget_overview",
                params: OV(p_scope: scope.rawValue, p_start: df.string(from: cur.start), p_end: df.string(from: cur.end))).execute().value
            async let pov: [BudgetOverviewRow] = client.rpc("budget_overview",
                params: OV(p_scope: scope.rawValue, p_start: df.string(from: prev.start), p_end: df.string(from: prev.end))).execute().value
            async let inc: Double = client.rpc("budget_income",
                params: IN(p_scope: scope.rawValue, p_start: df.string(from: cur.start), p_end: df.string(from: cur.end))).execute().value
            async let pinc: Double = client.rpc("budget_income",
                params: IN(p_scope: scope.rawValue, p_start: df.string(from: prev.start), p_end: df.string(from: prev.end))).execute().value
            async let bg: [BudgetRow] = client.from("budget_categories").select().execute().value
            async let gl: [BudgetGoal] = client.from("budget_goals").select().order("created_at", ascending: false).execute().value
            async let cf: [CashflowDTO] = client.rpc("budget_cashflow",
                params: OV(p_scope: scope.rawValue, p_start: df.string(from: cur.start), p_end: df.string(from: cur.end))).execute().value

            let (o, p, i, pi, b, g, c) = try await (ov, pov, inc, pinc, bg, gl, cf)
            overview = o; prevOverview = p; income = i; prevIncome = pi; budgets = b; goals = g
            if let cfRow = c.first {
                upcomingUnpaid = cfRow.upcomingUnpaid; overdueUnpaid = cfRow.overdueUnpaid
                billsDueCount = cfRow.billsDueCount; billsPaidCount = cfRow.billsPaidCount
            } else {
                upcomingUnpaid = 0; overdueUnpaid = 0; billsDueCount = 0; billsPaidCount = 0
            }
            errorText = nil
        } catch {
            errorText = "Couldn't load budgets: \(error.localizedDescription)"
        }
        #endif
    }

    // MARK: Budget mutations

    func setBudget(scope editScope: BudgetScope, category: BudgetCategoryKey, amount: Double) async {
        #if canImport(Supabase)
        do {
            let uid = try await SupabaseConfig.client.auth.session.user.id
            struct Up: Encodable { let owner_id: String; let scope: String; let category: String; let amount: Double }
            _ = try await SupabaseConfig.client.from("budget_categories")
                .upsert(Up(owner_id: uid.uuidString.lowercased(), scope: editScope.editableScope.rawValue,
                           category: category.rawValue, amount: amount), onConflict: "owner_id,scope,category")
                .execute()
            await load()
        } catch { errorText = "Couldn't save budget: \(error.localizedDescription)" }
        #endif
    }

    func deleteBudget(id: String) async {
        #if canImport(Supabase)
        do { _ = try await SupabaseConfig.client.from("budget_categories").delete().eq("id", value: id).execute(); await load() }
        catch { errorText = "Couldn't delete budget: \(error.localizedDescription)" }
        #endif
    }

    func loadSuggestions() async -> [BudgetSuggestionRow] {
        #if canImport(Supabase)
        do {
            let p = previousPeriod()
            struct Args: Encodable { let p_scope: String; let p_prev_start: String; let p_prev_end: String }
            let rows: [BudgetSuggestionRow] = try await SupabaseConfig.client.rpc("budget_suggestions",
                params: Args(p_scope: scope.editableScope.rawValue, p_prev_start: df.string(from: p.start), p_prev_end: df.string(from: p.end)))
                .execute().value
            return rows.filter { $0.suggested > 0 }.sorted { $0.suggested > $1.suggested }
        } catch { return [] }
        #else
        return []
        #endif
    }

    /// Phase 13 — recommended budgets from 90 days of history (monthly average).
    func autoRecommend() async -> [BudgetSuggestionRow] {
        #if canImport(Supabase)
        do {
            let cal = Calendar.current
            let end = Date()
            let start = cal.date(byAdding: .day, value: -90, to: end) ?? end
            struct OV: Encodable { let p_scope: String; let p_start: String; let p_end: String }
            let rows: [BudgetOverviewRow] = try await SupabaseConfig.client.rpc("budget_overview",
                params: OV(p_scope: scope.editableScope.rawValue, p_start: df.string(from: start), p_end: df.string(from: end)))
                .execute().value
            return rows.compactMap { r in
                let monthly = (r.plaidSpent + r.billsSpent) / 3.0
                guard monthly > 0 else { return nil }
                return BudgetSuggestionRow(category: r.category, basis: monthly, suggested: ceil(monthly / 10) * 10)
            }
            .sorted { $0.suggested > $1.suggested }
        } catch { return [] }
        #else
        return []
        #endif
    }

    // MARK: Goal mutations

    func saveGoal(id: String?, title: String, kind: BudgetGoalKind, scope: BudgetScope?,
                  linked: BudgetCategoryKey?, target: Double, current: Double, targetDate: Date?) async {
        #if canImport(Supabase)
        do {
            let uid = try await SupabaseConfig.client.auth.session.user.id
            struct Up: Encodable {
                let id: String; let owner_id: String; let title: String; let kind: String
                let scope: String?; let linked_category: String?
                let target_amount: Double; let current_amount: Double; let target_date: String?
            }
            let gid = id ?? UUID().uuidString.lowercased()
            let dateStr = targetDate.map { df.string(from: $0) }
            _ = try await SupabaseConfig.client.from("budget_goals")
                .upsert(Up(id: gid, owner_id: uid.uuidString.lowercased(), title: title, kind: kind.rawValue,
                           scope: scope?.editableScope.rawValue, linked_category: linked?.rawValue,
                           target_amount: target, current_amount: current, target_date: dateStr), onConflict: "id")
                .execute()
            await load()
        } catch { errorText = "Couldn't save goal: \(error.localizedDescription)" }
        #endif
    }

    func deleteGoal(id: String) async {
        #if canImport(Supabase)
        do { _ = try await SupabaseConfig.client.from("budget_goals").delete().eq("id", value: id).execute(); await load() }
        catch { errorText = "Couldn't delete goal: \(error.localizedDescription)" }
        #endif
    }

    // MARK: Notifications

    func syncNotifications() async {
        await BudgetNotifications.shared.refresh(scope: scope, periodLabel: periodLabel,
                                                 alerts: pendingAlerts(), goals: goals)
    }
}

// MARK: - Local notifications

/// Schedules real local notifications for budget thresholds, the monthly
/// reset, and goal milestones. Deduped per month so the user isn't spammed.
final class BudgetNotifications {
    static let shared = BudgetNotifications()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "sbt.budget."

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isEnabled() async -> Bool {
        let s = await center.notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    func refresh(scope: BudgetScope, periodLabel: String, alerts: [BudgetAlert], goals: [BudgetGoal]) async {
        guard await isEnabled() else { return }
        let monthKey = monthStamp()

        // Monthly reset reminder (repeating, 1st at 9am).
        var resetComps = DateComponents(); resetComps.day = 1; resetComps.hour = 9; resetComps.minute = 0
        schedule(id: "\(prefix)reset", title: "New month, fresh budget",
                 body: "Your budgets just reset. Take a minute to plan this month's spending.",
                 trigger: UNCalendarNotificationTrigger(dateMatching: resetComps, repeats: true))

        // Threshold alerts — fire once per (month, category, level).
        for a in alerts {
            let key = "\(prefix)\(monthKey).\(scope.rawValue).\(a.category).\(a.level == .over ? "over" : "warn")"
            if UserDefaults.standard.bool(forKey: key) { continue }
            UserDefaults.standard.set(true, forKey: key)
            schedule(id: key,
                     title: a.level == .over ? "Over budget" : "Heads up",
                     body: a.message,
                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 4, repeats: false))
        }

        // Goal milestones (25/50/75/100%).
        for g in goals {
            let milestone = [1.0, 0.75, 0.5, 0.25].first { g.progress >= $0 }
            guard let m = milestone else { continue }
            let key = "\(prefix)goal.\(g.id).\(Int(m * 100))"
            if UserDefaults.standard.bool(forKey: key) { continue }
            UserDefaults.standard.set(true, forKey: key)
            let pct = Int(m * 100)
            schedule(id: key, title: pct == 100 ? "Goal reached! 🎉" : "Goal milestone",
                     body: pct == 100 ? "You hit your \(g.title) goal." : "You're \(pct)% of the way to \(g.title).",
                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        }
    }

    private func schedule(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }

    private func monthStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyyMM"; return f.string(from: Date())
    }
}

// MARK: - Reusable bits

struct ProgressBar: View {
    let fraction: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(tint).frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 8)
    }
}

/// Circular progress ring with a centered label.
struct ProgressRing: View {
    let fraction: Double
    let tint: Color
    let lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.0001, min(1, fraction)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: fraction)
        }
    }
}

// MARK: - Dashboard

struct BudgetDashboardView: View {
    @StateObject private var store = BudgetStore()
    @EnvironmentObject private var subs: SubscriptionManager

    @State private var editing: BudgetCategoryKey?
    @State private var showAdd = false
    @State private var showSuggestions = false
    @State private var editingGoal: BudgetGoal?
    @State private var addingGoal = false
    @State private var showPaywall = false
    @State private var showAutoBudget = false
    @State private var alertsOn = false

    /// Advanced budget features (cash-flow forecast, wellness score, smart
    /// insights, auto-budget) are Unlimited-tier. Essential/Business see
    /// upgrade teasers; legacy AutoTrack maps to Unlimited.
    private var budgetPro: Bool { subs.canForecasting }

    private let currency: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.locale = .current; return f
    }()
    private func money(_ v: Double, _ frac: Int = 0) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.locale = .current; f.maximumFractionDigits = frac
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scopePicker.padding(.horizontal)
                    healthCard.padding(.horizontal)
                    actionRow.padding(.horizontal)

                    if let err = store.errorText {
                        Text(err).font(.footnote).foregroundStyle(Color.appDangerText).padding(.horizontal)
                    }

                    forecastSection.padding(.horizontal)
                    wellnessSection.padding(.horizontal)
                    insightsSection.padding(.horizontal)
                    goalsSection.padding(.horizontal)

                    categoriesSection.padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Theme.Color.background)
            .navigationTitle("Budget")
            .task {
                // Make sure premium gating reflects the live entitlement so
                // paying (Pro or AutoTrack) users see the unlocked features
                // without first visiting Settings.
                await subs.refreshAutoTrackEntitlementFromBackend()
                await store.load()
                alertsOn = await BudgetNotifications.shared.isEnabled()
                if alertsOn { await store.syncNotifications() }
            }
            .refreshable { await store.load(); if alertsOn { await store.syncNotifications() } }
            .sheet(item: $editing) { key in EditBudgetSheet(store: store, defaultScope: store.scope, category: key) }
            .sheet(isPresented: $showAdd) { EditBudgetSheet(store: store, defaultScope: store.scope, category: nil) }
            .sheet(isPresented: $showSuggestions) { BudgetSuggestionsSheet(store: store) }
            .sheet(item: $editingGoal) { g in EditGoalSheet(store: store, goal: g) }
            .sheet(isPresented: $addingGoal) { EditGoalSheet(store: store, goal: nil) }
            .sheet(isPresented: $showAutoBudget) { AutoBudgetSheet(store: store) }
            .paywallSheet(isPresented: $showPaywall, reason: "Unlock Cash Flow Forecasting, your Financial Wellness Score, and Smart Insights with Pro.")
        }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: $store.scope) {
            ForEach(BudgetScope.allCases) { s in Text(s.title).tag(s) }
        }
        .pickerStyle(.segmented)
    }

    // MARK: Health card (premium summary)

    private var healthCard: some View {
        let st = store.wellnessTier
        return VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    ProgressRing(fraction: store.totalBudget > 0 ? store.totalFraction : store.savingsRate,
                                 tint: st.tint, lineWidth: 10)
                        .frame(width: 96, height: 96)
                    VStack(spacing: 0) {
                        Text("\(store.totalBudget > 0 ? Int((store.totalFraction*100).rounded()) : store.healthScore)")
                            .font(.title.bold().monospacedDigit())
                        Text(store.totalBudget > 0 ? "% used" : "score")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(st.title, systemImage: st.systemImage)
                        .font(.headline).foregroundStyle(st.tint)
                    Text(store.periodLabel).font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.medium")
                        Text("Health \(store.healthScore)/100").font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                    if let t = store.spendTrendPct {
                        HStack(spacing: 4) {
                            Image(systemName: t <= 0 ? "arrow.down.right" : "arrow.up.right")
                            Text("\(t <= 0 ? "" : "+")\(Int((t*100).rounded()))% vs last month")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(t <= 0 ? Color.appAccent : Color.appAmber)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                metric("Budget", store.totalBudget)
                Divider().frame(height: 32)
                metric("Spent", store.totalSpent, store.totalFraction > 1 ? .red : .primary)
                Divider().frame(height: 32)
                metric("Remaining", store.totalRemaining, store.totalRemaining < 0 ? .red : .appAccent)
                Divider().frame(height: 32)
                metric("Saved", store.savingsRate * 100, .appAccent, isPct: true)
            }

            Text(store.healthExplanation)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func metric(_ title: String, _ value: Double, _ tint: Color = .primary, isPct: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(isPct ? "\(Int(value.rounded()))%" : money(value))
                .font(.subheadline.bold().monospacedDigit()).foregroundStyle(tint)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { showAdd = true } label: {
                Label("Add Budget", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)

            Button { showSuggestions = true } label: {
                Label("Suggest", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(Color.appAccentText)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.appAccent.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: Cash Flow Forecast (Phase 11)

    @ViewBuilder private var forecastSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Cash Flow Forecast", systemImage: "chart.line.uptrend.xyaxis")
            if budgetPro {
                forecastContent
            } else {
                lockedPreview(subtitle: "Unlock your projected savings before the month ends.") { forecastContent }
            }
        }
    }

    private var forecastContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                forecastMetric("Proj. left", store.projectedRemainingCash, store.projectedRemainingCash < 0 ? .red : .appAccent)
                Divider().frame(height: 34)
                forecastMetric("Proj. savings", store.projectedSavings, store.projectedSavings < 0 ? .red : .appAccent)
                Divider().frame(height: 34)
                forecastMetric("Upcoming bills", store.upcomingUnpaid, .primary)
            }
            Text(forecastNarrative)
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            if let d = store.daysUntilDepletion, store.totalBudget > 0 {
                HStack(spacing: 6) {
                    Image(systemName: d <= 7 ? "exclamationmark.triangle.fill" : "calendar")
                    Text(d <= 0 ? "Your \(store.scope.title) budget is already spent." :
                         "Your \(store.scope.title) budget is projected to run out in \(d) day\(d == 1 ? "" : "s").")
                    Spacer(minLength: 0)
                }
                .font(.caption.weight(.medium)).foregroundStyle(d <= 7 ? Color.red : Color.secondary)
            }
            if store.overdueUnpaid > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.exclamationmark")
                    Text("\(money(store.overdueUnpaid)) in bills are past due.")
                    Spacer(minLength: 0)
                }.font(.caption.weight(.medium)).foregroundStyle(Color.appDangerText)
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var forecastNarrative: String {
        if store.income <= 0 && store.totalSpentAll <= 0 { return "Connect a bank or add income to see your forecast." }
        let rem = store.projectedRemainingCash
        return rem >= 0
            ? "Based on your current pace, you'll finish this month with about \(money(rem)) remaining."
            : "Based on your current pace, you're on track to overspend by about \(money(-rem)) this month."
    }

    private func forecastMetric(_ title: String, _ value: Double, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(money(value)).font(.subheadline.bold().monospacedDigit()).foregroundStyle(tint)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    // MARK: Financial Wellness (Phase 15)

    @ViewBuilder private var wellnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Financial Wellness", systemImage: "heart.text.square.fill")
            if budgetPro {
                wellnessContent
            } else {
                lockedPreview(subtitle: "See your wellness score and the top moves to improve it.") { wellnessContent }
            }
        }
    }

    private var wellnessContent: some View {
        let tier = store.wellnessTier
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                ZStack {
                    ProgressRing(fraction: Double(store.wellnessScore) / 100, tint: tier.tint, lineWidth: 9)
                        .frame(width: 78, height: 78)
                    VStack(spacing: 0) {
                        Text("\(store.wellnessScore)").font(.title2.bold().monospacedDigit())
                        Text("/100").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label(tier.title, systemImage: tier.systemImage).font(.headline).foregroundStyle(tier.tint)
                    Text("Net cash flow: \(money(store.income - store.totalSpentAll))")
                        .font(.caption).foregroundStyle((store.income - store.totalSpentAll) >= 0 ? Color.appAccent : .red)
                    Text("Savings rate: \(Int((store.savingsRate*100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text("Top actions to improve").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            ForEach(store.topActions()) { a in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: a.icon).foregroundStyle(Color.appAccentText).frame(width: 20)
                    Text(a.text).font(.caption)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Blurred premium preview with a strong CTA (Phase 17 funnel).
    @ViewBuilder private func lockedPreview<Content: View>(subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
                .blur(radius: 8).disabled(true).allowsHitTesting(false)
                .frame(maxHeight: 150, alignment: .top).clipped()
            VStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.title3).foregroundStyle(.white)
                Text(subtitle).font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                Text("Unlock with Pro").font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(LinearGradient(colors: [Color.appAccent, Color.appAmber], startPoint: .leading, endPoint: .trailing), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.28))
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { showPaywall = true }
    }

    // MARK: Insights (premium)

    @ViewBuilder private var insightsSection: some View {
        let items = store.insights()
        if budgetPro {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader("Smart Insights", systemImage: "sparkles")
                    ForEach(items) { i in
                        HStack(spacing: 12) {
                            Image(systemName: i.icon).foregroundStyle(i.tint).frame(width: 22)
                            Text(i.text).font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        } else {
            premiumTeaser(
                title: "Smart Insights",
                subtitle: "See what changed this month, what's trending, and your pace to save.",
                icon: "sparkles")
        }
    }

    // MARK: Goals (premium)

    @ViewBuilder private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("Goals", systemImage: "target")
                Spacer()
                if budgetPro {
                    Button { addingGoal = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(Color.appAccentText) }
                }
            }
            if !budgetPro {
                premiumTeaser(title: "Budget Goals",
                              subtitle: "Save toward an emergency fund, a vacation, or paying off debt — and track progress.",
                              icon: "target")
            } else if store.goals.isEmpty {
                Text("No goals yet. Tap + to set your first one.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(store.goals) { g in
                    Button { editingGoal = g } label: { goalCard(g) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func goalCard(_ g: BudgetGoal) -> some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(fraction: g.progress, tint: g.isComplete ? .appAccent : .appAmber, lineWidth: 6)
                    .frame(width: 50, height: 50)
                Image(systemName: g.goalKind.systemImage).font(.subheadline).foregroundStyle(Color.appAccentText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(g.title).font(.subheadline.weight(.semibold))
                Text("\(money(g.currentAmount)) of \(money(g.targetAmount))")
                    .font(.caption).foregroundStyle(.secondary)
                ProgressBar(fraction: g.progress, tint: g.isComplete ? .appAccent : .appAmber)
            }
            Spacer(minLength: 0)
            Text("\(Int((g.progress*100).rounded()))%")
                .font(.subheadline.bold()).foregroundStyle(g.isComplete ? Color.appAccent : .primary)
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: Categories

    @ViewBuilder private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Categories", systemImage: "square.grid.2x2.fill")
            if store.visibleRows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill").font(.largeTitle).foregroundStyle(Color.appAccentText)
                    Text("No budgets yet").font(.headline)
                    Text("Let us build a budget from your last 90 days of spending — review it before saving.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button {
                        if budgetPro { showAutoBudget = true } else { showPaywall = true }
                    } label: {
                        Label("Create Recommended Budget", systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.plain)
                    .background(LinearGradient(colors: [Color.appAccent, Color.appAmber], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 16)
            } else {
                ForEach(store.visibleRows) { row in
                    Button { editing = row.key } label: { categoryCard(row) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func categoryCard(_ row: BudgetOverviewRow) -> some View {
        let lvl = BudgetLevel.from(fraction: row.rawFraction, budgeted: row.budgeted)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lvl.tint.opacity(0.16)).frame(width: 40, height: 40)
                    Image(systemName: row.key.systemImage).foregroundStyle(lvl.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.key.title).font(.subheadline.weight(.semibold))
                    Text(row.budgeted > 0
                         ? "\(money(row.actual)) of \(money(row.budgeted))"
                         : "\(money(row.actual)) spent · no budget set")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if row.budgeted > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Int((row.rawFraction*100).rounded()))%")
                            .font(.subheadline.bold().monospacedDigit()).foregroundStyle(lvl.tint)
                        Text(lvl.statusText).font(.caption2).foregroundStyle(lvl.tint)
                    }
                } else {
                    Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
                }
            }
            if row.budgeted > 0 {
                ProgressBar(fraction: row.fraction, tint: lvl.tint)
                HStack {
                    Text(row.remaining >= 0 ? "\(money(row.remaining)) left" : "\(money(-row.remaining)) over")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.remaining >= 0 ? Color.appAccent : .red)
                    Spacer()
                }
                // Phase 14 — category forecast (premium).
                if budgetPro {
                    let projected = row.actual / max(store.monthProgress, 0.01)
                    let over = projected - row.budgeted
                    HStack(spacing: 6) {
                        Image(systemName: over > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill").font(.caption2)
                        Text(over > 0
                             ? "Projected to exceed budget by \(money(over))"
                             : "Projected to finish \(money(-over)) under budget")
                            .font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(over > 0 ? Color.red : Color.appAccent)
                }
            }
        }
        .padding(14)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(.primary)
    }

    private func premiumTeaser(title: String, subtitle: String, icon: String) -> some View {
        Button { showPaywall = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color.appAccent, Color.appAmber],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title).font(.subheadline.weight(.bold))
                        Text("PRO").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.appAmber, in: Capsule()).foregroundStyle(.black)
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.appAccent.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit budget sheet

struct EditBudgetSheet: View {
    @ObservedObject var store: BudgetStore
    @Environment(\.dismiss) private var dismiss
    let defaultScope: BudgetScope
    let category: BudgetCategoryKey?

    @State private var editScope: BudgetScope = .personal
    @State private var selectedCategory: BudgetCategoryKey = .housing
    @State private var amountText = ""
    @State private var saving = false

    private var isExisting: Bool { category != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scope") {
                    Picker("Scope", selection: $editScope) {
                        Text("Personal").tag(BudgetScope.personal)
                        Text("Business").tag(BudgetScope.business)
                    }.pickerStyle(.segmented)
                }
                Section("Category") {
                    if isExisting {
                        Label(selectedCategory.title, systemImage: selectedCategory.systemImage)
                    } else {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(BudgetCategoryKey.allCases) { k in
                                Label(k.title, systemImage: k.systemImage).tag(k)
                            }
                        }
                    }
                }
                Section("Monthly budget") {
                    HStack { Text("$"); TextField("0", text: $amountText).keyboardType(.decimalPad) }
                }
                if isExisting, store.budget(for: editScope, category: selectedCategory) != nil {
                    Section {
                        Button(role: .destructive) { Task { await deleteCurrent() } } label: {
                            Label("Remove budget", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isExisting ? selectedCategory.title : "Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(saving || Double(amountText) == nil)
                }
            }
            .onAppear {
                editScope = defaultScope.editableScope
                if let category { selectedCategory = category }
                if let existing = store.budget(for: editScope, category: selectedCategory) { amountText = trimmed(existing.amount) }
            }
            .onChange(of: editScope) { _, _ in syncAmount() }
            .onChange(of: selectedCategory) { _, _ in syncAmount() }
        }
    }

    private func syncAmount() {
        if let existing = store.budget(for: editScope, category: selectedCategory) { amountText = trimmed(existing.amount) }
    }
    private func trimmed(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    private func save() async {
        guard let amt = Double(amountText) else { return }
        saving = true; await store.setBudget(scope: editScope, category: selectedCategory, amount: amt); saving = false; dismiss()
    }
    private func deleteCurrent() async {
        guard let row = store.budget(for: editScope, category: selectedCategory) else { return }
        saving = true; await store.deleteBudget(id: row.id); saving = false; dismiss()
    }
}

// MARK: - Suggestions sheet

struct BudgetSuggestionsSheet: View {
    @ObservedObject var store: BudgetStore
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [BudgetSuggestionRow] = []
    @State private var loading = true
    @State private var applying = false
    private let currency: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.locale = .current; return f
    }()
    var body: some View {
        NavigationStack {
            Group {
                if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "wand.and.stars").font(.largeTitle).foregroundStyle(Color.appAccentText)
                        Text("Not enough history yet").font(.headline)
                        Text("Once you have a month of spending, we'll suggest budgets from your averages.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else {
                    List {
                        Section {
                            ForEach(rows) { r in
                                HStack(spacing: 12) {
                                    Image(systemName: r.key.systemImage).foregroundStyle(Color.appAccentText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.key.title).font(.subheadline.weight(.semibold))
                                        Text("You spent \(currency.string(from: NSNumber(value: r.basis)) ?? "$0") last month")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(currency.string(from: NSNumber(value: r.suggested)) ?? "$0")
                                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.appAccentText)
                                }
                            }
                        } header: { Text("Suggested \(store.scope.editableScope.title) budgets") }
                        footer: { Text("Based on last month + a small buffer. Applying overwrites these categories.") }
                    }
                }
            }
            .navigationTitle("Smart Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if !rows.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Apply All") { Task { await applyAll() } }.disabled(applying) }
                }
            }
            .task { rows = await store.loadSuggestions(); loading = false }
        }
    }
    private func applyAll() async {
        applying = true
        for r in rows { await store.setBudget(scope: store.scope.editableScope, category: r.key, amount: r.suggested) }
        applying = false; dismiss()
    }
}

// MARK: - Auto-budget sheet (Phase 13)

struct AutoBudgetSheet: View {
    @ObservedObject var store: BudgetStore
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [BudgetSuggestionRow] = []
    @State private var loading = true
    @State private var applying = false
    @State private var overwrite = false

    private let currency: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .currency; f.locale = .current; return f
    }()

    private func hasExisting(_ r: BudgetSuggestionRow) -> Bool {
        store.budget(for: store.scope, category: r.key) != nil
    }
    private var applyRows: [BudgetSuggestionRow] {
        overwrite ? rows : rows.filter { !hasExisting($0) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if rows.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "wand.and.stars").font(.largeTitle).foregroundStyle(Color.appAccentText)
                        Text("Not enough history yet").font(.headline)
                        Text("Once you have spending history, we'll build a budget from your 90-day averages.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding()
                } else {
                    List {
                        Section {
                            ForEach(rows) { r in
                                HStack(spacing: 12) {
                                    Image(systemName: r.key.systemImage).foregroundStyle(Color.appAccentText)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(r.key.title).font(.subheadline.weight(.semibold))
                                        Text("~\(currency.string(from: NSNumber(value: r.basis)) ?? "$0")/mo over 90 days")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if hasExisting(r) && !overwrite {
                                        Text("kept").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Text(currency.string(from: NSNumber(value: r.suggested)) ?? "$0")
                                        .font(.subheadline.weight(.bold)).foregroundStyle(Color.appAccentText)
                                }
                            }
                        } header: { Text("Recommended \(store.scope.editableScope.title) budget") }
                        footer: { Text("Built from your last 90 days. Existing budgets are kept unless you turn on Overwrite.") }
                        if rows.contains(where: hasExisting) {
                            Section { Toggle("Overwrite existing budgets", isOn: $overwrite) }
                        }
                    }
                }
            }
            .navigationTitle("Recommended Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !rows.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { Task { await apply() } }.disabled(applying || applyRows.isEmpty)
                    }
                }
            }
            .task { rows = await store.autoRecommend(); loading = false }
        }
    }

    private func apply() async {
        applying = true
        for r in applyRows { await store.setBudget(scope: store.scope.editableScope, category: r.key, amount: r.suggested) }
        applying = false; dismiss()
    }
}

// MARK: - Edit goal sheet

struct EditGoalSheet: View {
    @ObservedObject var store: BudgetStore
    @Environment(\.dismiss) private var dismiss
    let goal: BudgetGoal?

    @State private var title = ""
    @State private var kind: BudgetGoalKind = .emergencyFund
    @State private var scope: BudgetScope = .personal
    @State private var linked: BudgetCategoryKey? = nil
    @State private var targetText = ""
    @State private var currentText = ""
    @State private var hasDate = false
    @State private var targetDate = Date()
    @State private var saving = false

    private var isExisting: Bool { goal != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Type", selection: $kind) {
                        ForEach(BudgetGoalKind.allCases) { k in Label(k.title, systemImage: k.systemImage).tag(k) }
                    }
                    TextField("Name (e.g. Emergency Fund)", text: $title)
                }
                Section("Amounts") {
                    HStack { Text("Target $"); TextField("0", text: $targetText).keyboardType(.decimalPad) }
                    HStack { Text("Saved so far $"); TextField("0", text: $currentText).keyboardType(.decimalPad) }
                }
                Section("Link (optional)") {
                    Picker("Scope", selection: $scope) {
                        Text("Personal").tag(BudgetScope.personal); Text("Business").tag(BudgetScope.business)
                    }.pickerStyle(.segmented)
                    Picker("Linked category", selection: $linked) {
                        Text("None").tag(BudgetCategoryKey?.none)
                        ForEach(BudgetCategoryKey.allCases) { k in
                            Label(k.title, systemImage: k.systemImage).tag(BudgetCategoryKey?.some(k))
                        }
                    }
                    Toggle("Target date", isOn: $hasDate)
                    if hasDate { DatePicker("By", selection: $targetDate, displayedComponents: .date) }
                }
                if isExisting {
                    Section { Button(role: .destructive) { Task { await del() } } label: { Label("Delete goal", systemImage: "trash") } }
                }
            }
            .navigationTitle(isExisting ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty || (Double(targetText) ?? 0) <= 0)
                }
            }
            .onAppear {
                if let g = goal {
                    title = g.title; kind = g.goalKind
                    scope = (g.scope == "business") ? .business : .personal
                    linked = g.linkedCategory.map { BudgetCategoryKey.from($0) }
                    targetText = trimmed(g.targetAmount); currentText = trimmed(g.currentAmount)
                    if let ds = g.targetDate { hasDate = true; let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; targetDate = f.date(from: ds) ?? Date() }
                } else {
                    title = kind.title
                }
            }
            .onChange(of: kind) { _, k in if title.isEmpty || !isExisting { title = k.title } }
        }
    }

    private func trimmed(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
    private func save() async {
        saving = true
        await store.saveGoal(id: goal?.id, title: title.trimmingCharacters(in: .whitespaces), kind: kind,
                             scope: scope, linked: linked, target: Double(targetText) ?? 0,
                             current: Double(currentText) ?? 0, targetDate: hasDate ? targetDate : nil)
        saving = false; dismiss()
    }
    private func del() async {
        guard let g = goal else { return }
        saving = true; await store.deleteGoal(id: g.id); saving = false; dismiss()
    }
}

#Preview {
    BudgetDashboardView()
        .environmentObject(SubscriptionManager())
}
