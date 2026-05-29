//
//  SacredDailyFocusCard.swift
//  SacredBillTracker
//
//  v1.0.9 — Combined hero card. Replaces the separate `DailyQuoteBanner`
//  + `BrandHeaderView` stack at the top of the Dashboard with one
//  premium, compact card titled "Sacred Daily Focus".
//
//  Contains:
//    • Sacred Bill Tracker logo (Tree of Life)
//    • App name
//    • Today's quote (single-line preview, expands on tap)
//    • Author
//    • Share button
//
//  The whole card is a principal button — tapping anywhere (except the
//  share glyph) opens `DailyFocusDetailView` as a sheet with the full
//  quote, attribution, and today's money-focus prompt.
//

import SwiftUI

struct SacredDailyFocusCard: View {

    let quote: MotivationalQuote

    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var todoStore: TodoStore

    /// v1.0.9 — When the user has Focus+, tap pushes the Focus+ center
    /// in this sheet. When they don't, tap opens the Focus+ paywall.
    /// One state covers both modes so the card is the SINGLE entry
    /// point and there is no second dashboard card.
    @State private var showFocusCenter = false
    @State private var showPaywall = false

    private static let appStoreURL: String =
        "https://apps.apple.com/us/app/sacred-bill-tracker/id6762890363"

    var body: some View {
        Button {
            if subs.hasFocusPlus {
                showFocusCenter = true
            } else {
                showPaywall = true
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {

                // Logo — same Tree of Life used everywhere else, with
                // the lime ring + gold shadow signature.
                logo
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(Color.appLime.opacity(0.85), lineWidth: 1.25)
                    )
                    .shadow(color: Color.appLime.opacity(0.25), radius: 6, y: 0)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Sacred Focus")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.appAccent)
                            .lineLimit(1)
                        focusPlusBadge
                    }

                    Text(quote.text)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !quote.author.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("— \(quote.author)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                // Share — its own tappable target so the surrounding
                // card button doesn't swallow the tap. Wrapped in a
                // ZStack so SwiftUI doesn't treat it as part of the
                // outer Button's hit area.
                ShareLink(
                    item: shareText,
                    subject: Text("Quote from Sacred Bill Tracker")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(Color.appAccent.opacity(0.15))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share today's quote")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [Color.appSacredBlack, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.appAccent.opacity(0.30), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sacred Focus. \(quote.text).")
        .accessibilityHint(subs.hasFocusPlus
            ? "Opens Sacred Focus Plus — daily planning, quotes, to-dos, and Schedule Buddy."
            : "Opens the Sacred Focus Plus upgrade screen.")
        // v1.0.9 — Subscribed: push Focus+ center as a sheet.
        .sheet(isPresented: $showFocusCenter) {
            NavigationStack {
                DailyFocusCenterView()
                    .environmentObject(subs)
                    .environmentObject(store)
                    .environmentObject(scheduleStore)
                    .environmentObject(todoStore)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showFocusCenter = false }
                        }
                    }
            }
        }
        // v1.0.9 — Not subscribed: open Focus+ paywall.
        .sheet(isPresented: $showPaywall) {
            FocusPlusPaywallView()
                .environmentObject(subs)
        }
    }

    // MARK: - Focus+ badge

    /// Small pill inside the card. Reads "Focus+" with the brand gold
    /// when locked, switches to a check-marked unlocked style when
    /// the user has the add-on. Subtle by design — keeps the card
    /// premium and minimal.
    @ViewBuilder
    private var focusPlusBadge: some View {
        if subs.hasFocusPlus {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2.weight(.bold))
                Text("Focus+")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.appLime.opacity(0.30)))
            .foregroundStyle(Color.appLime)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                Text("Focus+")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.appAccent.opacity(0.22)))
            .foregroundStyle(Color.appAccent)
        }
    }

    // MARK: - Logo (mirrors BrandHeaderView)

    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color.appSacredBlack)
        } else {
            ZStack {
                Circle().fill(Color.appSacredBlack)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appLime, Color.appAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var shareText: String {
        var parts: [String] = ["“\(quote.text)”"]
        let author = quote.author.trimmingCharacters(in: .whitespaces)
        if !author.isEmpty {
            parts.append("— \(author)")
        }
        parts.append("")
        parts.append("Sent from Sacred Bill Tracker")
        if !Self.appStoreURL.isEmpty {
            parts.append(Self.appStoreURL)
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Detail sheet

struct DailyFocusDetailView: View {

    let quote: MotivationalQuote

    @Environment(\.dismiss) private var dismiss

    private static let appStoreURL: String =
        "https://apps.apple.com/us/app/sacred-bill-tracker/id6762890363"

    /// Money-focus prompt of the day. Keep it short, calm, and
    /// action-oriented. Cycle through a small pool by day-of-year so
    /// the prompt feels alive without going off-brand.
    private var moneyFocus: String {
        let prompts = [
            "Review what is due today and mark anything paid.",
            "Glance at your overdue list. Knock out one bill if you can.",
            "Log any income you earned this week. Small wins count.",
            "Check your business profit margin for the month so far.",
            "Open one bill detail and double-check the due date.",
            "Mark one paid bill as paid so your dashboard is honest.",
            "Add an upcoming bill before it sneaks up on you."
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return prompts[(day - 1) % prompts.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Brand block.
                    HStack(spacing: 12) {
                        logo
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.appLime.opacity(0.85), lineWidth: 1.25))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Sacred Bill Tracker")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Rooted in what matters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    // Full quote.
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "quote.opening")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.appAccent)
                        Text(quote.text)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !quote.author.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("— \(quote.author)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.appAccent.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.appAccent.opacity(0.20), lineWidth: 1)
                    )

                    // Money focus prompt.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Today's Money Focus", systemImage: "target")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.appHousehold)
                        Text(moneyFocus)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.appCard)
                    )

                    // Share button.
                    ShareLink(
                        item: shareText,
                        subject: Text("Quote from Sacred Bill Tracker")
                    ) {
                        Label("Share Quote", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.appAccent.opacity(0.18))
                            )
                            .foregroundStyle(Color.appAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Theme.Color.background)
            .navigationTitle("Daily Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color.appSacredBlack)
        } else {
            ZStack {
                Circle().fill(Color.appSacredBlack)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appLime, Color.appAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var shareText: String {
        var parts: [String] = ["“\(quote.text)”"]
        let author = quote.author.trimmingCharacters(in: .whitespaces)
        if !author.isEmpty {
            parts.append("— \(author)")
        }
        parts.append("")
        parts.append("Sent from Sacred Bill Tracker")
        if !Self.appStoreURL.isEmpty {
            parts.append(Self.appStoreURL)
        }
        return parts.joined(separator: "\n")
    }
}

#Preview {
    SacredDailyFocusCard(
        quote: MotivationalQuote(
            text: "Rooted in what matters — pay yourself first.",
            author: "Sacred Bill Tracker"
        )
    )
    .environmentObject(SubscriptionManager())
    .padding()
    .background(Color(.systemGroupedBackground))
}
