//
//  FocusPlusPaywallView.swift
//  SacredBillTracker
//
//  v1.0.9 — Dedicated paywall for the Sacred Focus+ add-on. Separate
//  from the Pro paywall because Focus+ is an ADD-ON: existing Pro
//  subscribers must also subscribe here to unlock Daily Focus Center,
//  Schedule Buddy, and the rest of the Focus+ feature set.
//
//  Buttons (per spec):
//    - Subscribe for $9.99/month   (uses StoreKit displayPrice — never hard-coded)
//    - Restore Purchases
//    - Maybe Later                  (dismiss)
//
//  App Store compliance:
//    - No financial advice promises.
//    - Schedule Buddy described as "suggestions only".
//    - Subscription terms surfaced via the system Manage Subscriptions
//      link the user already has access to in Settings.
//

import SwiftUI
import StoreKit

struct FocusPlusPaywallView: View {

    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var purchaseInFlight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    // ── Header ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.title)
                                .foregroundStyle(Color.appAccentText)
                            Text("Sacred Focus+")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.primary)
                        }
                        Text("Unlock daily planning, focus quotes, to-do lists, and Schedule Buddy.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // ── What's included ─────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What you get")
                            .font(.headline)

                        ForEach(FocusPlusFeature.all) { feature in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: feature.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.appAccentText)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(feature.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.appCard)
                    )

                    // ── Pricing tile ───────────────────────────────
                    pricingTile
                        .padding(.top, 4)

                    // ── CTA ─────────────────────────────────────────
                    subscribeButton
                    restoreButton
                    maybeLaterButton

                    // ── Compliance footer ──────────────────────────
                    footerNotice

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Theme.Color.background.ignoresSafeArea())
            .navigationTitle("Sacred Focus+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .task {
                if subs.products[ProductID.focusPlusMonthly] == nil {
                    await subs.loadProducts()
                }
            }
            .onChange(of: subs.hasFocusPlus) { _, newValue in
                if newValue { dismiss() }
            }
            .alert("Hmm, that didn't work",
                   isPresented: errorBinding,
                   presenting: subs.lastError) { _ in
                Button("OK", role: .cancel) { subs.lastError = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Pricing

    private var pricingTile: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sacred Focus+ Monthly")
                    .font(.subheadline.weight(.semibold))
                Text("Cancel anytime in Settings → Subscription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(displayPrice)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                Text("per month")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appAccent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(0.30), lineWidth: 1)
        )
    }

    /// StoreKit-provided localized price string (matches user's
    /// storefront). Falls back to the spec price if products haven't
    /// loaded yet — never hard-codes USD for the live App Store.
    private var displayPrice: String {
        subs.focusPlusProduct?.displayPrice ?? "$9.99"
    }

    // MARK: - Buttons

    private var subscribeButton: some View {
        Button {
            Task { await tapSubscribe() }
        } label: {
            HStack {
                if purchaseInFlight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                }
                Text(purchaseInFlight
                     ? "Working…"
                     : "Subscribe for \(displayPrice)/month")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.appAccentText)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(purchaseInFlight || subs.focusPlusProduct == nil)
        .accessibilityLabel("Subscribe to Sacred Focus Plus for \(displayPrice) per month")
    }

    private var restoreButton: some View {
        Button {
            Task { await subs.restorePurchases() }
        } label: {
            Text("Restore Purchases")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.appAccent.opacity(0.16))
                )
                .foregroundStyle(Color.appAccentText)
        }
        .buttonStyle(.plain)
        .disabled(purchaseInFlight)
    }

    private var maybeLaterButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Maybe Later")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var footerNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sacred Focus+ is an additional subscription on top of any existing Sacred Bill Tracker plan. Schedule Buddy provides general suggestions only and is not professional financial advice.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Link("Privacy Policy",
                     destination: URL(string: "https://www.sacredpathway.org/sacred-bill-tracker-privacy")!)
                Link("Terms of Use",
                     destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appAccentText)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func tapSubscribe() async {
        guard let product = subs.focusPlusProduct else {
            await subs.loadProducts()
            return
        }
        purchaseInFlight = true
        _ = await subs.purchase(product)
        purchaseInFlight = false
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { subs.lastError != nil },
            set: { if !$0 { subs.lastError = nil } }
        )
    }
}

// MARK: - Feature list

struct FocusPlusFeature: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String

    static let all: [FocusPlusFeature] = [
        .init(id: "center",
              icon: "target",
              title: "Daily Focus Center",
              subtitle: "One screen for what matters today — bills, tasks, and a short focus quote."),
        .init(id: "quotes",
              icon: "quote.bubble.fill",
              title: "Short focus quotes",
              subtitle: "Calm, motivational quotes to start each day with intention."),
        .init(id: "todo",
              icon: "checklist",
              title: "To-do list",
              subtitle: "Track quick wins alongside your bills and income."),
        .init(id: "buddy",
              icon: "calendar.badge.checkmark",
              title: "Schedule Buddy",
              subtitle: "Suggested daily plan based on what's due. Suggestions only — not advice."),
        .init(id: "reminders",
              icon: "bell.badge.fill",
              title: "Financial focus reminders",
              subtitle: "Gentle nudges for the actions you actually want to take."),
        .init(id: "progress",
              icon: "chart.bar.fill",
              title: "Progress tracking",
              subtitle: "See your streaks and completed tasks at a glance."),
        .init(id: "favorites",
              icon: "star.fill",
              title: "Saved favorite quotes",
              subtitle: "Bookmark the lines that hit and revisit them anytime.")
    ]
}

#Preview {
    FocusPlusPaywallView()
        .environmentObject(SubscriptionManager())
}
