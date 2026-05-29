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
    @EnvironmentObject private var auth: AuthService
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

    // 15/3 Paydown Plan (v1.4) — opt-in for revolving-credit bills.
    @State private var isUsing153Plan: Bool = false

    // Payment Link (v1.5) — optional URL for the user's biller / bank-pay
    // site. App only opens it in Safari; never auto-pays. Auto-normalized
    // on save: `www.example.com` is stored as `https://www.example.com`.
    @State private var paymentURLString: String = ""
    @State private var showInvalidURLAlert = false

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

                // 15/3 Paydown Plan — available on every bill regardless
                // of category (v1.4.1). The eligibility gate that
                // restricted this to credit-card / revolving-credit
                // bills was removed by request so the user can apply
                // the strategy to any recurring expense.
                paydownPlanSection

                // Partner Budgeting backend is live (v1.0.5) — surface the
                // bill-level share flag so users can move bills into the
                // Shared tab.
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

                // v1.5 — Payment Link. Tap "Pay Bill" later on the detail
                // screen to open this in Safari. App never auto-pays.
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("https://example.com/pay", text: $paymentURLString)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Payment Link")
                } footer: {
                    Text("Optional. We'll open this in Safari when you tap Pay Bill — we never auto-pay.")
                        .font(.footnote)
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if case .edit(let bill) = mode, !isPartnerOwned(bill) {
                    // Build 21 fix — Delete is hidden for partner-owned
                    // bills. The previous Delete here always silently
                    // failed because `softDelete` is scoped to
                    // `user_id = me`, which never matches a partner's
                    // owner_id. Result: the bill came back on next
                    // refresh and the user thought delete was broken.
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
            // Payment Link parser couldn't make sense of the input.
            .alert("That payment link doesn't look right",
                   isPresented: $showInvalidURLAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Enter a full URL like https://chase.com/pay, or leave the field blank.")
            }
        }
    }

    // MARK: - 15/3 Paydown Plan section

    /// Live preview built from the form's current draft values so the
    /// user sees the math update as they type.
    private var paydownPreview: PaydownPlanService.Plan? {
        guard isUsing153Plan,
              let amt = Decimal(string: amountString.replacingOccurrences(of: ",", with: ".")),
              amt > 0
        else { return nil }
        return PaydownPlanService.compute(amount: amt, dueDate: dueDate)
    }

    @ViewBuilder
    private var paydownPlanSection: some View {
        Section {
            Toggle(isOn: $isUsing153Plan) {
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use 15/3 Paydown Plan")
                        Text("50% paid 15 days early, 50% 3 days early")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let plan = paydownPreview {
                VStack(alignment: .leading, spacing: 10) {
                    paydownPreviewRow(
                        title: "First Paydown",
                        amount: plan.firstAmount,
                        date: plan.firstDate
                    )
                    Divider()
                    paydownPreviewRow(
                        title: "Final Paydown",
                        amount: plan.secondAmount,
                        date: plan.secondDate
                    )
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("15/3 Paydown Plan")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(PaydownPlanService.helperText)
                Text(PaydownPlanService.disclaimer)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.footnote)
        }
    }

    private func paydownPreviewRow(title: String, amount: Decimal, date: Date) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                Text("Due \(PaydownPlanService.longDate(date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(PaydownPlanService.currency(amount))
                .font(.subheadline.monospacedDigit())
        }
    }

    // MARK: - Helpers

    private var isEditing: Bool {
        if case .edit = mode { return true } else { return false }
    }

    /// True if the bill belongs to a connected partner — i.e. the
    /// signed-in user is viewing a shared bill they did NOT create.
    /// Edit/Delete actions on partner-owned bills always silently fail
    /// at RLS, so we hide them at the UI layer.
    private func isPartnerOwned(_ bill: Bill) -> Bool {
        guard let owner = bill.ownerUserID, let me = auth.currentUserID else { return false }
        return owner != me
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
            isUsing153Plan = b.isUsing153Plan
            paymentURLString = b.paymentURL ?? ""
        } else {
            // Add mode defaults
            category = BillCategory.categories(for: type).first ?? .rent
        }
    }

    /// Save flow with Payment Link validation + auto-normalization.
    ///   • Empty → bill saves with `paymentURL = nil`.
    ///   • Anything that looks like a URL is auto-prefixed with
    ///     `https://` when needed, then saved.
    ///   • Junk input → alert; nothing is saved.
    private func save() {
        let result = PaymentURLValidator.validate(paymentURLString)
        switch result {
        case .empty:
            persist(normalizedPaymentURL: nil)
        case .valid(let normalized):
            // Reflect the normalized value back into the field so the user
            // sees what got saved (e.g. `https://www.example.com`).
            paymentURLString = normalized
            persist(normalizedPaymentURL: normalized)
        case .invalid:
            showInvalidURLAlert = true
        }
    }

    /// Writes the bill. Called from `save()` once the Payment Link has
    /// been validated/normalized (or proven empty).
    private func persist(normalizedPaymentURL: String?) {
        guard let amt = Decimal(string: amountString.replacingOccurrences(of: ",", with: ".")) else { return }
        // v1.4.1 — eligibility gate removed; plan is available on every bill.
        let planOn = isUsing153Plan

        let finalPaymentURL = normalizedPaymentURL?.nilIfEmpty

        switch mode {
        case .add:
            var newBill = Bill(
                name: name.trimmingCharacters(in: .whitespaces),
                amount: amt,
                dueDate: dueDate,
                category: category,
                recurrence: recurrence,
                type: type,
                autoPay: autoPay,
                notes: notes,
                status: status,
                isShared: isShared,
                paymentURL: finalPaymentURL
            )
            PaydownPlanService.apply(isOn: planOn, to: &newBill)
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
            existing.paymentURL = finalPaymentURL
            // Apply (or clear) the plan AFTER amount/dueDate are
            // updated so the recompute uses the latest values.
            PaydownPlanService.apply(isOn: planOn, to: &existing)
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
