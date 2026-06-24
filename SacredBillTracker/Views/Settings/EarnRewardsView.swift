//
//  EarnRewardsView.swift
//  SacredBillTracker
//
//  Referral / "Earn Rewards" screen. Shows the user's unique code,
//  copy + share, referral count, credits earned, status, and reward
//  history. Backed by ReferralService → Supabase.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct EarnRewardsView: View {
    @StateObject private var referrals = ReferralService.shared
    @State private var copied = false
    @State private var showShare = false

    private var code: String { referrals.dashboard.code }

    private var shareMessage: String {
        """
        I'm using Sacred Bill Tracker to stay on top of my money. \
        Use my code \(code) when you subscribe and we both get $5 in credit.
        """
    }

    var body: some View {
        List {
            // Code + actions
            Section {
                VStack(spacing: 14) {
                    Text("Your Referral Code")
                        .font(.caption).foregroundStyle(Color.appSubtleText)
                    Text(code)
                        .font(.system(.title, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.appAccentText)
                        .textSelection(.enabled)
                    HStack(spacing: 12) {
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = code
                            #endif
                            withAnimation { copied = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                        } label: {
                            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.appAccent)

                        Button {
                            showShare = true
                            AnalyticsService.shared.track(.referralShared, source: "earn_rewards")
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.appAccent)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            } header: {
                Text("Give $5, Get $5")
            } footer: {
                Text("When a friend subscribes with your code and stays subscribed for 30 days, you each get $5 in subscription credit.")
            }

            // Stats
            Section("Your Progress") {
                statRow("Referrals", value: "\(referrals.dashboard.referrals)", icon: "person.2.fill")
                statRow("Credits Earned", value: referrals.dashboard.creditsDisplay, icon: "giftcard.fill")
                statRow("Pending", value: "\(referrals.dashboard.pending)", icon: "hourglass")
            }

            // History
            Section("Reward History") {
                if referrals.dashboard.history.isEmpty {
                    Text("No rewards yet. Share your code to get started.")
                        .font(.footnote).foregroundStyle(Color.appSubtleText)
                } else {
                    ForEach(referrals.dashboard.history) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.role == "referrer" ? "Referral reward" : "Welcome reward")
                                    .font(.subheadline)
                                Text(item.reason ?? "")
                                    .font(.caption).foregroundStyle(Color.appSubtleText)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(item.amountDisplay).font(.subheadline.weight(.semibold))
                                Text(item.status.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(statusColor(item.status))
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Earn Rewards")
        .navigationBarTitleDisplayMode(.inline)
        .task { await referrals.refresh() }
        .refreshable { await referrals.refresh() }
        #if os(iOS)
        .sheet(isPresented: $showShare) {
            ShareSheet(activityItems: [shareMessage])
        }
        #endif
    }

    private func statRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.primary)
            Spacer()
            Text(value).font(.headline).foregroundStyle(Color.appAccentText)
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "granted": return .appHouseholdText
        case "void":    return .appDangerText
        default:        return .appSubtleText
        }
    }
}
