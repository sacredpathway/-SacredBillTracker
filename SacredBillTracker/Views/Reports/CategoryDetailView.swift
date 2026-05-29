//
//  CategoryDetailView.swift
//  SacredBillTracker
//
//  v1.0.9 — Pushed from ReportsView when the user taps a category row.
//  Lists every bill assigned to that category for the displayed month,
//  with totals + sort + a friendly empty state. Reuses BillRowView so
//  the design language matches the rest of the app exactly.
//
//  This is a READ-ONLY drill-in. Tapping a bill row still pushes the
//  existing BillDetailView via the parent NavigationStack's
//  navigationDestination(for: Bill.self), so no extra wiring needed.
//

import SwiftUI

struct CategoryDetailView: View {

    @EnvironmentObject private var store: BillStore

    let category: BillCategory
    /// Month the user was viewing in Reports when they tapped in. Bills
    /// are scoped to this month so the detail matches the breakdown bar
    /// the user just tapped.
    let month: Date
    /// Bill-type filter that was active in Reports (Household vs
    /// Business). When nil, both types are shown.
    let typeFilter: BillType?

    @State private var sort: Sort = .dueDate

    /// v1.0.9 — Single-source edit trigger.
    @State private var billToEdit: Bill?

    private var currency: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }

    // MARK: - Sort options

    enum Sort: String, CaseIterable, Identifiable {
        case dueDate
        case amount
        case status
        case name

        var id: String { rawValue }
        var title: String {
            switch self {
            case .dueDate: return "Due Date"
            case .amount:  return "Amount"
            case .status:  return "Status"
            case .name:    return "Name"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                totalsCard
                    .padding(.horizontal)

                sortPicker
                    .padding(.horizontal)

                if billsInCategory.isEmpty {
                    EmptyStateView(
                        systemImage: "tray",
                        title: "Nothing here",
                        message: "No bills found in this category."
                    )
                    .padding(.top, 40)
                    .padding(.horizontal)
                } else {
                    billList
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.Color.background)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $billToEdit) { bill in
            AddEditBillView(mode: .edit(bill))
                .environmentObject(store)
        }
    }

    // MARK: - Data

    /// Bills inside this category for the displayed month, honoring
    /// the optional type filter that was active in Reports.
    private var billsInCategory: [Bill] {
        let cal = Calendar.current
        return store.bills.filter { bill in
            guard bill.category == category else { return false }
            if let typeFilter, bill.type != typeFilter { return false }
            return cal.component(.month, from: bill.dueDate) == cal.component(.month, from: month)
                && cal.component(.year,  from: bill.dueDate) == cal.component(.year,  from: month)
        }
    }

    private var sortedBills: [Bill] {
        switch sort {
        case .dueDate:
            return billsInCategory.sorted { $0.dueDate < $1.dueDate }
        case .amount:
            return billsInCategory.sorted { $0.amount > $1.amount }
        case .status:
            // Overdue first, then Pending, then Paid; stable secondary
            // sort on due date so equal-status bills stay chronological.
            return billsInCategory.sorted { a, b in
                let ar = statusRank(a)
                let br = statusRank(b)
                if ar != br { return ar < br }
                return a.dueDate < b.dueDate
            }
        case .name:
            return billsInCategory.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func statusRank(_ bill: Bill) -> Int {
        if bill.isOverdue { return 0 }
        if !bill.isPaid   { return 1 }   // Pending
        return 2                          // Paid
    }

    // MARK: - Totals card

    private var totalsCard: some View {
        let bills = billsInCategory
        let total    = bills.reduce(Decimal(0)) { $0 + $1.amount }
        let paid     = bills.filter { $0.isPaid }
                            .reduce(Decimal(0)) { $0 + $1.amount }
        let overdue  = bills.filter { $0.isOverdue }
                            .reduce(Decimal(0)) { $0 + $1.amount }
        let pending  = bills.filter { !$0.isPaid && !$0.isOverdue }
                            .reduce(Decimal(0)) { $0 + $1.amount }
        let count    = bills.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: category.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appAccentText)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.appAccent.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.subheadline.weight(.semibold))
                    Text(month.longMonthYear)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                        .font(.title2.bold().monospacedDigit())
                    Text("\(count) bill\(count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 0) {
                totalTile(label: "Paid",
                          amount: paid,
                          tint: .green)
                Divider().frame(height: 38)
                totalTile(label: "Pending",
                          amount: pending,
                          tint: Color.appAccentText)
                Divider().frame(height: 38)
                totalTile(label: "Overdue",
                          amount: overdue,
                          tint: .appDanger)
            }
        }
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func totalTile(label: String, amount: Decimal, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(currency.string(from: amount as NSDecimalNumber) ?? "$0")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sort picker

    private var sortPicker: some View {
        HStack {
            Text("Sort")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Picker("Sort", selection: $sort) {
                ForEach(Sort.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.menu)
            .tint(Color.appAccentText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bill list

    private var billList: some View {
        let bills = sortedBills
        let maxAmt = bills.filter { !$0.isPaid }.map(\.amount).max() ?? store.maxUnpaidAmount
        return VStack(spacing: 0) {
            ForEach(bills) { bill in
                Button {
                    billToEdit = bill
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        BillRowView(bill: bill, maxUnpaidAmount: maxAmt)
                            .padding(.horizontal)
                        HStack(spacing: 8) {
                            statusBadge(for: bill)
                            typeBadge(for: bill)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if bill.id != bills.last?.id {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Badges

    private func statusBadge(for bill: Bill) -> some View {
        let (label, tint): (String, Color) = {
            if bill.isOverdue { return ("Overdue", .appDanger) }
            if bill.isPaid    { return ("Paid",    .green) }
            return ("Pending", Color.appAccentText)
        }()
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private func typeBadge(for bill: Bill) -> some View {
        let tint: Color = bill.type == .business ? .appBusiness : .appHousehold
        Text(bill.type.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }
}

#Preview {
    NavigationStack {
        CategoryDetailView(
            category: .utilities,
            month: Date(),
            typeFilter: .household
        )
        .environmentObject(BillStore())
    }
}
