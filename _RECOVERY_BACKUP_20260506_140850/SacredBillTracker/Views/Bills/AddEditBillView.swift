//
//  AddEditBillView.swift
//  SacredBillTracker
//
//  Form used both to add a new bill and edit an existing one.
//

import SwiftUI

struct AddEditBillView: View {

    enum Mode: Equatable {
        case add
        case edit(Bill)
    }

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    // Form state
    @State private var name: String = ""
    @State private var amountString: String = ""
    @State private var dueDate: Date = Date()
    @State private var type: BillType = .household
    @State private var category: BillCategory = .rent
    @State private var recurrence: RecurrenceType = .monthly
    @State private var autoPay: Bool = false
    @State private var notes: String = ""
    @State private var status: PaymentStatus = .unpaid
    @State private var isShared: Bool = false

    @State private var showDeleteConfirm = false
    @State private var showPaywall = false

    init(mode: Mode) {
        self.mode = mode
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name", text: $name)
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("0.00", text: $amountString)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                }

                Section {
                    Picker("Type", selection: $type) {
                        ForEach(BillType.allCases) { t in
                            HStack {
                                Label(t.title, systemImage: t.systemImage)
                                if t == .business && !subs.isPro && !FreeTierLimits.allowBusinessBills {
                                    Spacer()
                                    ProBadge()
                                }
                            }
                            .tag(t)
                        }
                    }
                    .onChange(of: type) { oldValue, newValue in
                        // Block switching to business bills on free tier.
                        if newValue == .business
                            && !subs.isPro
                            && !FreeTierLimits.allowBusinessBills {
                            type = oldValue
                            showPaywall = true
                            return
                        }
                        let allowed = BillCategory.categories(for: newValue)
                        if !allowed.contains(category) {
                            category = allowed.first ?? .other
                        }
                    }

                    Picker("Category", selection: $category) {
                        ForEach(BillCategory.categories(for: type)) { c in
                            Label(c.title, systemImage: c.systemImage).tag(c)
                        }
                    }
                } header: {
                    Text("Classification")
                } footer: {
                    if type == .household && !subs.isPro && !FreeTierLimits.allowBusinessBills {
                        Text("Business tracking is a Pro feature.")
                            .font(.footnote)
                    }
                }

                Section("Schedule") {
                    Picker("Recurrence", selection: $recurrence) {
                        ForEach(RecurrenceType.allCases) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    Toggle("Auto-Pay", isOn: $autoPay)
                }

                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach([PaymentStatus.unpaid, .paid], id: \.self) { s in
                            Text(s.title).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                #if DEBUG
                // Partner Budgeting destination is hidden from Release, so
                // the bill-level share flag has nowhere to surface — keep
                // the toggle compiled in for dev work, hide from shipping
                // builds. Bill.isShared still defaults to false so the
                // model stays compatible.
                Section {
                    Toggle(isOn: $isShared) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.2.fill")
                                .foregroundStyle(Color.appHousehold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share with partner")
                                Text("Visible in the Shared Bills tab")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    if !PartnerService.isBackendReady {
                        Text("Partner sync is coming soon — this flag is saved on your device for now.")
                            .font(.footnote)
                    }
                }
                #endif

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if case .edit(let bill) = mode {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete Bill", systemImage: "trash")
                        }
                    }
                    .confirmationDialog("Delete “\(bill.name)”?",
                                        isPresented: $showDeleteConfirm,
                                        titleVisibility: .visible) {
                        Button("Delete", role: .destructive) {
                            store.delete(bill)
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Bill" : "New Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: loadMode)
            .paywallSheet(isPresented: $showPaywall,
                          reason: "Business bill tracking is a Pro feature.")
        }
    }

    // MARK: - Helpers

    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }

    private var canSave: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let amt = Decimal(string: amountString.replacingOccurrences(of: ",", with: "."))
        return !trimmed.isEmpty && amt != nil && (amt ?? 0) > 0
    }

    private func loadMode() {
        if case .edit(let b) = mode {
            name = b.name
            amountString = NSDecimalNumber(decimal: b.amount).stringValue
            dueDate = b.dueDate
            type = b.type
            category = b.category
            recurrence = b.recurrence
            autoPay = b.autoPay
            notes = b.notes
            status = b.status
            isShared = b.isShared
        } else {
            // Add mode defaults
            category = BillCategory.categories(for: type).first ?? .rent
        }
    }

    private func save() {
        guard let amt = Decimal(string: amountString.replacingOccurrences(of: ",", with: ".")) else { return }
        switch mode {
        case .add:
            let newBill = Bill(
                name: name.trimmingCharacters(in: .whitespaces),
                amount: amt,
                dueDate: dueDate,
                category: category,
                recurrence: recurrence,
                type: type,
                autoPay: autoPay,
                notes: notes,
                status: status,
                isShared: isShared
            )
            store.add(newBill)
        case .edit(var existing):
            existing.name = name.trimmingCharacters(in: .whitespaces)
            existing.amount = amt
            existing.dueDate = dueDate
            existing.category = category
            existing.recurrence = recurrence
            existing.type = type
            existing.autoPay = autoPay
            existing.notes = notes
            existing.status = status
            existing.isShared = isShared
            store.update(existing)
        }
        dismiss()
    }
}

#if DEBUG
#Preview("Add") {
    AddEditBillView(mode: .add)
        .environmentObject(BillStore())
        .environmentObject(SubscriptionManager())
}

#Preview("Edit") {
    AddEditBillView(mode: .edit(SampleData.bills()[0]))
        .environmentObject(BillStore())
        .environmentObject(SubscriptionManager())
}
#endif
