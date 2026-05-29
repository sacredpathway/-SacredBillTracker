//
//  BillsByTypeListView.swift
//  SacredBillTracker
//
//  Destination pushed when the user taps a Financial Overview totals
//  card on the Dashboard (Personal Bills / Business Bills). Lists every
//  bill of the chosen `BillType` that is due in the current month and
//  reuses BillRowView + BillDetailView so every interaction stays
//  identical to the main Bills tab.
//

import SwiftUI

struct BillsByTypeListView: View {

    let type: BillType

    @EnvironmentObject private var store: BillStore

    /// v1.0.9 — Single-source edit trigger.
    @State private var billToEdit: Bill?

    var body: some View {
        let bills = filtered

        Group {
            if bills.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: "Nothing here",
                    message: "No \(type.title.lowercased()) bills are due this month."
                )
                .padding(.top, 40)
            } else {
                List {
                    ForEach(bills) { bill in
                        Button {
                            billToEdit = bill
                        } label: {
                            BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount)
                        }
                        .buttonStyle(.plain)
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
            }
        }
        .navigationTitle(type == .business ? "Business Bills" : "Personal Bills")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $billToEdit) { bill in
            AddEditBillView(mode: .edit(bill))
                .environmentObject(store)
        }
    }

    /// All bills of the chosen type due this month, sorted by due date.
    /// Reuses the existing `isDueThisMonth` helper on `Bill` so this
    /// matches the Dashboard's Personal/Business "This Month" totals.
    private var filtered: [Bill] {
        store.bills
            .filter { $0.type == type && $0.isDueThisMonth }
            .sorted { $0.dueDate < $1.dueDate }
    }
}

#Preview {
    NavigationStack {
        BillsByTypeListView(type: .household)
            .environmentObject(BillStore())
    }
}
