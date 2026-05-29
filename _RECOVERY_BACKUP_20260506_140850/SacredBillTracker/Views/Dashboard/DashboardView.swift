//
//  DashboardView.swift
//  SacredBillTracker
//

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject private var store: BillStore
    @StateObject private var quotes = QuoteService.shared
    @State private var showAdd = false

    private let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DailyQuoteBanner(quote: quotes.quote)
                        .padding(.horizontal)

                    BrandHeaderView()
                        .padding(.horizontal)

                    if store.bills.isEmpty {
                        // First-launch / empty-state: no bills exist at all.
                        // Skip the rest of the dashboard widgets — they would
                        // all show $0/0 and look broken to a brand-new user.
                        EmptyStateView(
                            systemImage: "tray",
                            title: "Welcome to Sacred Bill Tracker",
                            message: "Start tracking your bills to see your financial overview."
                        )
                        .padding(.top, 40)
                        .padding(.horizontal)
                    } else {
                        // Per spec: This Month totals sit DIRECTLY UNDER the
                        // black logo card so the user sees household / business
                        // money first.
                        totalsSection

                        FilterPicker(selection: $store.filter)
                            .padding(.horizontal)

                        snapshotGrid

                        RiskAlertCard(flags: store.riskFlags())
                            .padding(.horizontal)

                        CashFlowCard(flow: store.cashFlow())
                            .padding(.horizontal)

                        PrioritySection(
                            bills: store.priorityBills(limit: 3),
                            maxUnpaidAmount: store.maxUnpaidAmount
                        )

                        overdueSection
                        upcomingSection
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .accessibilityLabel("Add Bill")
                }
            }
            .navigationDestination(for: Bill.self) { bill in
                BillDetailView(bill: bill)
            }
            .navigationDestination(for: BillBucket.self) { bucket in
                BucketBillsListView(bucket: bucket)
            }
            .sheet(isPresented: $showAdd) {
                QuickAddView()
            }
        }
    }

    // MARK: - Snapshot

    private var snapshotGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCardLink(
                bucket: .dueToday,
                value: "\(store.dueToday.count)",
                systemImage: "clock.fill",
                tint: .appAmber,
                subtitle: sumString(store.dueToday)
            )
            statCardLink(
                bucket: .thisWeek,
                value: "\(store.dueThisWeek.count)",
                systemImage: "calendar.badge.clock",
                tint: .appLime,
                subtitle: sumString(store.dueThisWeek)
            )
            statCardLink(
                bucket: .overdue,
                value: "\(store.overdue.count)",
                systemImage: "exclamationmark.triangle.fill",
                tint: .red,                    // kept semantic – red = urgent
                subtitle: sumString(store.overdue)
            )
            statCardLink(
                bucket: .upcoming,
                value: "\(store.upcoming.count)",
                systemImage: "tray.full.fill",
                tint: .appAccent,
                subtitle: sumString(store.upcoming)
            )
        }
        .padding(.horizontal)
    }

    /// Wraps a StatCard in a `NavigationLink(value:)` so tapping pushes
    /// the matching `BucketBillsListView`. `.buttonStyle(.plain)` keeps
    /// the card looking exactly like before — no chevron, no tint shift.
    private func statCardLink(
        bucket: BillBucket,
        value: String,
        systemImage: String,
        tint: Color,
        subtitle: String?
    ) -> some View {
        NavigationLink(value: bucket) {
            StatCard(
                title: bucket.shortTitle,
                value: value,
                systemImage: systemImage,
                tint: tint,
                subtitle: subtitle
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Show \(bucket.listTitle.lowercased())")
    }

    private func sumString(_ bills: [Bill]) -> String {
        let total = bills.reduce(Decimal(0)) { $0 + $1.amount }
        return currency.string(from: total as NSDecimalNumber) ?? ""
    }

    // MARK: - Monthly totals

    private var totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("This Month")
            HStack(spacing: 12) {
                totalCard(title: "Household",
                          total: store.totalThisMonth(for: .household),
                          systemImage: "house.fill",
                          tint: .appHousehold)
                totalCard(title: "Business",
                          total: store.totalThisMonth(for: .business),
                          systemImage: "briefcase.fill",
                          tint: .appBusiness)
            }
            .padding(.horizontal)
        }
    }

    private func totalCard(title: String, total: Decimal, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title2.bold().monospacedDigit())
            Text("Total due this month")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Overdue list

    @ViewBuilder
    private var overdueSection: some View {
        if !store.overdue.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Past due", tint: .red)
                VStack(spacing: 0) {
                    ForEach(store.overdue.prefix(5)) { bill in
                        NavigationLink(value: bill) {
                            BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount).padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        if bill.id != store.overdue.prefix(5).last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Upcoming list

    @ViewBuilder
    private var upcomingSection: some View {
        let list = Array(store.upcoming.prefix(8))
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Due next")
            if list.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.seal",
                    title: "Stay ahead",
                    message: "Nothing is queued up. Add your first recurring bill to keep the tree rooted."
                )
                .padding(.horizontal)
            } else {
                VStack(spacing: 0) {
                    ForEach(list) { bill in
                        NavigationLink(value: bill) {
                            BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount).padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                        if bill.id != list.last?.id {
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, tint: Color = .primary) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(tint)
            .padding(.horizontal)
    }
}

// MARK: - Daily Quote Banner

/// Compact card above the brand header — surfaces a fresh motivational
/// line every launch. Driven by `QuoteService` so the source can be a
/// live API call, the cached API result, or the local 365-line pool —
/// the banner doesn't care, it just renders whatever's current.
///
/// Sits ABOVE the black BrandHeaderView with a subtle gold-tinted card
/// so it complements rather than competes with the brand mark.
private struct DailyQuoteBanner: View {
    let quote: MotivationalQuote

    /// Public App Store link. `shareText` only appends this when it's
    /// non-empty so we never share a dead placeholder.
    private static let appStoreURL: String =
        "https://apps.apple.com/us/app/sacred-bill-tracker/id6762890363"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(quote.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !quote.author.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("— \(quote.author)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)

            ShareLink(
                item: shareText,
                subject: Text("Quote from Sacred Bill Tracker")
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share quote")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.appAccent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    /// Plain-text payload sent through the iOS share sheet. Keeps the
    /// quote, author, app attribution, and (when set) App Store link.
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
    DashboardView()
        .environmentObject(BillStore())
        .environmentObject(NotificationManager.shared)
}
