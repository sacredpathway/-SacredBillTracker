//
//  BillDetailView.swift
//  SacredBillTracker
//

import SwiftUI

struct BillDetailView: View {

    @EnvironmentObject private var store: BillStore
    @State private var showEdit = false

    let bill: Bill

    // Read the latest version from the store so edits propagate instantly.
    private var currentBill: Bill {
        store.bills.first(where: { $0.id == bill.id }) ?? bill
    }

    var body: some View {
        let b = currentBill
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(for: b)
                amountCard(for: b)
                detailsCard(for: b)
                actionButtons(for: b)
                if !b.notes.isEmpty {
                    notesCard(for: b)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(b.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditBillView(mode: .edit(b))
        }
    }

    // MARK: - Sections

    private func header(for b: Bill) -> some View {
        HStack(spacing: 12) {
            Image(systemName: b.category.systemImage)
                .font(.title2)
                .foregroundStyle(b.type.accentColor)
                .frame(width: 52, height: 52)
                .background(b.type.accentColor.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(b.category.title).font(.headline)
                Label(b.type.title, systemImage: b.type.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: b.effectiveStatus)
        }
    }

    private func amountCard(for b: Bill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Amount Due")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(b.formattedAmount)
                .font(.largeTitle.bold().monospacedDigit())
            Text(b.dueDate.mediumFormatted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailsCard(for b: Bill) -> some View {
        VStack(spacing: 0) {
            detailRow("Recurrence", value: b.recurrence.title, icon: "repeat")
            Divider()
            detailRow("Auto-Pay", value: b.autoPay ? "On" : "Off",
                      icon: b.autoPay ? "checkmark.circle.fill" : "xmark.circle")
            Divider()
            detailRow("Category", value: b.category.title, icon: b.category.systemImage)
            Divider()
            detailRow("Type", value: b.type.title, icon: b.type.systemImage)
        }
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func actionButtons(for b: Bill) -> some View {
        HStack(spacing: 12) {
            if b.status == .paid {
                Button {
                    store.markUnpaid(b)
                } label: {
                    Label("Mark Unpaid", systemImage: "clock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    store.markPaid(b)
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private func notesCard(for b: Bill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(b.notes)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BillDetailView(bill: SampleData.bills()[0])
    }
    .environmentObject(BillStore())
}
#endif
