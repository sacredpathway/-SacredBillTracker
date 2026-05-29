//
//  MyLoadsView.swift
//  SacredBillTracker
//
//  Driver's view of their submitted loads. Shows status, route, and pay info.
//

import SwiftUI

struct MyLoadsView: View {

    @EnvironmentObject private var loadStore: LoadStore
    @EnvironmentObject private var auth: AuthService

    @State private var showingSubmitSheet = false
    @State private var statusFilter: LoadStatusFilter = .all
    @State private var selectedLoad: SubmittedLoad?

    private var driverId: UUID {
        auth.currentUserID ?? UUID()
    }

    private var myLoads: [SubmittedLoad] {
        let all = loadStore.loads(forDriver: driverId)
        switch statusFilter {
        case .all:       return all
        case .specific(let s): return all.filter { $0.status == s }
        }
    }

    private var myPaystubs: [Paystub] {
        loadStore.paystubs(forDriver: driverId)
    }

    var body: some View {
        NavigationStack {
            List {
                // Summary card
                summarySection

                // Status filter
                Section {
                    Picker("Filter", selection: $statusFilter) {
                        Text("All").tag(LoadStatusFilter.all)
                        ForEach(LoadStatus.driverVisible) { status in
                            Text(status.title).tag(LoadStatusFilter.specific(status))
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                // Loads list
                if myLoads.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "truck.box")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("No Loads Yet")
                                .font(.headline)
                            Text("Tap + to submit your first load")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }
                } else {
                    Section("Loads (\(myLoads.count))") {
                        ForEach(myLoads) { load in
                            LoadRowView(load: load)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedLoad = load }
                        }
                        .onDelete { offsets in
                            let toDelete = offsets.map { myLoads[$0] }
                            for load in toDelete where load.status == .submitted {
                                loadStore.deleteLoad(load)
                            }
                        }
                    }
                }

                // Paystubs section
                if !myPaystubs.isEmpty {
                    Section("Pay History") {
                        ForEach(myPaystubs) { stub in
                            PaystubRowView(paystub: stub)
                        }
                    }
                }
            }
            .navigationTitle("My Loads")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSubmitSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSubmitSheet) {
                SubmitLoadView()
            }
            .sheet(item: $selectedLoad) { load in
                LoadDetailSheet(load: load)
            }
            .refreshable {
                await loadStore.reload()
            }
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        Section {
            let allLoads = loadStore.loads(forDriver: driverId)
            let submitted = allLoads.filter { $0.status == .submitted }.count
            let approved = allLoads.filter { $0.status == .approved }.count
            let totalPaid = myPaystubs.reduce(Decimal(0)) { $0 + $1.driverPayAmount }

            HStack(spacing: 16) {
                SummaryPill(value: "\(allLoads.count)", label: "Total", color: .appAccent)
                SummaryPill(value: "\(submitted)", label: "Pending", color: .orange)
                SummaryPill(value: "\(approved)", label: "Approved", color: .appLime)
                SummaryPill(
                    value: formatCurrency(totalPaid),
                    label: "Earned",
                    color: .appAccent
                )
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.maximumFractionDigits = 0
        fmt.locale = .current
        return fmt.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// MARK: - Status filter enum

enum LoadStatusFilter: Hashable {
    case all
    case specific(LoadStatus)
}

// MARK: - Summary pill

private struct SummaryPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Load row

struct LoadRowView: View {
    let load: SubmittedLoad

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Load #\(load.loadNumber)")
                    .font(.headline)
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

                if load.driverPay != nil {
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
}

// MARK: - Status badge

struct LoadStatusBadge: View {
    let status: LoadStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.caption2)
            Text(status.title)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15))
        .foregroundStyle(status.color)
        .clipShape(Capsule())
    }
}

// MARK: - Paystub row

struct PaystubRowView: View {
    let paystub: Paystub

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "banknote.fill")
                    .foregroundStyle(.appAccent)
                Text(paystub.payPeriodLabel)
                    .font(.subheadline)
                Spacer()
                Text(paystub.formattedPay)
                    .font(.headline)
                    .foregroundStyle(.appLime)
            }
            HStack {
                Text("\(paystub.loadCount) loads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("Gross: \(paystub.formattedGross)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Load detail sheet

struct LoadDetailSheet: View {
    let load: SubmittedLoad
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Load Info") {
                    DetailRow(label: "Load #", value: load.loadNumber)
                    DetailRow(label: "Date", value: load.loadDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow(label: "Status", value: load.status.title, color: load.status.color)
                }

                Section("Route") {
                    DetailRow(label: "Pickup", value: load.pickup)
                    DetailRow(label: "Delivery", value: load.delivery)
                    DetailRow(label: "Miles", value: load.formattedMiles)
                }

                Section("Payment") {
                    DetailRow(label: "Gross", value: load.formattedGross)
                    DetailRow(label: "Your Pay (5%)", value: load.formattedDriverPay, color: .appLime)
                }

                if !load.notes.isEmpty {
                    Section("Notes") {
                        Text(load.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Load #\(load.loadNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    MyLoadsView()
        .environmentObject(LoadStore())
        .environmentObject(AuthService.shared)
}
