//
//  HealthAttentionListView.swift
//  SacredBillTracker
//
//  Sheet presented when the user taps the Dashboard Health Score
//  card. Lists the exact bills driving the warning, with filter chips
//  so the user can move between Overdue / Due Today / Due This Week /
//  Upcoming / High-Dollar Unpaid.
//
//  Source of truth: the same `BillStore.bills` array `BillHealthScore`
//  reads from. There is NO duplicated counting — every filter here is
//  the same predicate the scorer uses, so the dashboard "needs
//  attention" count always matches what the user sees after tapping.
//

import SwiftUI

struct HealthAttentionListView: View {

    @EnvironmentObject private var store: BillStore
    @Environment(\.dismiss) private var dismiss

    /// v1.0.9.x — Edit tapped bill with the same single-sheet pattern.
    @State private var billToEdit: Bill?

    /// Initial filter the user lands on. Driven by the most urgent
    /// signal: overdue → dueToday → dueThisWeek → upcoming.
    @State private var filter: AttentionFilter

    init(initialFilter: AttentionFilter) {
        _filter = State(initialValue: initialFilter)
    }

    enum AttentionFilter: String, CaseIterable, Identifiable, Hashable {
        case overdue
        case dueToday
        case dueThisWeek
        case highDollar
        case upcoming

        var id: String { rawValue }
        var title: String {
            switch self {
            case .overdue:     return "Overdue"
            case .dueToday:    return "Due Today"
            case .dueThisWeek: return "Due This Week"
            case .highDollar:  return "High-Dollar Unpaid"
            case .upcoming:    return "Upcoming"
            }
        }
        var systemImage: String {
            switch self {
            case .overdue:     return "exclamationmark.triangle.fill"
            case .dueToday:    return "clock.fill"
            case .dueThisWeek: return "calendar.badge.clock"
            case .highDollar:  return "dollarsign.circle.fill"
            case .upcoming:    return "tray.full.fill"
            }
        }
    }

    var body: some View {
        let bills = filteredBills
        NavigationStack {
            VStack(spacing: 0) {
                filterChips
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if bills.isEmpty {
                    Spacer(minLength: 8)
                    EmptyStateView(
                        systemImage: "checkmark.seal.fill",
                        title: "You're on track",
                        message: emptyMessage
                    )
                    .padding(.horizontal)
                    Spacer()
                } else {
                    List {
                        Section(header: countHeader(bills.count)) {
                            ForEach(bills) { bill in
                                Button { billToEdit = bill } label: {
                                    BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.delete(bill)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    if !bill.isPaid {
                                        Button {
                                            store.markPaid(bill)
                                        } label: {
                                            Label("Paid", systemImage: "checkmark.seal.fill")
                                        }
                                        .tint(.green)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Theme.Color.background)
            .navigationTitle("Needs Attention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $billToEdit) { bill in
                AddEditBillView(mode: .edit(bill))
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AttentionFilter.allCases) { f in
                    let count = countFor(f)
                    Button {
                        filter = f
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: f.systemImage)
                            Text(f.title)
                            if count > 0 {
                                Text("\(count)")
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(
                                            f == filter
                                            ? Color.appAccent.opacity(0.30)
                                            : Color.secondary.opacity(0.15)
                                        )
                                    )
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(
                                f == filter
                                ? Color.appAccent.opacity(0.18)
                                : Color.secondary.opacity(0.10)
                            )
                        )
                        .foregroundStyle(f == filter ? Color.appAccentText : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Filtered query (single source of truth — same predicates
    //         the health score scorer uses)

    private var filteredBills: [Bill] {
        Self.bills(in: store.bills, for: filter)
    }

    private func countFor(_ f: AttentionFilter) -> Int {
        Self.bills(in: store.bills, for: f).count
    }

    /// Pure filter — single source of truth shared by `filteredBills`
    /// (current view) and `countFor` (filter chip badges). Mirrors the
    /// predicates used by `BillHealthScore.compute(...)`.
    static func bills(in source: [Bill], for filter: AttentionFilter) -> [Bill] {
        let visible = source.filter { $0.deletedAt == nil }
        switch filter {
        case .overdue:
            return visible.filter { !$0.isPaid && $0.effectiveStatus == .overdue }
                          .sorted { $0.dueDate < $1.dueDate }
        case .dueToday:
            return visible.filter { !$0.isPaid && $0.isDueToday }
                          .sorted { $0.amount > $1.amount }
        case .dueThisWeek:
            // Matches BillHealthScore: days from today to dueDate is 1...7
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            return visible.filter { bill in
                guard !bill.isPaid, bill.effectiveStatus != .overdue else { return false }
                let dueDay = cal.startOfDay(for: bill.dueDate)
                let d = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
                return d >= 1 && d <= 7
            }
            .sorted { $0.dueDate < $1.dueDate }
        case .highDollar:
            let unpaid = visible.filter { !$0.isPaid }
            let amounts = unpaid.map(\.amount).sorted()
            guard !amounts.isEmpty else { return [] }
            let q3Index = max(0, Int(Double(amounts.count) * 0.75))
            let threshold = amounts[min(q3Index, amounts.count - 1)]
            return unpaid.filter { $0.amount >= threshold }
                         .sorted { $0.amount > $1.amount }
        case .upcoming:
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            return visible.filter { bill in
                guard !bill.isPaid else { return false }
                let dueDay = cal.startOfDay(for: bill.dueDate)
                return dueDay >= today
            }
            .sorted { $0.dueDate < $1.dueDate }
        }
    }

    private func countHeader(_ n: Int) -> some View {
        Text("\(n) bill\(n == 1 ? "" : "s")")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var emptyMessage: String {
        switch filter {
        case .overdue:     return "No overdue bills."
        case .dueToday:    return "Nothing due today."
        case .dueThisWeek: return "Nothing due in the next 7 days."
        case .highDollar:  return "No unusually large unpaid bills."
        case .upcoming:    return "No upcoming unpaid bills."
        }
    }
}

#Preview {
    HealthAttentionListView(initialFilter: .overdue)
        .environmentObject(BillStore())
}
