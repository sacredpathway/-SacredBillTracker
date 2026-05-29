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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                Spacer()
            }
            // Primary number — high-contrast, larger, monospaced so the
            // figures align and read instantly.
            Text(value)
                .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            // Label — full primary contrast (was .secondary, which read as
            // washed-out white-on-gray on the card).
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
    }
}

#Preview {
    HStack {
        StatCard(title: "Due Today", value: "3", systemImage: "clock.fill", tint: .orange)
        StatCard(title: "Overdue",   value: "$1,240", systemImage: "exclamationmark.triangle.fill", tint: .red)
    }
    .padding()
}
