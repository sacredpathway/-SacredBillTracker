//
//  BillRowView.swift
//  SacredBillTracker
//

import SwiftUI

struct BillRowView: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.openURL) private var openURL
    let bill: Bill
    var maxUnpaidAmount: Decimal? = nil

    /// True when this row was loaded from Supabase and the owner is
    /// someone other than the signed-in user — i.e. a partner-shared
    /// bill. We badge the row so users see at a glance "this is from
    /// my partner; I can't edit it."
    private var isPartnerBill: Bool {
        guard let owner = bill.ownerUserID, let me = auth.currentUserID else { return false }
        return owner != me
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Category icon
                Image(systemName: bill.category.systemImage)
                    .font(.headline)
                    .foregroundStyle(bill.type.accentColor)
                    .frame(width: 40, height: 40)
                    .background(bill.type.accentColor.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(bill.name)
                            .font(.headline)
                            .lineLimit(1)
                        if isPartnerBill {
                            Label("Shared by Partner", systemImage: "person.2.fill")
                                .labelStyle(.iconOnly)
                                .font(.caption2)
                                .foregroundStyle(Color.appHouseholdText)
                                .accessibilityLabel("Shared by partner")
                        }
                    }
                    HStack(spacing: 6) {
                        Text(bill.category.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("•").foregroundStyle(.secondary)
                        Text(dueCopy)
                            .font(.caption)
                            .foregroundStyle(dueTint)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(bill.formattedAmount)
                        .font(.headline.monospacedDigit())
                    StatusBadge(status: bill.effectiveStatus)
                }
            }

            let tags = bill.insights(maxAmountInScope: maxUnpaidAmount)
            if !tags.isEmpty {
                InsightTagRow(tags: tags)
            }

            // v1.5 — Pay Bill chip. Only shown when the user saved a
            // payment URL. Tapping opens Safari, NOT the row's nav link.
            if let payURL = PaymentURLValidator.openableURL(from: bill.paymentURL) {
                payBillChip(url: payURL)
                    .padding(.leading, 52)  // align past category icon
            }
        }
        .padding(.vertical, 4)
        // v1.5 — quick-pay from long-press / right-click anywhere on
        // the row. Mirrors the chip behavior so the user doesn't have
        // to aim for the small target.
        .contextMenu {
            if let payURL = PaymentURLValidator.openableURL(from: bill.paymentURL) {
                Button {
                    openURL(payURL)
                } label: {
                    Label("Pay Bill", systemImage: "arrow.up.right.square.fill")
                }
            }
        }
    }

    /// Compact gold chip — Pay Bill quick action that lives on the row.
    /// `.buttonStyle(.borderless)` is the standard SwiftUI trick to make
    /// a button inside a List row receive taps without swallowing the
    /// row's NavigationLink.
    private func payBillChip(url: URL) -> some View {
        Button {
            openURL(url)
        } label: {
            Label {
                Text("Pay Bill")
            } icon: {
                Image(systemName: "arrow.up.right.square.fill")
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(Theme.Color.accentGold)
            .background(Theme.Color.accentGold.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Pay \(bill.name)")
        .accessibilityHint("Opens this bill's payment link in Safari.")
        .accessibilityAddTraits(.isLink)
    }

    private var dueCopy: String {
        if bill.isPaid { return "Paid • \(bill.dueDate.mediumFormatted)" }
        if bill.isOverdue {
            return "\(bill.daysOverdue) day\(bill.daysOverdue == 1 ? "" : "s") overdue"
        }
        if bill.isDueToday { return "Due today" }
        if bill.daysUntilDue == 1 { return "Due tomorrow" }
        if bill.daysUntilDue <= 6 { return "In \(bill.daysUntilDue) days" }
        return bill.dueDate.mediumFormatted
    }

    private var dueTint: Color {
        if bill.isPaid { return .secondary }
        if bill.isOverdue { return .appDangerText }
        if bill.daysUntilDue <= 3 { return .appAmber }
        return .secondary
    }
}

struct StatusBadge: View {
    let status: PaymentStatus

    var body: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(status.color)
            .background(status.color.opacity(0.15), in: Capsule())
    }
}

/// Compact horizontal row of insight tags shown beneath a bill row.
struct InsightTagRow: View {
    let tags: [BillInsight]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { tag in
                    Label(tag.title, systemImage: tag.systemImage)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .foregroundStyle(tint(for: tag))
                        .background(tint(for: tag).opacity(0.12), in: Capsule())
                }
            }
            .padding(.leading, 52)  // align past the category icon
        }
        .scrollDisabled(tags.count <= 3)
    }

    private func tint(for tag: BillInsight) -> Color {
        switch tag {
        case .overdue:       return .appDangerText
        case .dueSoon:       return .appAmber
        case .highestAmount: return .appAccent
        case .autoPay:       return .appHousehold
        case .paidRecently:  return .green
        case .recurring:     return .appAccent
        }
    }
}

#if DEBUG
#Preview {
    List {
        BillRowView(bill: SampleData.bills()[0], maxUnpaidAmount: 1850)
        BillRowView(bill: SampleData.bills()[1], maxUnpaidAmount: 1850)
        BillRowView(bill: SampleData.bills()[9], maxUnpaidAmount: 1850)
    }
}
#endif
