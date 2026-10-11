//
//  SubmitLoadView.swift
//  SacredBillTracker
//
//  Driver form to submit a completed load for payroll processing.
//

import SwiftUI

struct SubmitLoadView: View {

    @EnvironmentObject private var loadStore: LoadStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var loadNumber: String = ""
    @State private var pickup: String = ""
    @State private var delivery: String = ""
    @State private var loadDate: Date = Date()
    @State private var grossAmountText: String = ""
    @State private var milesText: String = ""
    @State private var notes: String = ""
    @State private var showingConfirmation = false

    private var grossAmount: Decimal? {
        guard !grossAmountText.isEmpty else { return nil }
        return Decimal(string: grossAmountText.replacingOccurrences(of: ",", with: ""))
    }

    private var miles: Double {
        Double(milesText.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var isValid: Bool {
        !loadNumber.trimmingCharacters(in: .whitespaces).isEmpty
        && !pickup.trimmingCharacters(in: .whitespaces).isEmpty
        && !delivery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    headerCard
                } header: {
                    Text("")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Section("Load Details") {
                    HStack {
                        Image(systemName: "number")
                            .foregroundStyle(.appAccent)
                            .frame(width: 24)
                        TextField("Load Number", text: $loadNumber)
                            .textContentType(.none)
                            .autocorrectionDisabled()
                    }

                    DatePicker(
                        selection: $loadDate,
                        displayedComponents: .date
                    ) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(.appAccent)
                                .frame(width: 24)
                            Text("Load Date")
                        }
                    }
                }

                Section("Route") {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.green)
                            .frame(width: 24)
                        TextField("Pickup Location", text: $pickup)
                            .textContentType(.fullStreetAddress)
                    }

                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.appDangerText)
                            .frame(width: 24)
                        TextField("Delivery Location", text: $delivery)
                            .textContentType(.fullStreetAddress)
                    }

                    HStack {
                        Image(systemName: "road.lanes")
                            .foregroundStyle(.appAccent)
                            .frame(width: 24)
                        TextField("Miles", text: $milesText)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Payment") {
                    HStack {
                        Image(systemName: "dollarsign.circle.fill")
                            .foregroundStyle(.appAccent)
                            .frame(width: 24)
                        TextField("Gross Amount (optional)", text: $grossAmountText)
                            .keyboardType(.decimalPad)
                    }

                    if let gross = grossAmount {
                        let pay = gross * Decimal(0.05)
                        HStack {
                            Image(systemName: "banknote.fill")
                                .foregroundStyle(.appLime)
                                .frame(width: 24)
                            Text("Your Pay (5%)")
                            Spacer()
                            Text(formatCurrency(pay))
                                .fontWeight(.semibold)
                                .foregroundStyle(.appLime)
                        }
                    } else {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 24)
                            Text("Gross can be added later by admin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Additional notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button(action: submitLoad) {
                        HStack {
                            Spacer()
                            Image(systemName: "paperplane.fill")
                            Text("Submit Load")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!isValid)
                    .listRowBackground(isValid ? Color.appAccent : Color.gray.opacity(0.3))
                    .foregroundStyle(isValid ? .white : .secondary)
                }
            }
            .navigationTitle("Submit Load")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Load Submitted", isPresented: $showingConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("Load #\(loadNumber) has been submitted for review. You'll see updates in My Loads.")
            }
        }
    }

    // MARK: - Header card

    private var headerCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "truck.box.fill")
                .font(.system(size: 36))
                .foregroundStyle(.appAccent)
            Text("New Load Submission")
                .font(.headline)
            Text("Submit your completed load for payroll processing")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Submit

    private func submitLoad() {
        let driverId = auth.currentUserID ?? UUID()
        let driverName = auth.displayName ?? "Driver"

        let load = SubmittedLoad(
            driverId: driverId,
            driverName: driverName,
            loadNumber: loadNumber.trimmingCharacters(in: .whitespaces),
            pickup: pickup.trimmingCharacters(in: .whitespaces),
            delivery: delivery.trimmingCharacters(in: .whitespaces),
            loadDate: loadDate,
            grossAmount: grossAmount,
            miles: miles,
            notes: notes.trimmingCharacters(in: .whitespaces)
        )

        loadStore.submitLoad(load)
        showingConfirmation = true
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }
}

#Preview {
    SubmitLoadView()
        .environmentObject(LoadStore())
        .environmentObject(AuthService.shared)
}
