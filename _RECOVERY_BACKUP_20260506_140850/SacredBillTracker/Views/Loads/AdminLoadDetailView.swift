//
//  AdminLoadDetailView.swift
//  SacredBillTracker
//
//  Admin detail view for a submitted load. Allows editing gross amount,
//  miles, approving, and rejecting.
//

import SwiftUI

struct AdminLoadDetailView: View {

    let load: SubmittedLoad

    @EnvironmentObject private var loadStore: LoadStore
    @Environment(\.dismiss) private var dismiss

    @State private var grossAmountText: String = ""
    @State private var milesText: String = ""
    @State private var rejectReason: String = ""
    @State private var showingRejectConfirm = false

    private var grossAmount: Decimal? {
        guard !grossAmountText.isEmpty else { return nil }
        return Decimal(string: grossAmountText.replacingOccurrences(of: ",", with: ""))
    }

    private var miles: Double {
        Double(milesText.replacingOccurrences(of: ",", with: "")) ?? load.miles
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Load Info") {
                    DetailRow(label: "Load #", value: load.loadNumber)
                    DetailRow(label: "Driver", value: load.driverName)
                    DetailRow(label: "Date", value: load.loadDate.formatted(date: .abbreviated, time: .omitted))
                    DetailRow(label: "Status", value: load.status.title, color: load.status.color)
                }

                Section("Route") {
                    DetailRow(label: "Pickup", value: load.pickup)
                    DetailRow(label: "Delivery", value: load.delivery)

                    HStack {
                        Text("Miles")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if load.status == .submitted {
                            TextField("Miles", text: $milesText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        } else {
                            Text(load.formattedMiles)
                                .fontWeight(.medium)
                        }
                    }
                }

                Section("Payment") {
                    if load.status == .submitted {
                        HStack {
                            Text("Gross Amount")
                                .foregroundStyle(.secondary)
                            Spacer()
                            TextField("Enter amount", text: $grossAmountText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                        }

                        if let gross = grossAmount {
                            let pay = gross * Decimal(0.05)
                            HStack {
                                Text("Driver Pay (5%)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(formatCurrency(pay))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.appLime)
                            }
                        }
                    } else {
                        DetailRow(label: "Gross", value: load.formattedGross)
                        DetailRow(label: "Driver Pay (5%)", value: load.formattedDriverPay, color: .appLime)
                    }
                }

                if !load.notes.isEmpty {
                    Section("Driver Notes") {
                        Text(load.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Timestamps") {
                    DetailRow(label: "Submitted", value: load.createdAt.formatted(date: .abbreviated, time: .shortened))
                    DetailRow(label: "Updated", value: load.updatedAt.formatted(date: .abbreviated, time: .shortened))
                }

                if load.status == .submitted {
                    Section {
                        // Save edits button
                        Button {
                            saveEdits()
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "square.and.arrow.down")
                                Text("Save Changes")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.appAccent.opacity(0.15))
                        .foregroundStyle(.appAccent)

                        // Approve button
                        Button {
                            saveEdits()
                            if let updatedLoad = loadStore.loads.first(where: { $0.id == load.id }),
                               updatedLoad.grossAmount != nil {
                                loadStore.approveLoad(updatedLoad)
                                dismiss()
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                Text("Approve Load")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(grossAmount == nil && load.grossAmount == nil)
                        .listRowBackground(
                            (grossAmount != nil || load.grossAmount != nil)
                            ? Color.green.opacity(0.15)
                            : Color.gray.opacity(0.1)
                        )
                        .foregroundStyle(
                            (grossAmount != nil || load.grossAmount != nil) ? .green : .secondary
                        )

                        // Reject button
                        Button {
                            showingRejectConfirm = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "xmark.circle.fill")
                                Text("Reject Load")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .listRowBackground(Color.red.opacity(0.15))
                        .foregroundStyle(.red)
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
            .onAppear {
                if let gross = load.grossAmount {
                    grossAmountText = "\(gross)"
                }
                milesText = "\(load.miles)"
            }
            .alert("Reject Load", isPresented: $showingRejectConfirm) {
                TextField("Reason (optional)", text: $rejectReason)
                Button("Reject", role: .destructive) {
                    loadStore.rejectLoad(load, reason: rejectReason)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to reject Load #\(load.loadNumber)?")
            }
        }
    }

    private func saveEdits() {
        if let gross = grossAmount {
            loadStore.updateGrossAmount(loadId: load.id, amount: gross)
        }
        let newMiles = miles
        if newMiles != load.miles {
            loadStore.updateMiles(loadId: load.id, miles: newMiles)
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

// Re-use the DetailRow from MyLoadsView (already defined there as private,
// so we define a matching internal version for admin views).
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
    AdminLoadDetailView(
        load: SubmittedLoad(
            driverId: UUID(),
            driverName: "John Doe",
            loadNumber: "LD-1001",
            pickup: "Dallas, TX",
            delivery: "Houston, TX",
            grossAmount: 4500,
            miles: 240
        )
    )
    .environmentObject(LoadStore())
}
