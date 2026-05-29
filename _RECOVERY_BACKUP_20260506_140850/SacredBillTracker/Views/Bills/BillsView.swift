//
//  BillsView.swift
//  SacredBillTracker
//

import SwiftUI

struct BillsView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var subs: SubscriptionManager
    @State private var showAdd = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var scope: BillScope = .mine

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, unpaid, paid, overdue
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .unpaid: return "Unpaid"
            case .paid: return "Paid"
            case .overdue: return "Overdue"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if DEBUG
                // Partner Budgeting destination is hidden from Release until
                // the backend ships, so don't surface its My / Shared filter
                // either. Code stays in the project — flip with the matching
                // gate in SettingsView when ready.
                Picker("Scope", selection: $scope) {
                    ForEach(BillScope.allCases) { s in
                        HStack {
                            Image(systemName: s.systemImage)
                            Text(s.rawValue)
                        }
                        .tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                #endif

                FilterPicker(selection: $store.filter)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                content
            }
            .navigationTitle("Bills")
            .searchable(text: $searchText, prompt: "Search bills")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if canAddBill {
                            showAdd = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add Bill")
                }
            }
            .sheet(isPresented: $showAdd) {
                QuickAddView()
            }
            .paywallSheet(isPresented: $showPaywall,
                          reason: "Free is capped at \(FreeTierLimits.maxBills) bills. Pro makes it unlimited.")
        }
    }

    /// True when the user can add another bill under their current tier.
    private var canAddBill: Bool {
        subs.isPro || store.bills.count < FreeTierLimits.maxBills
    }

    @ViewBuilder
    private var content: some View {
        let list = visibleBills
        if list.isEmpty {
            EmptyStateView(
                systemImage: "tray",
                title: searchText.isEmpty ? "No bills yet" : "No bills found",
                message: searchText.isEmpty
                    ? "No bills yet — tap + to add your first one."
                    : "No bills match your search."
            )
            .padding(.top, 40)
            Spacer()
        } else {
            List {
                ForEach(list) { bill in
                    NavigationLink(value: bill) {
                        BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.delete(bill)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        if bill.status != .paid {
                            Button {
                                store.markPaid(bill)
                            } label: {
                                Label("Paid", systemImage: "checkmark.seal.fill")
                            }
                            .tint(.green)
                        } else {
                            Button {
                                store.markUnpaid(bill)
                            } label: {
                                Label("Unpaid", systemImage: "clock.fill")
                            }
                            .tint(.orange)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationDestination(for: Bill.self) { bill in
                BillDetailView(bill: bill)
            }
        }
    }

    private var visibleBills: [Bill] {
        store.filteredBills.filtered(by: scope).filter { bill in
            let matchesSearch = searchText.isEmpty
                || bill.name.localizedCaseInsensitiveContains(searchText)
                || bill.notes.localizedCaseInsensitiveContains(searchText)
                || bill.category.title.localizedCaseInsensitiveContains(searchText)

            let matchesStatus: Bool
            switch statusFilter {
            case .all:     matchesStatus = true
            case .unpaid:  matchesStatus = bill.effectiveStatus == .unpaid
            case .paid:    matchesStatus = bill.effectiveStatus == .paid
            case .overdue: matchesStatus = bill.effectiveStatus == .overdue
            }
            return matchesSearch && matchesStatus
        }
    }
}

#Preview {
    BillsView()
        .environmentObject(BillStore())
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionManager())
}
