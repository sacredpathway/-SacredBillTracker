//
//  BillRowView.swift
//  SacredBillTracker
//

import SwiftUI

struct BillRowView: View {
    let bill: Bill
    var maxUnpaidAmount: Decimal? = nil

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
                    Text(bill.name)
                        .font(.headline)
                        .lineLimit(1)
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
        }
        .padding(.vertical, 4)
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
        if bill.isOverdue { return .red }
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
        case .overdue:       return .red
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
