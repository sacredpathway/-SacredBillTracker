//
//  CPAReportGenerator.swift
//  SacredBillTracker
//
//  Builds an accountant-ready, multi-page, monochrome PDF that
//  summarizes bills, expenses, income, categories, monthly totals,
//  and bill-status counts for a chosen date range.
//
//  Engine: UIGraphicsPDFRenderer (Core Graphics). No third-party
//  dependencies, no networking — fully offline-first.
//

import Foundation
import UIKit

// MARK: - Date range

/// Pre-baked ranges shown on the CPA export screen.
enum CPADateRangeOption: String, CaseIterable, Identifiable {
    case currentMonth
    case lastMonth
    case currentQuarter
    case yearToDate
    case lastYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .currentMonth:   return "Current Month"
        case .lastMonth:      return "Last Month"
        case .currentQuarter: return "Current Quarter"
        case .yearToDate:     return "Year to Date"
        case .lastYear:       return "Last Year"
        case .custom:         return "Custom Range"
        }
    }

    /// Slug used inside the generated PDF filename, e.g. `yearToDate`.
    var filenameSlug: String { rawValue }
}

/// A concrete `[start, end]` range, plus the human-readable label that
/// renders in the PDF header (e.g. "Year to Date · Jan 1 – May 16, 2026").
struct CPADateRange: Hashable {
    let start: Date
    let end: Date
    let label: String

    static func resolve(
        option: CPADateRangeOption,
        customStart: Date,
        customEnd: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> CPADateRange {

        let cal = calendar
        let today = cal.startOfDay(for: now)
        let endOfToday = cal.date(
            bySettingHour: 23, minute: 59, second: 59, of: today
        ) ?? today

        switch option {

        case .currentMonth:
            guard let interval = cal.dateInterval(of: .month, for: today) else {
                return CPADateRange(start: today, end: endOfToday, label: option.title)
            }
            let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
            return CPADateRange(start: interval.start, end: end, label: prettyLabel(option, interval.start, end))

        case .lastMonth:
            guard
                let thisMonthStart = cal.dateInterval(of: .month, for: today)?.start,
                let lastMonthStart = cal.date(byAdding: .month, value: -1, to: thisMonthStart),
                let lastMonthEndExclusive = cal.date(byAdding: .month, value: 1, to: lastMonthStart),
                let lastMonthEnd = cal.date(byAdding: .second, value: -1, to: lastMonthEndExclusive)
            else {
                return CPADateRange(start: today, end: endOfToday, label: option.title)
            }
            return CPADateRange(start: lastMonthStart, end: lastMonthEnd, label: prettyLabel(option, lastMonthStart, lastMonthEnd))

        case .currentQuarter:
            let month = cal.component(.month, from: today)
            let year  = cal.component(.year, from: today)
            // 1–3 → Q1, 4–6 → Q2, 7–9 → Q3, 10–12 → Q4.
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var startComps = DateComponents()
            startComps.year = year
            startComps.month = quarterStartMonth
            startComps.day = 1
            let start = cal.date(from: startComps) ?? today
            let endExclusive = cal.date(byAdding: .month, value: 3, to: start) ?? today
            let end = cal.date(byAdding: .second, value: -1, to: endExclusive) ?? today
            return CPADateRange(start: start, end: end, label: prettyLabel(option, start, end))

        case .yearToDate:
            let year = cal.component(.year, from: today)
            var startComps = DateComponents()
            startComps.year = year
            startComps.month = 1
            startComps.day = 1
            let start = cal.date(from: startComps) ?? today
            return CPADateRange(start: start, end: endOfToday, label: prettyLabel(option, start, endOfToday))

        case .lastYear:
            let year = cal.component(.year, from: today) - 1
            var startComps = DateComponents()
            startComps.year = year
            startComps.month = 1
            startComps.day = 1
            let start = cal.date(from: startComps) ?? today
            var endComps = DateComponents()
            endComps.year = year
            endComps.month = 12
            endComps.day = 31
            endComps.hour = 23
            endComps.minute = 59
            endComps.second = 59
            let end = cal.date(from: endComps) ?? today
            return CPADateRange(start: start, end: end, label: prettyLabel(option, start, end))

        case .custom:
            let cleanStart = cal.startOfDay(for: customStart)
            let cleanEnd = cal.date(
                bySettingHour: 23, minute: 59, second: 59,
                of: cal.startOfDay(for: customEnd)
            ) ?? customEnd
            return CPADateRange(start: cleanStart, end: cleanEnd, label: prettyLabel(.custom, cleanStart, cleanEnd))
        }
    }

    private static func prettyLabel(_ option: CPADateRangeOption, _ start: Date, _ end: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        let s = fmt.string(from: start)
        let e = fmt.string(from: end)
        return "\(option.title) · \(s) – \(e)"
    }

    var closedRange: ClosedRange<Date> { start...end }
}

// MARK: - Options the export view passes in

struct CPAReportOptions {
    var businessMode: Bool
    var businessName: String
    var includeIncome: Bool
    var includePersonal: Bool
    var includeBusinessBills: Bool
}

// MARK: - Generator

enum CPAReportGenerator {

    // 8.5" × 11" @ 72dpi = 612 × 792.
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 40
    private static let lineHeight: CGFloat = 16

    /// Builds the PDF and returns the on-disk URL inside the app's
    /// temporary directory so the caller can hand it to ShareSheet /
    /// QuickLook. Throws on disk-write failure.
    static func generate(
        bills: [Bill],
        income: [WeeklyIncome],
        monthlyIncome: [(month: Date, total: Decimal)],
        range: CPADateRange,
        options: CPAReportOptions,
        rangeOptionSlug: String,
        taxYear: Int
    ) throws -> URL {

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0,
                                                            width: pageWidth,
                                                            height: pageHeight))

        let data = renderer.pdfData { ctx in

            var cursor = Cursor(y: margin)

            // Page 1 — header / summary / category totals.
            ctx.beginPage()
            drawHeader(at: &cursor, ctx: ctx, range: range, options: options, taxYear: taxYear)
            drawProfile(at: &cursor, ctx: ctx, options: options, taxYear: taxYear, range: range)
            drawSummary(at: &cursor, ctx: ctx, bills: bills, income: income, options: options)
            drawCategoryTotals(at: &cursor, ctx: ctx, bills: bills)

            // Monthly breakdown gets its own section but can sit on
            // page 1 if there's space, else carries over via ensureSpace.
            drawMonthlyBreakdown(at: &cursor, ctx: ctx, bills: bills, monthlyIncome: monthlyIncome)
            drawTopExpenseCategories(at: &cursor, ctx: ctx, bills: bills)
            drawWriteOffSummary(at: &cursor, ctx: ctx, bills: bills)
            drawBillStatusSummary(at: &cursor, ctx: ctx, bills: bills)

            if options.includeIncome {
                drawIncomeDetail(at: &cursor, ctx: ctx, income: income)
            }

            drawFooter(at: &cursor, ctx: ctx)
        }

        // Persist.
        let filename = "cpa_\(rangeOptionSlug)_\(taxYear).pdf"
        let tmpDir = FileManager.default.temporaryDirectory
        let url = tmpDir.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Cursor

    /// Tracks the current y position across the entire PDF render. The
    /// drawing helpers advance the cursor and start a new page via
    /// `ensureSpace(_:ctx:)` whenever the next chunk wouldn't fit.
    private struct Cursor {
        var y: CGFloat
    }

    private static func ensureSpace(_ needed: CGFloat, cursor: inout Cursor, ctx: UIGraphicsPDFRendererContext) {
        if cursor.y + needed > pageHeight - margin {
            ctx.beginPage()
            cursor.y = margin
        }
    }

    // MARK: - Fonts

    private static let titleFont       = UIFont.systemFont(ofSize: 22, weight: .bold)
    private static let subtitleFont    = UIFont.systemFont(ofSize: 12, weight: .semibold)
    private static let sectionFont     = UIFont.systemFont(ofSize: 13, weight: .bold)
    private static let bodyFont        = UIFont.systemFont(ofSize: 10)
    private static let monoFont        = UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private static let monoBoldFont    = UIFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
    private static let smallFont       = UIFont.systemFont(ofSize: 9)

    private static let textColor       = UIColor.black
    private static let mutedColor      = UIColor.darkGray

    // MARK: - Header

    private static func drawHeader(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        range: CPADateRange,
        options: CPAReportOptions,
        taxYear: Int
    ) {
        ensureSpace(110, cursor: &cursor, ctx: ctx)

        drawText("SACRED BILL TRACKER",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: titleFont, color: textColor)
        cursor.y += 26

        drawText("CPA READY TAX PACKAGE",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: subtitleFont, color: textColor, tracking: 1.5)
        cursor.y += 18

        drawText("Generated for accountant / tax-prep use",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: bodyFont, color: mutedColor)
        cursor.y += 14

        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        drawText("Generated: \(fmt.string(from: Date()))",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: smallFont, color: mutedColor)
        cursor.y += 12

        drawText("Tax Year: \(taxYear)    |    Range: \(range.label)",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: smallFont, color: mutedColor)
        cursor.y += 16

        drawHRule(at: cursor.y, ctx: ctx, thick: true)
        cursor.y += 14
    }

    // MARK: - Profile

    private static func drawProfile(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        options: CPAReportOptions,
        taxYear: Int,
        range: CPADateRange
    ) {
        ensureSpace(60, cursor: &cursor, ctx: ctx)
        drawSectionHeader("PROFILE", at: &cursor, ctx: ctx)

        let nameLine: String
        let modeLine: String
        if options.businessMode {
            let cleaned = options.businessName.trimmingCharacters(in: .whitespacesAndNewlines)
            nameLine = cleaned.isEmpty ? "Business Name: —" : "Business Name: \(cleaned)"
            modeLine = "Report Mode:   Business"
        } else {
            nameLine = "Filer:         Personal"
            modeLine = "Report Mode:   Personal Finance Summary"
        }

        drawText(nameLine, at: CGPoint(x: margin, y: cursor.y),
                 font: monoFont, color: textColor)
        cursor.y += lineHeight
        drawText(modeLine, at: CGPoint(x: margin, y: cursor.y),
                 font: monoFont, color: textColor)
        cursor.y += lineHeight
        drawText("Tax Year:      \(taxYear)", at: CGPoint(x: margin, y: cursor.y),
                 font: monoFont, color: textColor)
        cursor.y += lineHeight
        drawText("Period:        \(range.label)", at: CGPoint(x: margin, y: cursor.y),
                 font: monoFont, color: textColor)
        cursor.y += lineHeight + 6

        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 12
    }

    // MARK: - Summary

    private static func drawSummary(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        bills: [Bill],
        income: [WeeklyIncome],
        options: CPAReportOptions
    ) {
        ensureSpace(160, cursor: &cursor, ctx: ctx)
        drawSectionHeader("SUMMARY", at: &cursor, ctx: ctx)

        let totalIncome = income.reduce(Decimal(0)) { $0 + $1.amount }
        let totalBillsPaid = bills.filter { $0.isPaid }.reduce(Decimal(0)) { $0 + $1.amount }
        let totalExpenses = bills.reduce(Decimal(0)) { $0 + $1.amount }
        let overdueTotal = bills.filter { $0.isOverdue }.reduce(Decimal(0)) { $0 + $1.amount }
        let upcomingTotal = bills
            .filter { !$0.isPaid && !$0.isOverdue }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let estimatedNet = totalIncome - totalExpenses

        let rows: [(String, Decimal, Bool)] = [
            ("Total income",         options.includeIncome ? totalIncome : Decimal(0), false),
            ("Total bills paid",     totalBillsPaid,        false),
            ("Total expenses (all bills)", totalExpenses,   false),
            ("Estimated net",        estimatedNet,          true),
            ("Overdue totals",       overdueTotal,          false),
            ("Upcoming totals",      upcomingTotal,         false),
        ]

        for (label, value, emphasized) in rows {
            ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
            drawLabelValueRow(label: label,
                              value: formatCurrency(value),
                              y: cursor.y,
                              boldValue: emphasized)
            cursor.y += lineHeight + 2
        }
        cursor.y += 6
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 12
    }

    // MARK: - Category Totals

    private static func drawCategoryTotals(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        bills: [Bill]
    ) {
        ensureSpace(100, cursor: &cursor, ctx: ctx)
        drawSectionHeader("CATEGORY TOTALS", at: &cursor, ctx: ctx)

        drawTableHeader(["Category", "Count", "Total"],
                        columnWidths: [pageWidth - margin*2 - 200, 80, 120],
                        ctx: ctx, y: cursor.y)
        cursor.y += 14
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 6

        let grouped = Dictionary(grouping: bills, by: { $0.category })
        let rows = grouped
            .map { (cat, list) -> (String, Int, Decimal) in
                (cat.title, list.count, list.reduce(Decimal(0)) { $0 + $1.amount })
            }
            .sorted { $0.2 > $1.2 }

        if rows.isEmpty {
            drawText("No bills in this range.",
                     at: CGPoint(x: margin, y: cursor.y),
                     font: bodyFont, color: mutedColor)
            cursor.y += lineHeight
        } else {
            for (title, count, total) in rows {
                ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
                drawTableRow([title, "\(count)", formatCurrency(total)],
                             columnWidths: [pageWidth - margin*2 - 200, 80, 120],
                             y: cursor.y)
                cursor.y += lineHeight + 2
            }
        }

        // Totals line.
        let totalCount = rows.reduce(0) { $0 + $1.1 }
        let totalAmount = rows.reduce(Decimal(0)) { $0 + $1.2 }
        cursor.y += 4
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 4
        drawTableRow(["TOTAL", "\(totalCount)", formatCurrency(totalAmount)],
                     columnWidths: [pageWidth - margin*2 - 200, 80, 120],
                     y: cursor.y, bold: true)
        cursor.y += lineHeight + 12
    }

    // MARK: - Monthly Breakdown

    private static func drawMonthlyBreakdown(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        bills: [Bill],
        monthlyIncome: [(month: Date, total: Decimal)]
    ) {
        ensureSpace(120, cursor: &cursor, ctx: ctx)
        drawSectionHeader("MONTHLY BREAKDOWN", at: &cursor, ctx: ctx)

        let widths: [CGFloat] = [180, 110, 110, 132]
        drawTableHeader(["Month", "Income", "Expenses", "Net"],
                        columnWidths: widths, ctx: ctx, y: cursor.y)
        cursor.y += 14
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 6

        // Build the union of months that appear in either bills or
        // income so a month with only income still shows up.
        let cal = Calendar.current
        let billMonths = Dictionary(grouping: bills) { bill -> Date in
            let comps = cal.dateComponents([.year, .month], from: bill.dueDate)
            return cal.date(from: comps) ?? bill.dueDate
        }
        let incomeMonths = Dictionary(uniqueKeysWithValues: monthlyIncome.map { ($0.month, $0.total) })

        let allMonths = Set(billMonths.keys).union(incomeMonths.keys).sorted()

        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"

        if allMonths.isEmpty {
            drawText("No data in this range.",
                     at: CGPoint(x: margin, y: cursor.y),
                     font: bodyFont, color: mutedColor)
            cursor.y += lineHeight
        } else {
            var totalIncome = Decimal(0)
            var totalExpenses = Decimal(0)
            for month in allMonths {
                ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
                let monthBills = billMonths[month] ?? []
                let expenses = monthBills.reduce(Decimal(0)) { $0 + $1.amount }
                let income = incomeMonths[month] ?? 0
                let net = income - expenses
                totalIncome += income
                totalExpenses += expenses
                drawTableRow(
                    [fmt.string(from: month),
                     formatCurrency(income),
                     formatCurrency(expenses),
                     formatCurrency(net)],
                    columnWidths: widths,
                    y: cursor.y
                )
                cursor.y += lineHeight + 2
            }
            cursor.y += 4
            drawHRule(at: cursor.y, ctx: ctx)
            cursor.y += 4
            drawTableRow(
                ["TOTAL",
                 formatCurrency(totalIncome),
                 formatCurrency(totalExpenses),
                 formatCurrency(totalIncome - totalExpenses)],
                columnWidths: widths,
                y: cursor.y,
                bold: true
            )
            cursor.y += lineHeight
        }
        cursor.y += 12
    }

    // MARK: - Top expense categories

    private static func drawTopExpenseCategories(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        bills: [Bill]
    ) {
        ensureSpace(120, cursor: &cursor, ctx: ctx)
        drawSectionHeader("TOP EXPENSE CATEGORIES", at: &cursor, ctx: ctx)

        let grouped = Dictionary(grouping: bills, by: { $0.category })
        let ranked = grouped
            .map { (cat: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
            .prefix(5)

        if ranked.isEmpty {
            drawText("No expenses in this range.",
                     at: CGPoint(x: margin, y: cursor.y),
                     font: bodyFont, color: mutedColor)
            cursor.y += lineHeight + 12
            return
        }

        let widths: [CGFloat] = [40, pageWidth - margin*2 - 40 - 120, 120]
        drawTableHeader(["#", "Category", "Total"],
                        columnWidths: widths, ctx: ctx, y: cursor.y)
        cursor.y += 14
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 6

        for (i, item) in ranked.enumerated() {
            ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
            drawTableRow(
                ["\(i + 1)", item.cat.title, formatCurrency(item.total)],
                columnWidths: widths,
                y: cursor.y
            )
            cursor.y += lineHeight + 2
        }
        cursor.y += 12
    }

    // MARK: - Write-off summary

    private static func drawWriteOffSummary(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        bills: [Bill]
    ) {
        ensureSpace(120, cursor: &cursor, ctx: ctx)
        drawSectionHeader("WRITE-OFF SUMMARY", at: &cursor, ctx: ctx)
        drawText("Deductible-style groupings — confirm with your CPA.",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: smallFont, color: mutedColor)
        cursor.y += 14

        // Bucket categories into typical deduction groups. Business
        // bills are flagged separately at the bottom.
        let groups: [(String, [BillCategory])] = [
            ("Office / Software",        [.software, .officeSupplies, .equipment]),
            ("Vehicle / Transportation", [.transportation]),
            ("Insurance",                [.insurance]),
            ("Utilities / Internet / Phone", [.utilities, .utilitiesBusiness, .internet, .phone]),
            ("Rent (Business)",          [.rentBusiness]),
            ("Marketing / Advertising",  [.marketing]),
            ("Legal / Professional",     [.legal]),
            ("Payroll / Services",       [.payroll, .services]),
            ("Medical",                  [.medical]),
            ("Taxes",                    [.taxes]),
        ]

        let widths: [CGFloat] = [pageWidth - margin*2 - 200, 80, 120]
        drawTableHeader(["Group", "Count", "Total"],
                        columnWidths: widths, ctx: ctx, y: cursor.y)
        cursor.y += 14
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 6

        var grandTotal = Decimal(0)
        var grandCount = 0

        for (label, cats) in groups {
            let scope = bills.filter { cats.contains($0.category) }
            if scope.isEmpty { continue }
            ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
            let total = scope.reduce(Decimal(0)) { $0 + $1.amount }
            grandTotal += total
            grandCount += scope.count
            drawTableRow(
                [label, "\(scope.count)", formatCurrency(total)],
                columnWidths: widths,
                y: cursor.y
            )
            cursor.y += lineHeight + 2
        }

        // Business-only row — every bill flagged BillType.business.
        let businessOnly = bills.filter { $0.type == .business }
        if !businessOnly.isEmpty {
            ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
            let bTotal = businessOnly.reduce(Decimal(0)) { $0 + $1.amount }
            drawTableRow(
                ["Business-flagged (all)", "\(businessOnly.count)", formatCurrency(bTotal)],
                columnWidths: widths,
                y: cursor.y
            )
            cursor.y += lineHeight + 2
        }

        cursor.y += 4
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 4
        drawTableRow(
            ["DEDUCTIBLE GROUPS TOTAL", "\(grandCount)", formatCurrency(grandTotal)],
            columnWidths: widths,
            y: cursor.y,
            bold: true
        )
        cursor.y += lineHeight + 12
    }

    // MARK: - Bill status

    private static func drawBillStatusSummary(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        bills: [Bill]
    ) {
        ensureSpace(100, cursor: &cursor, ctx: ctx)
        drawSectionHeader("BILL STATUS SUMMARY", at: &cursor, ctx: ctx)

        let paid = bills.filter { $0.isPaid }
        let upcoming = bills.filter { !$0.isPaid && !$0.isOverdue }
        let overdue = bills.filter { $0.isOverdue }
        let autoPay = bills.filter { $0.autoPay }

        let widths: [CGFloat] = [pageWidth - margin*2 - 200, 80, 120]
        drawTableHeader(["Status", "Count", "Total"],
                        columnWidths: widths, ctx: ctx, y: cursor.y)
        cursor.y += 14
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 6

        let rows: [(String, [Bill])] = [
            ("Paid",     paid),
            ("Upcoming", upcoming),
            ("Overdue",  overdue),
            ("Auto-pay", autoPay),
        ]
        for (label, scope) in rows {
            ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
            let t = scope.reduce(Decimal(0)) { $0 + $1.amount }
            drawTableRow([label, "\(scope.count)", formatCurrency(t)],
                         columnWidths: widths, y: cursor.y)
            cursor.y += lineHeight + 2
        }
        cursor.y += 12
    }

    // MARK: - Income detail

    private static func drawIncomeDetail(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext,
        income: [WeeklyIncome]
    ) {
        ensureSpace(120, cursor: &cursor, ctx: ctx)
        drawSectionHeader("WEEKLY INCOME DETAIL", at: &cursor, ctx: ctx)

        if income.isEmpty {
            drawText("No income entries in this range.",
                     at: CGPoint(x: margin, y: cursor.y),
                     font: bodyFont, color: mutedColor)
            cursor.y += lineHeight + 12
            return
        }

        // v1.0.9 — added Type column (Business / Personal). Widths
        // tightened so the four columns fit inside the page.
        let widths: [CGFloat] = [
            150,                                          // Week / Date
            70,                                           // Type
            pageWidth - margin*2 - 150 - 70 - 100,        // Source / Note
            100                                           // Amount
        ]
        drawTableHeader(["Week / Date", "Type", "Source / Note", "Amount"],
                        columnWidths: widths, ctx: ctx, y: cursor.y)
        cursor.y += 14
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 6

        let sorted = income.sorted { $0.weekStart < $1.weekStart }
        var total = Decimal(0)
        var businessTotal = Decimal(0)
        var personalTotal = Decimal(0)
        for entry in sorted {
            ensureSpace(lineHeight + 2, cursor: &cursor, ctx: ctx)
            total += entry.amount
            switch entry.type {
            case .business: businessTotal += entry.amount
            case .personal: personalTotal += entry.amount
            }
            let sourceOrNote: String = {
                let src = entry.sourceName.trimmingCharacters(in: .whitespaces)
                let nt = entry.note.trimmingCharacters(in: .whitespaces)
                switch (src.isEmpty, nt.isEmpty) {
                case (true, true):   return "—"
                case (false, true):  return src
                case (true, false):  return nt
                case (false, false): return "\(src) — \(nt)"
                }
            }()
            drawTableRow(
                [entry.rangeLabelWithYear,
                 entry.type.title,
                 sourceOrNote,
                 formatCurrency(entry.amount)],
                columnWidths: widths,
                y: cursor.y
            )
            cursor.y += lineHeight + 2
        }
        cursor.y += 4
        drawHRule(at: cursor.y, ctx: ctx)
        cursor.y += 4
        drawTableRow(
            ["BUSINESS TOTAL", "", "", formatCurrency(businessTotal)],
            columnWidths: widths,
            y: cursor.y,
            bold: true
        )
        cursor.y += lineHeight + 2
        drawTableRow(
            ["PERSONAL TOTAL", "", "", formatCurrency(personalTotal)],
            columnWidths: widths,
            y: cursor.y,
            bold: true
        )
        cursor.y += lineHeight + 2
        drawTableRow(
            ["TOTAL", "", "", formatCurrency(total)],
            columnWidths: widths,
            y: cursor.y,
            bold: true
        )
        cursor.y += lineHeight + 12
    }

    // MARK: - Footer

    private static func drawFooter(
        at cursor: inout Cursor,
        ctx: UIGraphicsPDFRendererContext
    ) {
        ensureSpace(50, cursor: &cursor, ctx: ctx)
        drawHRule(at: cursor.y, ctx: ctx, thick: true)
        cursor.y += 10
        drawText("This report is informational only and does not constitute tax advice.",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: smallFont, color: mutedColor)
        cursor.y += 12
        drawText("Generated by Sacred Bill Tracker",
                 at: CGPoint(x: margin, y: cursor.y),
                 font: smallFont, color: mutedColor)
    }

    // MARK: - Primitive drawing

    private static func drawSectionHeader(_ title: String,
                                          at cursor: inout Cursor,
                                          ctx: UIGraphicsPDFRendererContext) {
        ensureSpace(28, cursor: &cursor, ctx: ctx)
        drawText(title,
                 at: CGPoint(x: margin, y: cursor.y),
                 font: sectionFont, color: textColor, tracking: 1.2)
        cursor.y += 18
        drawHRule(at: cursor.y - 4, ctx: ctx)
    }

    private static func drawText(_ text: String,
                                 at point: CGPoint,
                                 font: UIFont,
                                 color: UIColor,
                                 tracking: CGFloat = 0) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private static func drawText(_ text: String,
                                 in rect: CGRect,
                                 font: UIFont,
                                 color: UIColor,
                                 alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    private static func drawHRule(at y: CGFloat,
                                  ctx: UIGraphicsPDFRendererContext,
                                  thick: Bool = false) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: y))
        path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
        path.lineWidth = thick ? 1.0 : 0.4
        UIColor.black.setStroke()
        path.stroke()
    }

    private static func drawLabelValueRow(label: String,
                                          value: String,
                                          y: CGFloat,
                                          boldValue: Bool) {
        let labelRect = CGRect(x: margin, y: y,
                               width: pageWidth - margin*2 - 140, height: lineHeight)
        let valueRect = CGRect(x: pageWidth - margin - 140, y: y,
                               width: 140, height: lineHeight)
        drawText(label, in: labelRect, font: bodyFont, color: textColor)
        drawText(value, in: valueRect,
                 font: boldValue ? monoBoldFont : monoFont,
                 color: textColor,
                 alignment: .right)
    }

    /// Right-align any column whose width is ≤ 140 (the numeric/count
    /// columns) and any column whose title sits in `numericTitles`. The
    /// first column is always left-aligned regardless.
    private static let numericTitles: Set<String> = [
        "Count", "Total", "Income", "Expenses", "Net", "Amount", "#"
    ]

    private static func columnAlignments(titles: [String],
                                         columnWidths: [CGFloat]) -> [NSTextAlignment] {
        zip(titles, columnWidths).enumerated().map { i, pair in
            let (title, width) = pair
            if i == 0 { return .left }
            if numericTitles.contains(title) { return .right }
            return width <= 140 ? .right : .left
        }
    }

    private static func drawTableHeader(_ titles: [String],
                                        columnWidths: [CGFloat],
                                        ctx: UIGraphicsPDFRendererContext,
                                        y: CGFloat) {
        let alignments = columnAlignments(titles: titles, columnWidths: columnWidths)
        var x = margin
        for (i, title) in titles.enumerated() {
            let w = columnWidths[i]
            drawText(title,
                     in: CGRect(x: x, y: y, width: w, height: lineHeight),
                     font: monoBoldFont,
                     color: textColor,
                     alignment: alignments[i])
            x += w
        }
    }

    private static func drawTableRow(_ values: [String],
                                     columnWidths: [CGFloat],
                                     y: CGFloat,
                                     bold: Bool = false) {
        // Re-derive alignment from widths only — table row callers
        // don't have title context, so any narrow non-first column
        // is treated as numeric.
        var x = margin
        let font: UIFont = bold ? monoBoldFont : monoFont
        for (i, val) in values.enumerated() {
            let w = columnWidths[i]
            let alignment: NSTextAlignment = (i == 0) ? .left : (w <= 140 ? .right : .left)
            drawText(val,
                     in: CGRect(x: x, y: y, width: w, height: lineHeight),
                     font: font,
                     color: textColor,
                     alignment: alignment)
            x += w
        }
    }

    // MARK: - Currency

    private static func formatCurrency(_ amount: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f.string(from: amount as NSDecimalNumber) ?? "$\(amount)"
    }
}
