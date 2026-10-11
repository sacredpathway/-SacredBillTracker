//
//  QuickAddView.swift
//  SacredBillTracker
//
//  Sheet that lets the user pick a common template or duplicate an
//  existing bill — one tap, then the normal Add/Edit form opens.
//

import SwiftUI

struct QuickAddView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var profiles: ManagedProfileStore
    @Environment(\.dismiss) private var dismiss

    /// When set, `AddEditBillView(mode: .edit(seed))` opens pre-filled.
    @State private var seededBill: Bill?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Use a template", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } header: { EmptyView() }

                Section {
                    ForEach(BillTemplates.all) { template in
                        Button {
                            let seed = template.makeBill()
                            seededBill = seed
                        } label: {
                            TemplateRow(template: template)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Templates")
                }

                if !store.bills.isEmpty {
                    Section {
                        ForEach(store.bills.prefix(8)) { bill in
                            Button {
                                // Build a copy shifted forward 1 month
                                let cal = Calendar.current
                                let next = cal.date(byAdding: .month, value: 1, to: bill.dueDate) ?? bill.dueDate
                                var copy = bill
                                copy = Bill(
                                    name: bill.name,
                                    amount: bill.amount,
                                    dueDate: next,
                                    category: bill.category,
                                    recurrence: bill.recurrence,
                                    type: bill.type,
                                    autoPay: bill.autoPay,
                                    notes: bill.notes,
                                    status: .unpaid,
                                    profileID: bill.profileID
                                )
                                seededBill = copy
                                _ = copy
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: bill.category.systemImage)
                                        .frame(width: 26)
                                        .foregroundStyle(bill.type.accentColor)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bill.name)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("Duplicate for next month")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(bill.formattedAmount)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Duplicate an existing bill")
                    }
                }

                Section {
                    NavigationLink {
                        AddEditBillView(mode: .add)
                    } label: {
                        Label("Start from scratch", systemImage: "plus")
                            .foregroundStyle(Color.appAccentText)
                    }
                }
            }
            .navigationTitle("New Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $seededBill) { bill in
                // Reuse AddEditBillView in .edit mode with a bill that
                // isn't yet in the store — Save will create it fresh.
                SeededAddView(seed: bill) { finalized in
                    store.add(finalized)
                    dismiss()
                }
                .environmentObject(profiles)
            }
        }
    }
}

private struct TemplateRow: View {
    let template: BillTemplate

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: template.systemImage)
                .frame(width: 28)
                .foregroundStyle(template.type.accentColor)
                .background(template.type.accentColor.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8))
                .padding(3)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name).font(.subheadline.bold()).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(template.category.title)
                    Text("·").foregroundStyle(.secondary)
                    Text(template.recurrence.title)
                    if template.autoPaySuggested {
                        Text("· Autopay").foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// Pre-filled add form — takes a seed Bill, lets the user confirm amount
/// and due date, then hands the finalized Bill back to a completion.
private struct SeededAddView: View {
    let seed: Bill
    var onSave: (Bill) -> Void

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var profiles: ManagedProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amountString: String
    @State private var dueDate: Date
    @State private var type: BillType
    @State private var category: BillCategory
    @State private var recurrence: RecurrenceType
    @State private var autoPay: Bool
    @State private var notes: String
    @State private var profileID: UUID?

    init(seed: Bill, onSave: @escaping (Bill) -> Void) {
        self.seed = seed
        self.onSave = onSave
        _name = State(initialValue: seed.name)
        _amountString = State(initialValue: seed.amount == 0
                              ? "" : NSDecimalNumber(decimal: seed.amount).stringValue)
        _dueDate = State(initialValue: seed.dueDate)
        _type = State(initialValue: seed.type)
        _category = State(initialValue: seed.category)
        _recurrence = State(initialValue: seed.recurrence)
        _autoPay = State(initialValue: seed.autoPay)
        _notes = State(initialValue: seed.notes)
        _profileID = State(initialValue: seed.profileID)
    }

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

                Section("Bill") {
                    TextField("Name", text: $name)
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString).keyboardType(.decimalPad)
                    }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }
                Section("Classification") {
                    Picker("Type", selection: $type) {
                        ForEach(BillType.allCases) { t in
                            Label(t.title, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .onChange(of: type) { _, newValue in
                        let allowed = BillCategory.categories(for: newValue)
                        if !allowed.contains(category) { category = allowed.first ?? .other }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(BillCategory.categories(for: type)) { c in
                            Label(c.title, systemImage: c.systemImage).tag(c)
                        }
                    }
                }
                Section("Schedule") {
                    Picker("Recurrence", selection: $recurrence) {
                        ForEach(RecurrenceType.allCases) { r in Text(r.title).tag(r) }
                    }
                    Toggle("Auto-Pay", isOn: $autoPay)
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical).lineLimit(3...6)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let amt = Decimal(string: amountString.replacingOccurrences(of: ",", with: ".")) ?? 0
                        let bill = Bill(
                            name: name.trimmingCharacters(in: .whitespaces),
                            amount: amt,
                            dueDate: dueDate,
                            category: category,
                            recurrence: recurrence,
                            type: type,
                            autoPay: autoPay,
                            notes: notes,
                            status: .unpaid,
                            profileID: profileID ?? profiles.context.writeProfileID
                        )
                        onSave(bill)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty
                              || (Decimal(string: amountString.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                }
            }
            .onAppear {
                if profileID == nil {
                    profileID = profiles.context.writeProfileID
                }
            }
        }
    }
}
