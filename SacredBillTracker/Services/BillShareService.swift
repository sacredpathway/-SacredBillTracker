//
//  BillShareService.swift
//  SacredBillTracker
//
//  Builds a plain-text, share-sheet-ready summary of a set of bills.
//  Produces the v1.6 spec format:
//
//      Sacred Bill Tracker Summary
//      Generated <date>
//
//      Total Bills: 8
//      Monthly Total: $1,842.50
//      Paid: $900.00
//      Pending: $742.50
//      Overdue: $200.00
//
//      Upcoming Bills:
//      • Rent — $1,200.00 — Due Jun 1 — Pending
//      • Phone — $95.00 — Due Jun 3 — Paid
//      • Insurance — $210.00 — Due Jun 7 — Overdue
//
//      Shared from Sacred Bill Tracker.
//
//  Lightweight by design: no PDF rendering, no networking, no extra
//  dependencies — just string formatting on top of the existing `Bill`
//  model. Pairs with the Bills tab's "Share Summary" toolbar button
//  and the Settings → Data row, both via SwiftUI `ShareLink`.
//
//  PRIVACY: NEVER reads `Bill.notes`. The summary is built purely from
//  publicly-shareable fields (name, amount, due date, status).
//

import Foundation
import SwiftUI
import UIKit
import PDFKit

enum BillShareService {

    struct PDFMetrics: Equatable {
        let billCount: Int
        let totalDue: Decimal
        let totalPaid: Decimal
        let totalUnpaid: Decimal
        let dueNext7Days: Decimal
        let dueNext30Days: Decimal
        let overdueAmount: Decimal
        let overdueCount: Int
        let categoryTotals: [(name: String, amount: Decimal)]

        static func == (lhs: PDFMetrics, rhs: PDFMetrics) -> Bool {
            lhs.billCount == rhs.billCount && lhs.totalDue == rhs.totalDue &&
            lhs.totalPaid == rhs.totalPaid && lhs.totalUnpaid == rhs.totalUnpaid &&
            lhs.dueNext7Days == rhs.dueNext7Days && lhs.dueNext30Days == rhs.dueNext30Days &&
            lhs.overdueAmount == rhs.overdueAmount && lhs.overdueCount == rhs.overdueCount &&
            lhs.categoryTotals.map { "\($0.name):\($0.amount)" } == rhs.categoryTotals.map { "\($0.name):\($0.amount)" }
        }
    }

    struct PDFReport: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
        let billCount: Int
        let totalAmount: Decimal
        let dateRange: String
        let note: String
    }

    enum PDFError: LocalizedError {
        case noBills
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .noBills: return "There are no bills available to include in this report."
            case .writeFailed: return "The PDF could not be created. Please try again."
            }
        }
    }

    static func metrics(
        for bills: [Bill],
        generatedAt: Date = Date(),
        calendar: Calendar = .current
    ) -> PDFMetrics {
        let live = bills.filter { $0.deletedAt == nil }
        let paid = live.filter(\.isPaid)
        let unpaid = live.filter { !$0.isPaid }
        let upcoming = BillTotalsCalculator.upcomingTotals(from: live, now: generatedAt, calendar: calendar)
        let today = calendar.startOfDay(for: generatedAt)
        let overdue = unpaid.filter { calendar.startOfDay(for: $0.dueDate) < today }
        let grouped = Dictionary(grouping: live, by: { $0.category.title })
        let categories = grouped.map { name, rows in
            (name: name, amount: rows.reduce(Decimal(0)) { $0 + $1.amount })
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return PDFMetrics(
            billCount: live.count,
            totalDue: live.reduce(Decimal(0)) { $0 + $1.amount },
            totalPaid: paid.reduce(Decimal(0)) { $0 + $1.amount },
            totalUnpaid: unpaid.reduce(Decimal(0)) { $0 + $1.amount },
            dueNext7Days: upcoming.dueNext7Days,
            dueNext30Days: upcoming.dueNext30Days,
            overdueAmount: overdue.reduce(Decimal(0)) { $0 + $1.amount },
            overdueCount: overdue.count,
            categoryTotals: categories
        )
    }

    static func maskedReference(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let visible = clean.filter { $0.isLetter || $0.isNumber }.suffix(4)
        return visible.isEmpty ? nil : "•••• \(visible)"
    }

    static func filename(for bills: [Bill], generatedAt: Date = Date()) -> String {
        let month = DateFormatter()
        month.locale = Locale(identifier: "en_US_POSIX")
        month.dateFormat = "MMMM-yyyy"
        let subject = bills.count == 1 ? bills[0].name : "Financial-Summary"
        let slug = subject.replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        return "Sacred-Bill-Tracker-\(slug.isEmpty ? "Report" : slug)-\(month.string(from: generatedAt)).pdf"
    }

    static func generatePDF(
        bills: [Bill],
        note: String = "",
        generatedAt: Date = Date(),
        calendar: Calendar = .current,
        outputDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> PDFReport {
        let live = bills.filter { $0.deletedAt == nil }
        guard !live.isEmpty else { throw PDFError.noBills }
        let sorted = live.sorted { priority(for: $0, at: generatedAt, calendar: calendar) < priority(for: $1, at: generatedAt, calendar: calendar) }
        let title = live.count == 1 ? "Bill Details Report" : "Financial Summary Report"
        let range = reportRange(for: live)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let reportMetrics = metrics(for: live, generatedAt: generatedAt, calendar: calendar)
        let url = outputDirectory.appendingPathComponent(filename(for: live, generatedAt: generatedAt))
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        let data = renderer.pdfData { context in
            PDFDrawer(context: context, title: title, period: range, generatedAt: generatedAt)
                .draw(bills: sorted, metrics: reportMetrics, note: cleanNote, calendar: calendar)
        }
        do { try data.write(to: url, options: .atomic) }
        catch {
            #if DEBUG
            print("Bill PDF generation failed: \(error)")
            #endif
            throw PDFError.writeFailed
        }
        return PDFReport(url: url, title: title, billCount: live.count,
                         totalAmount: reportMetrics.totalDue, dateRange: range, note: cleanNote)
    }

    private static func priority(for bill: Bill, at now: Date, calendar: Calendar) -> (Int, Date, String) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: bill.dueDate)).day ?? 0
        let rank = bill.isPaid ? 3 : (days < 0 ? 0 : (days == 0 ? 1 : 2))
        return (rank, bill.dueDate, bill.name)
    }

    private static func reportRange(for bills: [Bill]) -> String {
        guard let first = bills.map(\.dueDate).min(), let last = bills.map(\.dueDate).max() else { return "" }
        let f = DateFormatter(); f.dateStyle = .medium
        return Calendar.current.isDate(first, inSameDayAs: last) ? f.string(from: first) : "\(f.string(from: first)) - \(f.string(from: last))"
    }

    /// Plain-old-data container for the four income aggregates included
    /// in a shared summary. Keeps `makeSummary` decoupled from
    /// `IncomeStore` so the generator stays unit-testable without
    /// spinning up the store.
    struct IncomeAggregates: Equatable {
        var thisWeek:   Decimal
        var last30Days: Decimal
        var thisMonth:  Decimal
        var allTime:    Decimal

        static let zero = IncomeAggregates(
            thisWeek: 0, last30Days: 0, thisMonth: 0, allTime: 0
        )
    }

    // MARK: - Public API

    /// Build the full share-sheet body from a list of bills, with an
    /// optional Income Summary section prepended.
    ///
    /// Backward-compatible: callers that don't pass `income` (or pass
    /// `.zero`) get the v1.6 bill-only layout; the Income Summary
    /// section is omitted when every income aggregate is zero.
    ///
    /// Bills already filtered / scoped by the caller are passed in
    /// as-is; this service does not re-filter beyond skipping any
    /// soft-deleted rows defensively.
    static func makeSummary(
        bills: [Bill],
        income: IncomeAggregates = .zero,
        generatedAt: Date = Date(),
        calendar cal: Calendar = .current
    ) -> String {

        // Defensive: never include trashed bills in a shared summary.
        let live = bills.filter { $0.deletedAt == nil }

        // -------- Bill aggregates --------
        let count = live.count

        // "Monthly total" = full current-month bill obligation, matching
        // the in-app dashboard's Total Bills semantics.
        let monthlyTotal = BillTotalsCalculator.monthlyTotals(
            from: live,
            in: generatedAt,
            calendar: cal
        ).totalBills

        let paid    = live.filter { $0.effectiveStatus == .paid }
                          .reduce(Decimal(0)) { $0 + $1.amount }
        let pending = live.filter { $0.effectiveStatus == .unpaid }
                          .reduce(Decimal(0)) { $0 + $1.amount }
        let overdue = live.filter { $0.effectiveStatus == .overdue }
                          .reduce(Decimal(0)) { $0 + $1.amount }

        // -------- Compose --------
        var lines: [String] = []
        lines.append("Sacred Bill Tracker Summary")
        lines.append("Generated \(longDate(generatedAt))")
        lines.append("")

        // v1.7 — Income Summary section. Shown only when the user has
        // recorded any income, so older / fresh installs still get the
        // clean bills-only layout the prior spec described.
        if income != .zero {
            lines.append("Income Summary")
            lines.append("• This Week: \(currency(income.thisWeek))")
            lines.append("• Last 30 Days: \(currency(income.last30Days))")
            lines.append("• This Month: \(currency(income.thisMonth))")
            lines.append("• All Time: \(currency(income.allTime))")
            lines.append("")
        }

        // Bills Overview header keeps the document scannable when both
        // the income and bills sections are present.
        lines.append("Bills Overview")
        lines.append("• Total Bills: \(count)")
        lines.append("• Monthly Total: \(currency(monthlyTotal))")
        lines.append("• Paid: \(currency(paid))")
        lines.append("• Pending: \(currency(pending))")
        lines.append("• Overdue: \(currency(overdue))")
        lines.append("")

        // -------- Upcoming bills, grouped by due date --------
        //
        // Surfaces ALL non-trash bills, grouped by date, sorted by due
        // date ascending. Matches the "Upcoming Bills" example in spec.
        let upcoming = live.sorted { $0.dueDate < $1.dueDate }

        lines.append("Upcoming Bills")
        if upcoming.isEmpty {
            lines.append("• No upcoming bills.")
        } else {
            appendGroupedByDate(bills: upcoming, calendar: cal, into: &lines)
        }
        lines.append("")
        lines.append("Generated by Sacred Bill Tracker")

        return lines.joined(separator: "\n")
    }

    // MARK: - Grouping

    /// Appends bills under per-day headers, e.g.
    ///
    ///     May 24
    ///     • Rent — $850.00
    ///
    ///     May 28
    ///     • Internet — $75.00
    ///
    /// Bills are sorted by due date ascending; a blank line separates
    /// each day for legibility in the share sheet preview.
    private static func appendGroupedByDate(
        bills: [Bill],
        calendar cal: Calendar,
        into lines: inout [String]
    ) {
        var lastDay: Date? = nil
        for bill in bills {
            let day = cal.startOfDay(for: bill.dueDate)
            if lastDay == nil || !cal.isDate(lastDay!, inSameDayAs: day) {
                if lastDay != nil { lines.append("") } // gap between dates
                lines.append(shortDueDate(day)) // date header (e.g. "May 24")
            }
            lines.append(formatRow(bill))
            lastDay = day
        }
    }

    /// Single bill row matching the v1.7 spec example:
    /// `• Rent — $850.00`
    /// (Day header lives on the line above; status tag is dropped in
    /// the per-day list to keep each row short and readable.)
    static func formatRow(_ bill: Bill) -> String {
        "• \(bill.name) — \(currency(bill.amount))"
    }

    // MARK: - Formatting helpers

    /// Locale-aware currency, 2 fractional digits to match the spec
    /// examples (`$1,842.50`, `$95.00`).
    static func currency(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }

    /// Short due date used on each bill row, e.g. `Jun 1`.
    static func shortDueDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f.string(from: date)
    }

    /// Long header date, e.g. `May 22, 2026`.
    static func longDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateStyle = .long
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Title-cased status label — relies on `Bill.effectiveStatus`
    /// so unpaid + past-due bills are surfaced as "Overdue".
    static func statusLabel(_ status: PaymentStatus) -> String {
        switch status {
        case .paid:    return "Paid"
        case .unpaid:  return "Pending"
        case .overdue: return "Overdue"
        }
    }

}

private final class PDFDrawer {
    private let context: UIGraphicsPDFRendererContext
    private let title: String
    private let period: String
    private let generatedAt: Date
    private let margin: CGFloat = 42
    private let pageWidth: CGFloat = 612
    private let pageHeight: CGFloat = 792
    private var y: CGFloat = 0
    private var page = 0

    private let gold = UIColor(red: 0.54, green: 0.42, blue: 0.07, alpha: 1)
    private let green = UIColor(red: 0.13, green: 0.38, blue: 0.23, alpha: 1)
    private let ink = UIColor(red: 0.10, green: 0.12, blue: 0.14, alpha: 1)
    private let muted = UIColor(red: 0.35, green: 0.38, blue: 0.41, alpha: 1)
    private let rule = UIColor(red: 0.83, green: 0.80, blue: 0.69, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, title: String, period: String, generatedAt: Date) {
        self.context = context; self.title = title; self.period = period; self.generatedAt = generatedAt
    }

    func draw(bills: [Bill], metrics: BillShareService.PDFMetrics, note: String, calendar: Calendar) {
        newPage(continued: false)
        if !note.isEmpty {
            section("REPORT NOTE")
            paragraph(note, color: muted)
            y += 8
        }
        overview(metrics)
        section("BILL BREAKDOWN")
        billTable(bills, calendar: calendar)
        section("CATEGORY SUMMARY")
        for item in metrics.categoryTotals { keyValue(item.name, BillShareService.currency(item.amount)) }

        let overdue = bills.filter { status(for: $0, calendar: calendar).label == "OVERDUE" }
        let upcoming = bills.filter { let s = status(for: $0, calendar: calendar).label; return s == "DUE TODAY" || s == "DUE SOON" || s == "UNPAID" }
        let paid = bills.filter(\.isPaid)
        if !overdue.isEmpty { section("OVERDUE BILLS"); billTable(overdue, calendar: calendar) }
        if !upcoming.isEmpty { section("UPCOMING BILLS"); billTable(upcoming, calendar: calendar) }
        if !paid.isEmpty { section("PAID BILLS"); billTable(paid, calendar: calendar) }

        section("BILL DETAILS")
        for bill in bills { billDetail(bill, calendar: calendar) }
    }

    private func newPage(continued: Bool) {
        context.beginPage(); page += 1; y = margin
        text("SACRED BILL TRACKER", x: margin, width: 350, font: .boldSystemFont(ofSize: 12), color: green)
        text(title + (continued ? " - Continued" : ""), x: margin, y: y + 24, width: 430,
             font: .boldSystemFont(ofSize: 24), color: ink)
        y += 58
        text(period, x: margin, width: 350, font: .systemFont(ofSize: 10), color: muted)
        let f = DateFormatter(); f.dateStyle = .long
        text("Generated \(f.string(from: generatedAt))", x: margin, y: y + 15, width: 350,
             font: .systemFont(ofSize: 10), color: muted)
        y += 40
        rule.setStroke(); let path = UIBezierPath(); path.move(to: CGPoint(x: margin, y: y)); path.addLine(to: CGPoint(x: pageWidth - margin, y: y)); path.stroke()
        y += 16
        text("Sacred Bill Tracker • Financial information supplied by the user", x: margin, y: pageHeight - 29,
             width: 430, font: .systemFont(ofSize: 8), color: muted)
        text("Page \(page)", x: pageWidth - 95, y: pageHeight - 29, width: 53,
             font: .systemFont(ofSize: 8), color: muted, align: .right)
    }

    private func ensure(_ height: CGFloat) {
        if y + height > pageHeight - 48 { newPage(continued: true) }
    }

    private func section(_ value: String) {
        ensure(35); y += 10
        text(value, x: margin, width: pageWidth - margin * 2, font: .boldSystemFont(ofSize: 11), color: gold)
        y += 22
    }

    private func overview(_ m: BillShareService.PDFMetrics) {
        section("FINANCIAL OVERVIEW")
        let cards = [
            ("TOTAL DUE", m.totalDue), ("TOTAL PAID", m.totalPaid), ("TOTAL UNPAID", m.totalUnpaid),
            ("OVERDUE (\(m.overdueCount))", m.overdueAmount), ("DUE NEXT 7 DAYS", m.dueNext7Days),
            ("DUE NEXT 30 DAYS", m.dueNext30Days)
        ]
        for row in 0..<3 {
            ensure(55)
            for col in 0..<2 {
                let item = cards[row * 2 + col], x = margin + CGFloat(col) * 269
                UIColor(white: 0.97, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 258, height: 46), cornerRadius: 6).fill()
                text(item.0, x: x + 10, y: y + 7, width: 235, font: .boldSystemFont(ofSize: 8), color: muted)
                text(BillShareService.currency(item.1), x: x + 10, y: y + 22, width: 235, font: .boldSystemFont(ofSize: 13), color: ink)
            }
            y += 53
        }
    }

    private func billTable(_ bills: [Bill], calendar: Calendar) {
        tableHeader()
        for bill in bills {
            if y + 31 > pageHeight - 48 { newPage(continued: true); tableHeader() }
            let s = status(for: bill, calendar: calendar)
            text(bill.name, x: margin, y: y + 7, width: 135, font: .systemFont(ofSize: 9), color: ink)
            text(bill.category.title, x: 180, y: y + 7, width: 94, font: .systemFont(ofSize: 8), color: muted)
            text(BillShareService.currency(bill.amount), x: 279, y: y + 7, width: 74, font: .systemFont(ofSize: 9), color: ink, align: .right)
            text(shortDate(bill.dueDate), x: 363, y: y + 7, width: 65, font: .systemFont(ofSize: 8), color: ink)
            text(s.label, x: 433, y: y + 4, width: 75, font: .boldSystemFont(ofSize: 7), color: s.color)
            text(s.detail, x: 433, y: y + 14, width: 94, font: .systemFont(ofSize: 7), color: muted)
            y += 26
            UIColor(white: 0.9, alpha: 1).setStroke(); let p = UIBezierPath(); p.move(to: CGPoint(x: margin, y: y)); p.addLine(to: CGPoint(x: pageWidth-margin, y: y)); p.stroke()
        }
        y += 8
    }

    private func tableHeader() {
        ensure(26)
        UIColor(white: 0.94, alpha: 1).setFill(); UIBezierPath(rect: CGRect(x: margin, y: y, width: pageWidth-margin*2, height: 22)).fill()
        for (value, x, width, align) in [("BILL", margin, CGFloat(135), NSTextAlignment.left), ("CATEGORY", 180, 94, .left), ("AMOUNT", 279, 74, .right), ("DUE", 363, 65, .left), ("STATUS", 433, 94, .left)] {
            text(value, x: x, y: y + 7, width: width, font: .boldSystemFont(ofSize: 7), color: muted, align: align)
        }
        y += 22
    }

    private func billDetail(_ bill: Bill, calendar: Calendar) {
        ensure(105)
        text(bill.name, x: margin, width: 380, font: .boldSystemFont(ofSize: 14), color: ink)
        let s = status(for: bill, calendar: calendar)
        text(s.label, x: 455, width: 74, font: .boldSystemFont(ofSize: 9), color: s.color, align: .right)
        y += 23
        keyValue("Amount due", BillShareService.currency(bill.amount))
        if bill.isPayoffTrackingEnabled {
            if let original = bill.payoffOriginalBalance { keyValue("Original amount", BillShareService.currency(original)) }
            if let remaining = bill.payoffRemainingBalance { keyValue("Remaining balance", BillShareService.currency(remaining)) }
            if let count = bill.estimatedPayoffPaymentCount { keyValue("Remaining payments", "Approximately \(count)") }
        }
        keyValue("Category", bill.category.title); keyValue("Due date", longDate(bill.dueDate))
        keyValue("Status", "\(s.label) - \(s.detail)"); keyValue("Recurring frequency", bill.recurrence.title)
        keyValue("Created", longDate(bill.createdAt)); keyValue("Last updated", longDate(bill.updatedAt))
        if !bill.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ensure(35); text("Notes", x: margin, width: 115, font: .boldSystemFont(ofSize: 9), color: muted)
            y += 14; paragraph(bill.notes, color: ink); y += 4
        }
        if !bill.payoffHistory.isEmpty {
            ensure(35); text("PAYMENT HISTORY", x: margin, width: 250, font: .boldSystemFont(ofSize: 9), color: gold); y += 17
            for record in bill.payoffHistory.sorted(by: { $0.date < $1.date }) {
                ensure(24)
                text(shortDate(record.date), x: margin, width: 75, font: .systemFont(ofSize: 8), color: ink)
                text(record.kind.title, x: 125, width: 115, font: .systemFont(ofSize: 8), color: muted)
                text(BillShareService.currency(record.amount), x: 245, width: 85, font: .systemFont(ofSize: 8), color: ink, align: .right)
                text("Balance: \(BillShareService.currency(record.remainingBalanceAfter))", x: 345, width: 182, font: .systemFont(ofSize: 8), color: muted, align: .right)
                y += 18
            }
        }
        y += 14
    }

    private func keyValue(_ key: String, _ value: String) {
        ensure(18)
        text(key, x: margin, width: 155, font: .boldSystemFont(ofSize: 8), color: muted)
        text(value, x: 205, width: 322, font: .systemFont(ofSize: 9), color: ink)
        y += 16
    }

    private func paragraph(_ value: String, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: color]
        var words = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while !words.isEmpty {
            if pageHeight - 55 - y < 18 { newPage(continued: true) }
            let available = pageHeight - 55 - y
            var low = 1, high = words.count, fitting = 1
            while low <= high {
                let mid = (low + high) / 2
                let candidate = words.prefix(mid).joined(separator: " ")
                let height = (candidate as NSString).boundingRect(
                    with: CGSize(width: pageWidth-margin*2, height: 10_000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil
                ).height
                if height <= available { fitting = mid; low = mid + 1 } else { high = mid - 1 }
            }
            let chunk = words.prefix(fitting).joined(separator: " ")
            let drawn = text(chunk, x: margin, width: pageWidth-margin*2,
                             font: .systemFont(ofSize: 9), color: color, maxHeight: available)
            y += drawn + 3
            words.removeFirst(fitting)
        }
    }

    @discardableResult private func text(_ value: String, x: CGFloat, y explicitY: CGFloat? = nil, width: CGFloat,
                                         font: UIFont, color: UIColor, align: NSTextAlignment = .left,
                                         maxHeight: CGFloat = 1000) -> CGFloat {
        let style = NSMutableParagraphStyle(); style.alignment = align; style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let originY = explicitY ?? y
        let box = (value as NSString).boundingRect(with: CGSize(width: width, height: maxHeight), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        (value as NSString).draw(with: CGRect(x: x, y: originY, width: width, height: min(maxHeight, ceil(box.height)+2)), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs, context: nil)
        return ceil(box.height)
    }

    private func status(for bill: Bill, calendar: Calendar) -> (label: String, detail: String, color: UIColor) {
        if bill.isPaid { return ("PAID", "Paid", green) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: generatedAt), to: calendar.startOfDay(for: bill.dueDate)).day ?? 0
        if days < 0 { return ("OVERDUE", "\(-days) day\(-days == 1 ? "" : "s") overdue", .systemRed) }
        if days == 0 { return ("DUE TODAY", "Due today", .systemRed) }
        if days <= 3 { return ("DUE SOON", "Due in \(days) days", gold) }
        return ("UNPAID", "Due in \(days) days", ink)
    }

    private func shortDate(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: date) }
    private func longDate(_ date: Date) -> String { let f = DateFormatter(); f.dateStyle = .long; return f.string(from: date) }
}

struct BillPDFPreviewView: View {
    let bills: [Bill]
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var report: BillShareService.PDFReport?
    @State private var errorMessage: String?
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let report {
                        PDFPagePreview(url: report.url).frame(height: 390).clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(report.title).font(.headline)
                        Label("\(report.billCount) bill\(report.billCount == 1 ? "" : "s")", systemImage: "doc.text")
                        Label(BillShareService.currency(report.totalAmount), systemImage: "dollarsign.circle")
                        Label(report.dateRange, systemImage: "calendar")
                    }
                    TextField("Optional report note", text: $note, axis: .vertical)
                        .lineLimit(3...7).textFieldStyle(.roundedBorder)
                        .accessibilityHint("This note appears near the beginning of the PDF")
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                    HStack {
                        Button { prepareAndShare() } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.borderedProminent)
                        Button { prepareAndShare() } label: { Label("Save PDF", systemImage: "folder") }
                            .buttonStyle(.bordered)
                    }
                }.padding()
            }
            .background(Theme.Color.background)
            .navigationTitle("PDF Preview")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { generate() }
            .onChange(of: note) { _, _ in generate() }
            .sheet(isPresented: $showShare) { if let report { PDFActivityView(items: [report.url]) } }
        }
    }

    private func generate() {
        do { report = try BillShareService.generatePDF(bills: bills, note: note); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func prepareAndShare() { generate(); if report != nil { showShare = true } }
}

private struct PDFPagePreview: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePage; return view }
    func updateUIView(_ view: PDFView, context: Context) { view.document = PDFDocument(url: url); view.goToFirstPage(nil) }
}

private struct PDFActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
