//
//  BillDetailView.swift
//  SacredBillTracker
//

import SwiftUI

struct BillDetailView: View {

    @EnvironmentObject private var store: BillStore
    @Environment(\.openURL) private var openURL
    @State private var showEdit = false

    // v1.6 — Confirm before leaving the app to a biller's payment site.
    // Apple-compliant UX: the user explicitly approves the hand-off so
    // Sacred Bill Tracker is never mistaken for processing the payment.
    @State private var showLeaveAppConfirm = false
    @State private var pendingPayURL: URL?

    let bill: Bill

    // Read the latest version from the store so edits propagate instantly.
    private var currentBill: Bill {
        store.bills.first(where: { $0.id == bill.id }) ?? bill
    }

    var body: some View {
        let b = currentBill
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(for: b)
                amountCard(for: b)
                detailsCard(for: b)
                if b.isUsing153Plan {
                    paydownPlanCard(for: b)
                }
                if let payURL = PaymentURLValidator.openableURL(from: b.paymentURL) {
                    payBillButton(url: payURL)
                }
                actionButtons(for: b)
                if !b.notes.isEmpty {
                    notesCard(for: b)
                }
            }
            .padding()
        }
        .background(Theme.Color.background)
        .navigationTitle(b.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddEditBillView(mode: .edit(b))
        }
    }

    // MARK: - Sections

    private func header(for b: Bill) -> some View {
        HStack(spacing: 12) {
            Image(systemName: b.category.systemImage)
                .font(.title2)
                .foregroundStyle(b.type.accentColor)
                .frame(width: 52, height: 52)
                .background(b.type.accentColor.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(b.category.title).font(.headline)
                Label(b.type.title, systemImage: b.type.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusBadge(status: b.effectiveStatus)
        }
    }

    private func amountCard(for b: Bill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Amount Due")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(b.formattedAmount)
                .font(.largeTitle.bold().monospacedDigit())
            Text(b.dueDate.mediumFormatted)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailsCard(for b: Bill) -> some View {
        VStack(spacing: 0) {
            detailRow("Recurrence", value: b.recurrence.title, icon: "repeat")
            Divider()
            detailRow("Auto-Pay", value: b.autoPay ? "On" : "Off",
                      icon: b.autoPay ? "checkmark.circle.fill" : "xmark.circle")
            Divider()
            detailRow("Category", value: b.category.title, icon: b.category.systemImage)
            Divider()
            detailRow("Type", value: b.type.title, icon: b.type.systemImage)
        }
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// "Pay Bill" CTA — Sacred-gold brand button. Only opens the user's
    /// saved URL in Safari; the app never processes payments internally.
    /// Hidden completely when `bill.paymentURL` is nil/invalid (the
    /// caller already gates this behind `openableURL(from:)`).
    ///
    /// v1.6 — Tapping the button now arms a "Leave Sacred Bill Tracker?"
    /// confirmation dialog. Safari only opens after the user explicitly
    /// taps "Open Website". The button is disabled if the validated URL
    /// somehow falls back to nil between render and tap (defense in
    /// depth — the gating `openableURL(from:)` already filters invalid
    /// links upstream).
    private func payBillButton(url: URL) -> some View {
        Button {
            pendingPayURL = url
            showLeaveAppConfirm = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "safari.fill")
                Text("Pay Bill")
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.subheadline)
                    .opacity(0.85)
            }
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.Color.accentGold))
        .disabled(PaymentURLValidator.openableURL(from: currentBill.paymentURL) == nil)
        .accessibilityLabel("Pay this bill")
        .accessibilityHint("Opens your saved payment link in Safari after a confirmation. The app does not process payments.")
        .accessibilityAddTraits(.isLink)
        .confirmationDialog(
            "Leave Sacred Bill Tracker?",
            isPresented: $showLeaveAppConfirm,
            titleVisibility: .visible,
            presenting: pendingPayURL
        ) { url in
            Button("Open Website") {
                openURL(url)
                pendingPayURL = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPayURL = nil
            }
        } message: { _ in
            Text("This opens the biller's payment website. Sacred Bill Tracker tracks bills only and does not process payments.")
        }
    }

    private func actionButtons(for b: Bill) -> some View {
        HStack(spacing: 12) {
            if b.status == .paid {
                Button {
                    store.markUnpaid(b)
                } label: {
                    Label("Mark Unpaid", systemImage: "clock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button {
                    store.markPaid(b)
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - 15/3 Paydown Plan card

    @ViewBuilder
    private func paydownPlanCard(for b: Bill) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "creditcard.and.123")
                    .foregroundStyle(.tint)
                Text("15/3 Paydown Plan Active")
                    .font(.headline)
            }

            paydownRow(
                title: "First Paydown",
                amount: b.firstPaydownAmount,
                date: b.firstPaydownDate
            )
            Divider()
            paydownRow(
                title: "Final Paydown",
                amount: b.secondPaydownAmount,
                date: b.secondPaydownDate
            )

            Text(PaydownPlanService.disclaimer)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func paydownRow(title: String, amount: Decimal?, date: Date?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.semibold)
                if let date {
                    Text("Due \(PaydownPlanService.longDate(date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let amount {
                Text(PaydownPlanService.currency(amount))
                    .font(.subheadline.monospacedDigit())
            }
        }
    }

    private func notesCard(for b: Bill) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(b.notes)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BillDetailView(bill: SampleData.bills()[0])
    }
    .environmentObject(BillStore())
}
#endif
