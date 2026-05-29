//
//  BillHealthScoreCard.swift
//  SacredBillTracker
//
//  At-a-glance health card for the dashboard. Renders a circular
//  progress ring + status text driven by `BillHealthScore.compute(...)`.
//

import SwiftUI

struct BillHealthScoreCard: View {

    let score: BillHealthScore
    /// v1.0.9.x — Parent-supplied tap handler. When non-nil the card
    /// renders as a button with a "View bills" affordance + chevron.
    /// nil keeps the legacy (non-tappable) presentation for callers
    /// that don't want navigation behavior.
    var onTap: (() -> Void)? = nil

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                cardBody
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the bills that need your attention")
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Theme.Color.accentGreen.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score.score) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: score.score)
                VStack(spacing: 0) {
                    Text("\(score.score)")
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("score")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: score.status.systemImage)
                        .foregroundStyle(scoreColor)
                    Text(score.status.rawValue)
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                }
                Text(detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if hasAttention && onTap != nil {
                    Text("View bills")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(Color.appAccent.opacity(0.18))
                        )
                        .foregroundStyle(Color.appAccentText)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            if hasAttention && onTap != nil {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.appHairline, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Bill health score: \(score.score) out of 100. \(score.status.rawValue). \(detail)")
    }

    private var scoreColor: Color {
        switch score.status {
        case .great:     return Theme.Color.success
        case .attention: return Theme.Color.accentGold
        case .overdue:   return Theme.Color.danger
        }
    }

    private var detail: String {
        var parts: [String] = []
        if score.overdueCount  > 0 { parts.append("\(score.overdueCount) overdue") }
        if score.dueTodayCount > 0 { parts.append("\(score.dueTodayCount) due today") }
        if score.dueSoonCount  > 0 { parts.append("\(score.dueSoonCount) due this week") }
        return parts.isEmpty ? "You're on track. No bills need attention." : parts.joined(separator: " • ")
    }

    /// True when there's at least one bill driving the warning. Used
    /// to decide whether to show the chevron + "View bills" pill.
    private var hasAttention: Bool {
        score.overdueCount + score.dueTodayCount + score.dueSoonCount > 0
    }
}
