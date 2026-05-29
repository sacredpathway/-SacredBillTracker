//
//  GeneratePaystubView.swift
//  SacredBillTracker
//
//  Admin view to roll approved loads into paystubs at pay period end.
//  Groups approved loads by driver, shows totals, and generates paystubs.
//

import SwiftUI

struct GeneratePaystubView: View {

    @EnvironmentObject private var loadStore: LoadStore
    @Environment(\.dismiss) private var dismiss

    @State private var payPeriodStart: Date = Calendar.current.date(
        byAdding: .day, value: -14, to: Date()
    ) ?? Date()
    @State private var payPeriodEnd: Date = Date()
    @State private var generatedStubs: [Paystub] = []
    @State private var showingConfirmation = false
    @State private var showingResult = false

    private var eligibleLoads: [SubmittedLoad] {
        loadStore.approvedLoads.filter {
            $0.loadDate >= payPeriodStart && $0.loadDate <= payPeriodEnd
        }
    }

    private var groupedByDriver: [(id: UUID, name: String, loads: [SubmittedLoad])] {
        let grouped = Dictionary(grouping: eligibleLoads, by: \.driverId)
        return grouped.map { (id, loads) in
            (id: id, name: loads.first?.driverName ?? "Unknown", loads: loads)
        }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pay Period") {
                    DatePicker("Start Date", selection: $payPeriodStart, displayedComponents: .date)
                    DatePicker("End Date", selection: $payPeriodEnd, displayedComponents: .date)
                }

                if eligibleLoads.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("No Approved Loads")
                                .font(.headline)
                            Text("No approved loads found in this pay period")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    }
                } else {
                    // Summary per driver
                    ForEach(groupedByDriver, id: \.id) { driver in
                        let totalGross = driver.loads.compactMap(\.grossAmount).reduce(Decimal(0), +)
                        let totalPay = totalGross * Decimal(0.05)
                        let totalMiles = driver.loads.reduce(0.0) { $0 + $1.miles }

                        Section {
                            ForEach(driver.loads) { load in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Load #\(load.loadNumber)")
                                            .font(.subheadline)
                                        Text(load.routeSummary)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(load.formattedGross)
                                        .font(.subheadline)
                                }
                            }

                            // Driver totals
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Loads")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(driver.loads.count)")
                                        .fontWeight(.medium)
                                }
                                HStack {
                                    Text("Total Miles")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f mi", totalMiles))
                                        .fontWeight(.medium)
                                }
                                HStack {
                                    Text("Total Gross")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(formatCurrency(totalGross))
                                        .fontWeight(.medium)
                                }
                                Divider()
                                HStack {
                                    Text("Driver Pay (5%)")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(formatCurrency(totalPay))
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.appLime)
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            HStack {
                                Image(systemName: "person.fill")
                                Text(driver.name)
                            }
                        }
                    }

                    // Generate button
                    Section {
                        Button {
                            showingConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "banknote.fill")
                                Text("Generate Paystubs (\(groupedByDriver.count))")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.appAccent)
                        .foregroundStyle(.white)
                    }
                }
            }
            .navigationTitle("Generate Paystubs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Generate Paystubs",
                isPresented: $showingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Generate \(groupedByDriver.count) Paystub(s)") {
                    generatePaystubs()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will roll \(eligibleLoads.count) approved load(s) into paystubs and mark them as paid. This action cannot be undone.")
            }
            .alert("Paystubs Generated", isPresented: $showingResult) {
                Button("Done") { dismiss() }
            } message: {
                Text("\(generatedStubs.count) paystub(s) created successfully.")
            }
        }
    }

    private func generatePaystubs() {
        generatedStubs = loadStore.generateAllPaystubs(
            payPeriodStart: payPeriodStart,
            payPeriodEnd: payPeriodEnd
        )
        showingResult = true
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    GeneratePaystubView()
        .environmentObject(LoadStore())
}
