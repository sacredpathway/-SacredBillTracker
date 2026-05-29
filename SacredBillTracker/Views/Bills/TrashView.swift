//
//  TrashView.swift
//  SacredBillTracker
//
//  Soft-delete recycle bin (v1.3). Lists bills where deleted_at IS NOT
//  NULL for the current user and lets them be restored. Only loads on
//  appearance and supports pull-to-refresh.
//
//  "Delete Forever" is DEBUG-only — production builds cannot bypass the
//  soft-delete safety net, per the v1.3 spec.
//

import SwiftUI

struct TrashView: View {

    @EnvironmentObject private var store: BillStore

    var body: some View {
        Group {
            if store.deletedBills.isEmpty && !store.isLoadingTrash {
                ScrollView {
                    EmptyStateView(
                        systemImage: "trash",
                        title: "Trash is empty",
                        message: "Deleted bills appear here. Restore them anytime within 30 days."
                    )
                    .padding(.top, 60)
                }
                .refreshable { await store.reloadTrash() }
            } else {
                List {
                    ForEach(store.deletedBills) { bill in
                        TrashRow(bill: bill)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    store.restore(bill)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.appAccent)

                                #if DEBUG
                                Button(role: .destructive) {
                                    store.permanentlyDelete(bill)
                                } label: {
                                    Label("Delete Forever", systemImage: "trash.slash")
                                }
                                #endif
                            }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { await store.reloadTrash() }
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.reloadTrash() }
        .overlay {
            if store.isLoadingTrash && store.deletedBills.isEmpty {
                ProgressView().controlSize(.large)
            }
        }
    }
}

// MARK: - Row

private struct TrashRow: View {

    @EnvironmentObject private var store: BillStore
    let bill: Bill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: bill.category.systemImage)
                .font(.title3)
                .foregroundStyle(bill.type.accentColor)
                .frame(width: 36, height: 36)
                .background(bill.type.accentColor.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name)
                    .font(.subheadline.weight(.semibold))
                Text(deletedSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(bill.formattedAmount)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                store.restore(bill)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.appAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Restore \(bill.name)")
        }
        .padding(.vertical, 4)
    }

    private var deletedSubtitle: String {
        guard let deletedAt = bill.deletedAt else { return "Deleted" }
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .short
        return "Deleted " + fmt.localizedString(for: deletedAt, relativeTo: Date())
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrashView()
    }
    .environmentObject(BillStore())
}
#endif
