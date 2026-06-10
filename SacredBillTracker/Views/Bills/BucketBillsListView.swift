//
//  BucketBillsListView.swift
//  SacredBillTracker
//
//  Destination pushed when the user taps a Dashboard stat card
//  (Due Today / This Week / Overdue / Upcoming). Reuses the existing
//  BillRowView + BillDetailView so every interaction (mark paid /
//  unpaid, delete, swipe, edit) stays identical to the main Bills tab.
//

import SwiftUI

struct BucketBillsListView: View {

    let bucket: BillBucket

    @EnvironmentObject private var store: BillStore

    /// v1.0.9 — Single-source edit trigger (see BillsView comment).
    @State private var billToEdit: Bill?

    var body: some View {
        let bills = bucketBills

        Group {
            if bills.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "All clear",
                    message: bucket.emptyMessage
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
                            if !bill.isPaid {
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
        .navigationTitle(bucket.listTitle)
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $billToEdit) { bill in
            AddEditBillView(mode: .edit(bill))
                .environmentObject(store)
        }
    }

    private var bucketBills: [Bill] {
        switch bucket {
        case .dueToday: return store.dueToday
        case .thisWeek: return store.dueThisWeek
        case .overdue:  return store.overdue
        case .upcoming: return store.upcoming
        }
    }
}

#Preview {
    NavigationStack {
        BucketBillsListView(bucket: .dueToday)
            .environmentObject(BillStore())
    }
}
