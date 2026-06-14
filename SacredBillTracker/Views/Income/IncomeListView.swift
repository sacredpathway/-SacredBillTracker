//
//  IncomeListView.swift
//  SacredBillTracker
//
//  Weekly Income Tracker home screen. Lists every WeeklyIncome entry
//  with edit / delete affordances, surfaces This Week / Last 30 Days /
//  All Time totals at the top, and provides a plus button to add a
//  new entry.
//

import SwiftUI

struct IncomeListView: View {

    @EnvironmentObject private var store: IncomeStore

    @State private var showAdd = false
    @State private var editing: WeeklyIncome?

    /// Optional type filter passed in by the Dashboard's Financial
    /// Overview taps. nil = show every entry (matches the legacy
    /// behavior when the view is opened from Settings → Income).
    let typeFilter: IncomeType?

    init(typeFilter: IncomeType? = nil) {
        self.typeFilter = typeFilter
    }

    @AppStorage("sbt.income.period.v1") private var incomePeriodRaw: String = IncomePeriod.weekly.rawValue
    @AppStorage("sbt.income.weekStartDay.v1") private var weekStartDayRaw: Int = WeekStartDay.monday.rawValue

    private let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ProfileSwitcherBar()
                    .padding(.horizontal)

                totalsGrid
                    .padding(.horizontal)

                if filteredEntries.isEmpty {
                    emptyState
                        .padding(.top, 40)
                        .padding(.horizontal)
                } else {
                    entriesList
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .background(Theme.Color.background)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
                .accessibilityLabel("Add income entry")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddEditIncomeView()
                .environmentObject(store)
        }
        .sheet(item: $editing) { entry in
            AddEditIncomeView(existing: entry)
                .environmentObject(store)
        }
    }

    // MARK: - Totals

    private var totalsGrid: some View {
        let period = IncomePeriod.from(rawValue: incomePeriodRaw)
        let weekStart = WeekStartDay.from(rawValue: weekStartDayRaw)
        let bounds = period.currentBounds(weekStartDay: weekStart)
        let periodTotal = store.total(in: bounds.start...bounds.end)

        return VStack(alignment: .leading, spacing: 12) {
            Text("Totals")
                .font(.title3.bold())

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                totalCard(title: period.currentPeriodLabel,
                          total: periodTotal,
                          systemImage: "calendar.badge.clock",
                          tint: .appAccent)
                totalCard(title: "Last 30 Days",
                          total: store.last30DaysTotal,
                          systemImage: "clock.arrow.circlepath",
                          tint: .appHousehold)
            }

            totalCard(title: "All Time",
                      total: store.allTimeTotal,
                      systemImage: "infinity.circle.fill",
                      tint: .appBusiness)

            // v1.0.9 — Business / Personal split of all-time totals.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                totalCard(title: "Business",
                          total: store.allTimeTotal(type: .business),
                          systemImage: IncomeType.business.systemImage,
                          tint: IncomeType.business.accent)
                totalCard(title: "Personal",
                          total: store.allTimeTotal(type: .personal),
                          systemImage: IncomeType.personal.systemImage,
                          tint: IncomeType.personal.accent)
            }
        }
    }

    private func totalCard(title: String, total: Decimal, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title2.bold().monospacedDigit())
            Text("Income earned")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Empty

    private var emptyState: some View {
        EmptyStateView(
            systemImage: "dollarsign.circle",
            title: "No income yet",
            message: "Add your first income entry to start tracking your real profit."
        )
    }

    // MARK: - List

    private var entriesList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Entries")
                .font(.title3.bold())

            VStack(spacing: 0) {
                ForEach(filteredEntries) { entry in
                    Button {
                        editing = entry
                    } label: {
                        row(for: entry)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if entry.id != filteredEntries.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - Filtering

    /// Entries scoped to the optional `typeFilter`. Used by the
    /// empty-state branch + the rendered list so they stay in sync.
    private var filteredEntries: [WeeklyIncome] {
        guard let typeFilter else { return store.profileEntries }
        return store.profileEntries.filter { $0.type == typeFilter }
    }

    /// Navigation title that reflects the active filter.
    private var navTitle: String {
        switch typeFilter {
        case .business: return "Business Income"
        case .personal: return "Personal Income"
        case nil:       return "Income Overview"
        }
    }

    @ViewBuilder
    private func row(for entry: WeeklyIncome) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entry.type.accent.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: entry.type.systemImage)
                    .font(.title3)
                    .foregroundStyle(entry.type.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.sourceName.isEmpty ? entry.rangeLabel : entry.sourceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(entry.type.title)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(entry.type.accent.opacity(0.18)))
                        .foregroundStyle(entry.type.accent)
                }
                Text(entry.rangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(entry.formattedAmount)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
    }
}

#Preview {
    NavigationStack {
        IncomeListView()
            .environmentObject(IncomeStore())
            .environmentObject(ManagedProfileStore.shared)
    }
}
