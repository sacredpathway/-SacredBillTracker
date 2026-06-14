//
//  AddEditIncomeView.swift
//  SacredBillTracker
//
//  Premium, Apple-native sheet for adding or editing a single
//  WeeklyIncome entry. Mirrors the visual style used by QuickAddView /
//  AddEditBillView so the new feature feels native to the existing app.
//
//  v1.0.9 — Add-Income flow is now:
//    Amount → Date → Source Name → Type (Business/Personal) → Notes
//
//  The underlying model still carries `weekStart` / `weekEnd` for
//  back-compat with the weekly / 30-day / monthly calculations, so when
//  the user picks a single date we collapse the range (start = end =
//  that day).
//

import SwiftUI

struct AddEditIncomeView: View {

    @EnvironmentObject private var store: IncomeStore
    @EnvironmentObject private var profiles: ManagedProfileStore
    @Environment(\.dismiss) private var dismiss

    // MARK: - Editing state

    /// nil = new entry, non-nil = editing an existing one.
    private let existing: WeeklyIncome?

    @State private var amountString: String
    @State private var date: Date
    @State private var sourceName: String
    @State private var type: IncomeType
    @State private var note: String
    @State private var profileID: UUID?

    @State private var showDeleteConfirm: Bool = false

    // MARK: - Init

    init(existing: WeeklyIncome? = nil) {
        self.existing = existing
        if let e = existing {
            _amountString = State(initialValue: Self.formatAmountForEdit(e.amount))
            _date         = State(initialValue: e.weekStart)
            _sourceName   = State(initialValue: e.sourceName)
            _type         = State(initialValue: e.type)
            _note         = State(initialValue: e.note)
            _profileID    = State(initialValue: e.profileID)
        } else {
            _amountString = State(initialValue: "")
            _date         = State(initialValue: Date())
            _sourceName   = State(initialValue: "")
            _type         = State(initialValue: .business)
            _note         = State(initialValue: "")
            _profileID    = State(initialValue: nil)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                if profiles.canUseManagedProfiles && profiles.profiles.count > 1 {
                    Section(header: Text("Profile")) {
                        Picker("Managed Account", selection: Binding(
                            get: { profileID ?? profiles.context.writeProfileID ?? profiles.profiles.first?.id },
                            set: { profileID = $0 }
                        )) {
                            ForEach(profiles.profiles) { profile in
                                Label(profile.name, systemImage: profile.iconSystemName)
                                    .tag(Optional(profile.id))
                            }
                        }
                    }
                }

                Section("Amount earned") {
                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                            .multilineTextAlignment(.leading)
                    }
                }

                Section("Date") {
                    DatePicker("Date",
                               selection: $date,
                               displayedComponents: .date)
                }

                Section("Source name") {
                    TextField("e.g. BrokerX, Side hustle, Settlement",
                              text: $sourceName)
                        .textInputAutocapitalization(.words)
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(IncomeType.allCases) { t in
                            Label(t.title, systemImage: t.systemImage)
                                .tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notes (optional)") {
                    TextField("Anything extra — load #, broker name, miles…",
                              text: $note,
                              axis: .vertical)
                        .lineLimit(1...3)
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete entry", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Income" : "Edit Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { save() }
                        .disabled(!isValid)
                }
            }
            .confirmationDialog(
                "Delete this income entry?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteAndDismiss() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear {
                if profileID == nil {
                    profileID = existing?.profileID ?? profiles.context.writeProfileID
                }
            }
        }
    }

    // MARK: - Validation & save

    private var isValid: Bool {
        guard let amt = Decimal(string: cleanedAmountString), amt > 0 else { return false }
        return !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cleanedAmountString: String {
        amountString
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private func save() {
        guard let amount = Decimal(string: cleanedAmountString) else { return }

        // Collapse the single Date into the legacy weekStart/weekEnd
        // range so historical weekly / 30-day / monthly calculations
        // (and the CPA PDF) keep working unchanged.
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        let dayEnd = cal.date(
            bySettingHour: 23, minute: 59, second: 59,
            of: dayStart
        ) ?? date

        let trimmedSource = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            var updated = existing
            updated.amount = amount
            updated.weekStart = dayStart
            updated.weekEnd = dayEnd
            updated.type = type
            updated.sourceName = trimmedSource
            updated.note = trimmedNote
            updated.profileID = profileID ?? profiles.context.writeProfileID
            updated.ownerUserID = profiles.context.ownerID
            store.update(updated)
        } else {
            let new = WeeklyIncome(
                amount: amount,
                weekStart: dayStart,
                weekEnd: dayEnd,
                type: type,
                sourceName: trimmedSource,
                note: trimmedNote,
                profileID: profileID ?? profiles.context.writeProfileID,
                ownerUserID: profiles.context.ownerID
            )
            store.add(new)
        }
        dismiss()
    }

    private func deleteAndDismiss() {
        guard let existing else { return }
        store.delete(existing)
        dismiss()
    }

    // MARK: - Formatters

    private var currencySymbol: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.currencySymbol ?? "$"
    }

    private static func formatAmountForEdit(_ amount: Decimal) -> String {
        // Plain decimal, no currency symbol, no thousand separators —
        // matches what a TextField with .decimalPad expects.
        let n = amount as NSDecimalNumber
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.usesGroupingSeparator = false
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        return fmt.string(from: n) ?? "\(amount)"
    }
}

#Preview {
    AddEditIncomeView()
        .environmentObject(IncomeStore())
        .environmentObject(ManagedProfileStore.shared)
}
