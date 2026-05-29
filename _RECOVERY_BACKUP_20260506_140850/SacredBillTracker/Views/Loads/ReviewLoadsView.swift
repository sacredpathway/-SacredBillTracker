//
//  ReviewLoadsView.swift
//  SacredBillTracker
//
//  Admin / dispatcher view for reviewing submitted loads.
//  Approve, reject, edit gross amounts, and generate paystubs.
//

import SwiftUI

struct ReviewLoadsView: View {

    @EnvironmentObject private var loadStore: LoadStore

    @State private var selectedTab: AdminTab = .pending
    @State private var selectedLoad: SubmittedLoad?
    @State private var showingPaystubSheet = false

    enum AdminTab: String, CaseIterable, Identifiable {
        case pending   = "Pending"
        case approved  = "Approved"
        case all       = "All"
        case paystubs  = "Paystubs"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    ForEach(AdminTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Content
                List {
                    switch selectedTab {
                    case .pending:
                        pendingSection
                    case .approved:
                        approvedSection
                    case .all:
                        allLoadsSection
                    case .paystubs:
                        paystubsSection
                    }
                }
            }
            .navigationTitle("Review Loads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if selectedTab == .approved && !loadStore.approvedLoads.isEmpty {
                        Button {
                            showingPaystubSheet = true
                        } label: {
                            Label("Generate Paystubs", systemImage: "banknote.fill")
                        }
                    }
                }
            }
            .sheet(item: $selectedLoad) { load in
                AdminLoadDetailView(load: load)
            }
            .sheet(isPresented: $showingPaystubSheet) {
                GeneratePaystubView()
            }
            .refreshable {
                await loadStore.reload()
            }
        }
    }

    // MARK: - Pending

    @ViewBuilder
    private var pendingSection: some View {
        let pending = loadStore.pendingLoads
        if pending.isEmpty {
            Section {
                emptyState(
                    icon: "checkmark.circle",
                    title: "All Caught Up",
                    subtitle: "No loads waiting for review"
                )
            }
        } else {
            Section("Pending Review (\(pending.count))") {
                ForEach(pending) { load in
                    AdminLoadRow(load: load) {
                        selectedLoad = load
                    }
                    .swipeActions(edge: .trailing) {
                        if load.canBeApproved {
                            Button {
                                loadStore.approveLoad(load)
                            } label: {
                                Label("Approve", systemImage: "checkmark")
                            }
                            .tint(.green)
                        }

                        Button {
                            loadStore.rejectLoad(load, reason: "Rejected by admin")
                        } label: {
                            Label("Reject", systemImage: "xmark")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            selectedLoad = load
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.appAccent)
                    }
                }
            }
        }
    }

    // MARK: - Approved

    @ViewBuilder
    private var approvedSection: some View {
        let approved = loadStore.approvedLoads
        if approved.isEmpty {
            Section {
                emptyState(
                    icon: "tray",
                    title: "No Approved Loads",
                    subtitle: "Approved loads ready for paystub will appear here"
                )
            }
        } else {
            // Group by driver
            let grouped = Dictionary(grouping: approved, by: \.driverId)
            ForEach(Array(grouped.keys), id: \.self) { driverId in
                let driverLoads = grouped[driverId] ?? []
                let name = driverLoads.first?.driverName ?? "Unknown"
                let totalGross = driverLoads.compactMap(\.grossAmount).reduce(Decimal(0), +)
                let totalPay = totalGross * Decimal(0.05)

                Section {
                    ForEach(driverLoads) { load in
                        AdminLoadRow(load: load) {
                            selectedLoad = load
                        }
                    }
                } header: {
                    HStack {
                        Text(name)
                        Spacer()
                        Text("\(driverLoads.count) loads · Pay: \(formatCurrency(totalPay))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - All loads

    @ViewBuilder
    private var allLoadsSection: some View {
        let all = loadStore.loads.sorted { $0.createdAt > $1.createdAt }
        if all.isEmpty {
            Section {
                emptyState(
                    icon: "truck.box",
                    title: "No Loads",
                    subtitle: "Submitted loads from drivers will appear here"
                )
            }
        } else {
            Section("All Loads (\(all.count))") {
                ForEach(all) { load in
                    AdminLoadRow(load: load) {
                        selectedLoad = load
                    }
                }
            }
        }
    }

    // MARK: - Paystubs

    @ViewBuilder
    private var paystubsSection: some View {
        let stubs = loadStore.paystubs.sorted { $0.generatedAt > $1.generatedAt }
        if stubs.isEmpty {
            Section {
                emptyState(
                    icon: "banknote",
                    title: "No Paystubs",
                    subtitle: "Generate paystubs from approved loads"
                )
            }
        } else {
            Section("Generated Paystubs (\(stubs.count))") {
                ForEach(stubs) { stub in
                    PaystubRowView(paystub: stub)
                }
            }
        }
    }

    // MARK: - Helpers

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Admin load row

private struct AdminLoadRow: View {
    let load: SubmittedLoad
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Load #\(load.loadNumber)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(load.driverName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    LoadStatusBadge(status: load.status)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(load.routeSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Label(load.formattedMiles, systemImage: "road.lanes")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(load.formattedGross)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(load.grossAmount == nil ? .orange : .primary)

                    if load.grossAmount != nil {
                        Text("→ \(load.formattedDriverPay)")
                            .font(.caption)
                            .foregroundStyle(.appLime)
                            .fontWeight(.semibold)
                    }
                }

                Text(load.loadDate, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ReviewLoadsView()
        .environmentObject(LoadStore())
}
