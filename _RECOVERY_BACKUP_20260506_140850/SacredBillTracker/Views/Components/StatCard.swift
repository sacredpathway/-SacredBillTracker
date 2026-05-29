//
//  StatCard.swift
//  SacredBillTracker
//

import SwiftUI

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
            }
            Text(value)
                .font(.title2).bold()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    HStack {
        StatCard(title: "Due Today", value: "3", systemImage: "clock.fill", tint: .orange)
        StatCard(title: "Overdue",   value: "$1,240", systemImage: "exclamationmark.triangle.fill", tint: .red)
    }
    .padding()
}
