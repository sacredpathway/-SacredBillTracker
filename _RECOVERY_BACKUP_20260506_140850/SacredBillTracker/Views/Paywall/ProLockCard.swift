//
//  ProLockCard.swift
//  SacredBillTracker
//
//  A reusable "this feature is Pro" card. Drop it in place of any
//  free-tier-gated section and it'll nudge the user to upgrade.
//
//  Also ships `ProBadge` (a small "PRO" pill) for inline gating.
//

import SwiftUI

struct ProLockCard: View {

    let icon: String
    let title: String
    let message: String
    let ctaLabel: String

    /// Fired when the user taps the upgrade button. Parent owns the
    /// paywall presentation so the same paywall can be reused from
    /// anywhere in the app.
    var onUpgrade: () -> Void

    init(icon: String = "lock.fill",
         title: String,
         message: String,
         ctaLabel: String = "Upgrade to Pro",
         onUpgrade: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.message = message
        self.ctaLabel = ctaLabel
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.appAccent, Color.appAmber],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                onUpgrade()
            } label: {
                Text(ctaLabel)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [Color.appAccent, Color.appAmber],
                                       startPoint: .leading, endPoint: .trailing),
                        in: Capsule())
                    .foregroundStyle(.white)
                    .shadow(color: Color.appAccent.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

/// Small "PRO" pill, used next to feature labels.
struct ProBadge: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                LinearGradient(colors: [Color.appAccent, Color.appAmber],
                               startPoint: .leading, endPoint: .trailing),
                in: Capsule())
            .foregroundStyle(.white)
    }
}

#Preview {
    ProLockCard(
        icon: "chart.pie.fill",
        title: "Reports are a Pro feature",
        message: "Unlock cash-flow forecasts, category breakdowns, and risk alerts — for household and business.",
        onUpgrade: {}
    )
    .padding()
}
