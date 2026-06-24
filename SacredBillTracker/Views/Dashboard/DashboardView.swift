//
//  DashboardView.swift
//  SacredBillTracker
//

import SwiftUI

struct DashboardView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var incomeStore: IncomeStore
    @EnvironmentObject private var subs: SubscriptionManager
    @StateObject private var quotes = QuoteService.shared
    @State private var showAdd = false
    @State private var showAddIncome = false

    // v1.6 — Sacred leaf scroll background. Tracks ScrollView offset so
    // the leaf field drifts gently as the user scrolls. Reduce Motion is
    // honored inside SacredLeafScrollBackground.
    @State private var sbtLeafScrollOffset: CGFloat = 0

    /// v1.0.9 — Single-source bill-edit trigger. `sheet(item:)` is
    /// idempotent (a second tap while one is presenting is a no-op),
    /// so this replaces the legacy NavigationLink → BillDetailView →
    /// "Edit" button two-screen flow that was perceived as stacking.
    @State private var billToEdit: Bill?

    /// v1.0.9.x — Health Score card → drill-in sheet.
    @State private var showHealthAttention: Bool = false
    /// Initial filter the health sheet should land on (most urgent
    /// signal first).
    @State private var healthInitialFilter: HealthAttentionListView.AttentionFilter = .overdue

    /// v1.0.10 — Today at a Glance taps → Focus center or paywall.
    @State private var showFocusFromGlance: Bool = false
    @State private var showFocusPaywallFromGlance: Bool = false

    /// v1.0.11 — Customizable dashboard. Persists the user's widget order
    /// + visibility as a comma-separated list of enabled widget raw values.
    /// Empty = the default order with all widgets shown.
    @AppStorage("sbt.dash.widgetOrder.v1") private var widgetOrderRaw: String = ""
    @State private var customizing = false

    // Income period prefs (v1.2.2). Read the same AppStorage keys
    // SettingsView writes so the card stays in sync the moment the
    // user changes them.
    @AppStorage("sbt.income.period.v1") private var incomePeriodRaw: String = IncomePeriod.weekly.rawValue
    @AppStorage("sbt.income.weekStartDay.v1") private var weekStartDayRaw: Int = WeekStartDay.monday.rawValue

    /// v1.0.9 — Filter on the new Business/Personal income split.
    /// Persists so the user's preferred lens (week / 30d / month / year
    /// / all time) survives launches.
    /// v1.0.9 — default is now "This Month" so the dashboard income
    /// counters reset on the 1st of every calendar month. Storage is
    /// untouched: this only affects the display window.
    @AppStorage("sbt.income.dashboardPeriod.v1") private var incomeDashboardPeriodRaw: String = IncomeDashboardPeriod.thisMonth.rawValue

    /// v1.0.9 — Display-only toggle. When ON the Top Summary collapses
    /// from two split cards into a single Combined Income card. Storage
    /// model, reports, and exports continue to track Business / Personal
    /// separately — this flag never touches the underlying data.
    @AppStorage("sbt.income.combineIncome.v1") private var combineIncome: Bool = false

    /// Combined Totals toggle (v1.3). When ON, totals/cards aggregate
    /// Personal + Business into a single "All Bills" view; the type
    /// filter is hidden because it's irrelevant to a combined view.
    /// Persists across launches via @AppStorage.
    @AppStorage("sbt.combinedTotals.v1") private var combinedTotals: Bool = false

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
                    // v1.0.9 — Single Sacred Daily Focus card serves as
                    // the ONLY dashboard hero AND the Sacred Focus+
                    // entry point. Tap routes to DailyFocusCenterView
                    // (subscribed) or FocusPlusPaywallView (not). The
                    // standalone Focus+ card has been removed so the
                    // dashboard top stays minimal.
                    ProfileSwitcherBar()
                        .padding(.horizontal)

                    SacredDailyFocusCard(quote: quotes.quote)
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
                        FilterPicker(selection: $store.filter)
                            .padding(.horizontal)

                        // v1.0.11 — Customizable widgets. Rendered in the
                        // user's saved order. Press-and-hold any widget (or
                        // tap the Customize button) to reorder, add, or
                        // remove widgets.
                        ForEach(enabledWidgets) { widget in
                            widgetView(widget)
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    customizing = true
                                }
                        }
                    }
                }
                .padding(.vertical)
                // v1.6 — track scroll offset for SacredLeafScrollBackground
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SacredScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("sbtDashboard")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "sbtDashboard")
            .onPreferenceChange(SacredScrollOffsetKey.self) { sbtLeafScrollOffset = $0 }
            .background(
                ZStack {
                    Theme.Color.background
                    SacredLeafScrollBackground(scrollOffset: sbtLeafScrollOffset)
                }
                .ignoresSafeArea()
            )
            .navigationTitle("Dashboard")
            // AutoTrack: pull bank deposits into the income counter when the
            // user is entitled. No-op otherwise (RPC returns no rows).
            .task(id: subs.hasAutoTrack) {
                if subs.hasAutoTrack {
                    await incomeStore.refreshBankIncome()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !store.bills.isEmpty {
                        Button { customizing = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.appAccentText)
                        }
                        .accessibilityLabel("Customize dashboard")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.appAccentText)
                                    .shadow(color: Color.appAccent.opacity(0.45), radius: 8, x: 0, y: 4)
                            )
                    }
                    .accessibilityLabel("Add Bill")
                }
            }
            // v1.0.9 — removed `.navigationDestination(for: Bill.self)`.
            // Bill row taps now use `Button { billToEdit = bill }` +
            // `.sheet(item: $billToEdit)` instead of pushing a detail
            // screen, so there is exactly one navigation surface per
            // tap and `sheet(item:)` prevents double-stacking.
            .navigationDestination(for: BillBucket.self) { bucket in
                BucketBillsListView(bucket: bucket)
            }
            .sheet(item: $billToEdit) { bill in
                AddEditBillView(mode: .edit(bill))
                    .environmentObject(store)
            }
            .sheet(isPresented: $showHealthAttention) {
                HealthAttentionListView(initialFilter: healthInitialFilter)
                    .environmentObject(store)
            }
            .sheet(isPresented: $customizing) {
                DashboardCustomizeSheet(
                    enabled: enabledWidgets,
                    hidden: hiddenWidgets,
                    onSave: { saveOrder($0) }
                )
            }
            .sheet(isPresented: $showFocusFromGlance) {
                NavigationStack {
                    DailyFocusCenterView()
                        .environmentObject(subs)
                        .environmentObject(store)
                        .environmentObject(incomeStore)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showFocusFromGlance = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showFocusPaywallFromGlance) {
                FocusPlusPaywallView()
                    .environmentObject(subs)
            }
            .sheet(isPresented: $showAdd) {
                QuickAddView()
            }
            .sheet(isPresented: $showAddIncome) {
                AddEditIncomeView()
                    .environmentObject(incomeStore)
            }
        }
    }

    // MARK: - Income split (REMOVED v1.0.9)
    //
    // The Business-vs-Personal cards, Quick Stats, filter pills, and
    // Combine Income toggle that used to live in `incomeSection` now
    // belong to `FinancialOverviewSection`. The helpers below have
    // been deleted; only `snapshotGrid` and its helpers remain.

    /*
    private var __removed_incomeSection: some View {
        let weekStart = WeekStartDay.from(rawValue: weekStartDayRaw)
        let period = IncomeDashboardPeriod.from(rawValue: incomeDashboardPeriodRaw)
        let range = incomeStore.bounds(for: period, weekStartDay: weekStart)

        let businessTotal = incomeStore.total(in: range, type: .business)
        let personalTotal = incomeStore.total(in: range, type: .personal)
        let combined = businessTotal + personalTotal
        let quick = computeQuickStats(in: range)

        return VStack(alignment: .leading, spacing: 16) {

            // Header bar (title + Add button).
            HStack {
                sectionHeader("Income Overview")
                Spacer()
                Button {
                    showAddIncome = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccent)
                }
                .buttonStyle(.plain)
                .padding(.trailing)
            }

            // ── Top Summary ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                incomeSubsectionHeader("Top Summary")

                // Combine Income toggle (display-only — storage and
                // reports continue to track Business / Personal
                // separately regardless of this switch).
                combineIncomeToggle
                    .padding(.horizontal)

                Group {
                    if combineIncome {
                        combinedTopCard(total: combined)
                            .padding(.horizontal)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            ))
                    } else {
                        HStack(spacing: 12) {
                            incomeTotalCard(
                                type: .business,
                                total: businessTotal,
                                percent: percentage(of: businessTotal, in: combined)
                            )
                            incomeTotalCard(
                                type: .personal,
                                total: personalTotal,
                                percent: percentage(of: personalTotal, in: combined)
                            )
                        }
                        .padding(.horizontal)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96)),
                            removal: .opacity
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: combineIncome)
            }

            // Total Income section is redundant when the Top Summary
            // already shows the combined number — hide it in that mode
            // to avoid showing the same dollar figure twice.
            if !combineIncome {
                incomeDivider
                    .transition(.opacity)

                // ── Total Income ────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    incomeSubsectionHeader("Total Income")
                    combinedIncomeCard(total: combined)
                        .padding(.horizontal)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            incomeDivider

            // ── Income Insight ──────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                incomeSubsectionHeader("Income Insight")
                let lines = combineIncome
                    ? combinedIncomeInsight(combined: combined)
                    : incomeInsights(
                        business: businessTotal,
                        personal: personalTotal,
                        period: period
                    )
                if lines.isEmpty {
                    Text("No income recorded for this period yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                        .padding(.horizontal)
                } else {
                    ForEach(lines, id: \.self) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.appAccent.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.appAccent.opacity(0.18), lineWidth: 1)
                            )
                            .padding(.horizontal)
                    }
                }
            }

            incomeDivider

            // ── Quick Stats ─────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                incomeSubsectionHeader("Quick Stats")
                quickStatsCard(stats: quick)
                    .padding(.horizontal)
            }

            incomeDivider

            // ── Filter ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                incomeSubsectionHeader("Filter")
                filterPills(selected: period)
            }
        }
        // Drive the same easing across every conditional render so
        // toggling Combine Income animates as one coherent layout
        // change rather than independent staggered swaps.
        .animation(.easeInOut(duration: 0.22), value: combineIncome)
    }

    // MARK: - Combine Income toggle + combined card (v1.0.9)

    /// Pill-style toggle row matching the existing `combinedTotalsToggle`
    /// look. Storage-only switch — does NOT mutate any income data.
    private var combineIncomeToggle: some View {
        HStack {
            Image(systemName: combineIncome
                  ? "rectangle.stack.fill"
                  : "rectangle.split.2x1")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(combineIncome ? Color.appAccent : .secondary)
            Text("Combine Income")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { combineIncome },
                set: { newValue in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        combineIncome = newValue
                    }
                }
            ))
            .labelsHidden()
            .tint(Color.appAccent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(combineIncome
            ? "Combine Income on. Showing one combined card."
            : "Combine Income off. Showing Business and Personal separately.")
    }

    /// Full-width replacement for the two split cards when the toggle is
    /// ON. Same overall card chrome as the split cards so the swap feels
    /// like one card growing rather than a layout reflow.
    private func combinedTopCard(total: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Combined Income", systemImage: "dollarsign.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(Color.appAccent)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title.bold().monospacedDigit())
            Text("Business + Personal earnings together")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Single-line insight used when the Combine Income toggle is ON.
    /// Matches the v1.0.9 spec exactly:
    ///   "Your combined income this period is $15,464.79."
    private func combinedIncomeInsight(combined: Decimal) -> [String] {
        guard combined > 0 else { return [] }
        let amount = currency.string(from: combined as NSDecimalNumber) ?? "$0"
        return ["Your combined income this period is \(amount)."]
    }

    // MARK: - Income subsection chrome

    private func incomeSubsectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
            .padding(.horizontal)
    }

    private var incomeDivider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.18))
            .frame(height: 1)
            .padding(.horizontal)
            .padding(.top, 2)
    }

    /// Horizontal pill row used by both the (legacy) inline filter and
    /// the new bottom Filter section. Bound to `incomeDashboardPeriodRaw`.
    private func filterPills(selected: IncomeDashboardPeriod) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(IncomeDashboardPeriod.allCases) { p in
                    Button {
                        incomeDashboardPeriodRaw = p.rawValue
                    } label: {
                        Text(p.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(
                                    p == selected
                                    ? Color.appAccent.opacity(0.18)
                                    : Color.secondary.opacity(0.12)
                                )
                            )
                            .foregroundStyle(p == selected ? Color.appAccent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Quick Stats (v1.0.9)

    private struct IncomeQuickStats {
        let highestSource: (name: String, total: Decimal)?
        let averageMonthly: Decimal
        let recordCount: Int
    }

    /// Aggregates stats for the currently-selected filter window.
    /// - Highest source: groups entries by `sourceName` (case-insensitive),
    ///   picks the largest sum.
    /// - Average monthly: total / number of distinct (year, month) buckets
    ///   that actually contained income. Min divisor = 1 so a single-month
    ///   filter still produces a real average instead of $0.
    /// - Record count: number of entries within the window.
    private func computeQuickStats(in range: ClosedRange<Date>) -> IncomeQuickStats {
        let filtered = incomeStore.entries(in: range)
        let cal = Calendar.current

        // Highest income source.
        let groupedBySource = Dictionary(grouping: filtered) { entry -> String in
            let key = entry.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            return key.isEmpty ? "—" : key
        }
        let sourceTotals = groupedBySource.map { (name, list) -> (name: String, total: Decimal) in
            (name: name, total: list.reduce(Decimal(0)) { $0 + $1.amount })
        }
        let highest = sourceTotals.max(by: { $0.total < $1.total })

        // Average monthly.
        let total = filtered.reduce(Decimal(0)) { $0 + $1.amount }
        let monthBuckets = Set(filtered.map { entry -> String in
            let c = cal.dateComponents([.year, .month], from: entry.weekStart)
            return "\(c.year ?? 0)-\(c.month ?? 0)"
        })
        let months = max(monthBuckets.count, 1)
        let avg: Decimal = NSDecimalNumber(decimal: total)
            .dividing(by: NSDecimalNumber(value: months)) as Decimal

        return IncomeQuickStats(
            highestSource: highest,
            averageMonthly: avg,
            recordCount: filtered.count
        )
    }

    private func quickStatsCard(stats: IncomeQuickStats) -> some View {
        VStack(spacing: 0) {
            // Highest Income Source
            quickStatsRow(
                label: "Highest Income Source",
                primary: stats.highestSource?.name ?? "—",
                secondary: stats.highestSource.map {
                    currency.string(from: $0.total as NSDecimalNumber) ?? "$0"
                } ?? "$0",
                systemImage: "trophy.fill",
                tint: Color.appAccent
            )

            Divider().padding(.leading, 56)

            // Average Monthly Income
            quickStatsRow(
                label: "Average Monthly Income",
                primary: currency.string(from: stats.averageMonthly as NSDecimalNumber) ?? "$0",
                secondary: nil,
                systemImage: "chart.line.uptrend.xyaxis",
                tint: Color.appBusiness
            )

            Divider().padding(.leading, 56)

            // Income Records
            quickStatsRow(
                label: "Income Records",
                primary: "\(stats.recordCount) Entr\(stats.recordCount == 1 ? "y" : "ies")",
                secondary: nil,
                systemImage: "list.bullet.rectangle.portrait",
                tint: Color.appHousehold
            )
        }
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func quickStatsRow(
        label: String,
        primary: String,
        secondary: String?,
        systemImage: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 36, height: 36)
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(primary)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if let secondary {
                Text(secondary)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Income card helpers (v1.0.9)

    private func incomeTotalCard(
        type: IncomeType,
        total: Decimal,
        percent: Int?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(type.cardTitle, systemImage: type.systemImage)
                .font(.caption.bold())
                .foregroundStyle(type.accent)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title2.bold().monospacedDigit())
            Text("\(percent ?? 0)% of earnings")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(type.accent.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func combinedIncomeCard(total: Decimal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Income")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                    .font(.title.bold().monospacedDigit())
            }
            Spacer()
            Image(systemName: "dollarsign.circle.fill")
                .font(.title)
                .foregroundStyle(Color.appAccent)
        }
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    /// Integer percentage of `part` relative to `whole`. Returns nil
    /// when `whole` is zero (so the cards don't render "0%" misleadingly
    /// on an empty period).
    private func percentage(of part: Decimal, in whole: Decimal) -> Int? {
        guard whole > 0 else { return nil }
        let p = NSDecimalNumber(decimal: part)
            .dividing(by: NSDecimalNumber(decimal: whole))
            .multiplying(by: 100)
        return Int(p.doubleValue.rounded())
    }

    /// Per-category insight lines used when the Combine Income toggle
    /// is OFF — one line for Business, one line for Personal. Matches
    /// the v1.0.9 spec:
    ///   "Business income generated 78% of your earnings this period."
    ///   "Personal income generated 22% of your earnings this period."
    /// Returns an empty array (no insight cards rendered) when there is
    /// no income at all in the selected period.
    private func incomeInsights(
        business: Decimal,
        personal: Decimal,
        period: IncomeDashboardPeriod
    ) -> [String] {
        let total = business + personal
        guard total > 0 else { return [] }

        let bp = percentage(of: business, in: total) ?? 0
        let pp = 100 - bp

        return [
            "Business income generated \(bp)% of your earnings this period.",
            "Personal income generated \(pp)% of your earnings this period."
        ]
    }
    */ // end __removed_incomeSection block

    // MARK: - Snapshot

    private var snapshotGrid: some View {
        let dueToday    = store.dueToday
        let dueThisWeek = store.dueThisWeek
        let overdue     = store.overdue
        let upcoming    = store.upcoming

        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 12) {
            statCardLink(
                bucket: .dueToday,
                value: "\(dueToday.count)",
                systemImage: "clock.fill",
                tint: .appAmber,
                subtitle: sumString(dueToday)
            )
            statCardLink(
                bucket: .thisWeek,
                value: "\(dueThisWeek.count)",
                systemImage: "calendar.badge.clock",
                tint: .appLime,
                subtitle: sumString(dueThisWeek)
            )
            statCardLink(
                bucket: .overdue,
                value: "\(overdue.count)",
                systemImage: "exclamationmark.triangle.fill",
                tint: .red,                    // kept semantic – red = urgent
                subtitle: sumString(overdue)
            )
            statCardLink(
                bucket: .upcoming,
                value: "\(upcoming.count)",
                systemImage: "tray.full.fill",
                tint: .appAccent,
                subtitle: sumString(upcoming)
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

    // MARK: - Monthly totals (REMOVED v1.0.9)
    //
    // Folded into `FinancialOverviewSection`. The helpers below
    // (totalsSection, combinedTotalsToggle, totalCard) are no longer
    // referenced anywhere — wrapped in a block comment so the Swift
    // compiler skips them, keeping the diff readable without dropping
    // git history.

    /*
    private var __removed_totalsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("This Month")
                Spacer()
                combinedTotalsToggle
                    .padding(.trailing)
            }
            if combinedTotals {
                totalCard(title: "All Bills",
                          total: store.combinedTotalThisMonth(),
                          systemImage: "tray.full.fill",
                          tint: .appAccent)
                    .padding(.horizontal)
            } else {
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
    }

    /// Compact pill-style toggle that flips Combined Totals on/off.
    /// Tapping animates the totals/snapshot/cards swap so the change
    /// feels instant without jank.
    private var combinedTotalsToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                combinedTotals.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: combinedTotals
                      ? "rectangle.stack.fill"
                      : "rectangle.split.2x1")
                Text(combinedTotals ? "Combined" : "Split")
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(combinedTotals
                    ? Color.appAccent.opacity(0.18)
                    : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(combinedTotals ? Color.appAccent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(combinedTotals
            ? "Combined totals on. Tap to split by type."
            : "Combined totals off. Tap to combine personal and business.")
    }

    /// Generic card used by both the Bills "This Month" section and the
    /// Weekly Income section. The optional `subtitle` lets each caller
    /// pass the contextually-correct caption — bill cards default to
    /// "Total due this month"; income cards pass their own income-
    /// specific captions (see `IncomePeriod.periodCaption` and
    /// `IncomePeriod.last30DaysCaption`).
    private func totalCard(
        title: String,
        total: Decimal,
        systemImage: String,
        tint: Color,
        subtitle: String = "Total due this month"
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title2.bold().monospacedDigit())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }
    */ // end __removed_totalsSection block

    // MARK: - Overdue list

    @ViewBuilder
    private var overdueSection: some View {
        let source = store.overdue
        if !source.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Past due", tint: .red)
                VStack(spacing: 0) {
                    ForEach(source.prefix(5)) { bill in
                        Button {
                            billToEdit = bill
                        } label: {
                            BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount)
                                .padding(.horizontal)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if bill.id != source.prefix(5).last?.id {
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
        let pool = store.upcoming
        let list = Array(pool.prefix(8))
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
                        Button {
                            billToEdit = bill
                        } label: {
                            BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount)
                                .padding(.horizontal)
                                .contentShape(Rectangle())
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

    // MARK: - Customizable widgets (v1.0.11)

    /// Widgets in the user's saved order. Empty storage → default order
    /// with everything shown.
    private var enabledWidgets: [DashboardWidget] {
        guard !widgetOrderRaw.isEmpty else { return DashboardWidget.allCases }
        let parsed = widgetOrderRaw
            .split(separator: ",")
            .compactMap { DashboardWidget(rawValue: String($0)) }
        return parsed.isEmpty ? DashboardWidget.allCases : parsed
    }

    /// Widgets the user has removed — available to re-add.
    private var hiddenWidgets: [DashboardWidget] {
        DashboardWidget.allCases.filter { !enabledWidgets.contains($0) }
    }

    private func saveOrder(_ list: [DashboardWidget]) {
        widgetOrderRaw = list.map(\.rawValue).joined(separator: ",")
    }

    @ViewBuilder
    private func widgetView(_ widget: DashboardWidget) -> some View {
        switch widget {
        case .incomeOverview:
            FinancialOverviewSection(
                combineIncome: $combineIncome,
                scope: store.filter,
                incomePeriod: IncomeDashboardPeriod.from(rawValue: incomeDashboardPeriodRaw),
                weekStartDay: WeekStartDay.from(rawValue: weekStartDayRaw)
            )
        case .healthScore:
            BillHealthScoreCard(
                score: BillHealthScore.compute(from: store.filteredBills),
                onTap: {
                    let s = BillHealthScore.compute(from: store.filteredBills)
                    if s.overdueCount > 0       { healthInitialFilter = .overdue }
                    else if s.dueTodayCount > 0 { healthInitialFilter = .dueToday }
                    else if s.dueSoonCount > 0  { healthInitialFilter = .dueThisWeek }
                    else                        { healthInitialFilter = .upcoming }
                    showHealthAttention = true
                }
            )
            .padding(.horizontal)
        case .quickStats:
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Quick Stats")
                snapshotGrid
            }
        case .riskAlerts:
            RiskAlertCard(flags: store.riskFlags())
                .padding(.horizontal)
        case .cashFlow:
            CashFlowCard(flow: store.cashFlow())
                .padding(.horizontal)
        case .payoffSummary:
            PayoffSummaryCard(summary: store.payoffSummary(for: store.filter))
                .padding(.horizontal)
        case .priority:
            PrioritySection(
                bills: store.priorityBills(limit: 3),
                maxUnpaidAmount: store.maxUnpaidAmount,
                onSelect: { billToEdit = $0 }
            )
        case .overdue:
            overdueSection
        case .upcoming:
            upcomingSection
        case .snapshot:
            snapshotLink
        }
    }

    private var snapshotLink: some View {
        NavigationLink {
            FinancialSnapshotView()
                .environmentObject(store)
        } label: {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Theme.Color.accentGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Financial snapshot")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    Text("Monthly totals at a glance")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.Color.card))
            .shadow(color: Theme.Color.cardShadow, radius: 10, x: 0, y: 4)
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dashboard widget catalog + customize editor (v1.0.11)

enum DashboardWidget: String, CaseIterable, Identifiable, Codable {
    case incomeOverview
    case healthScore
    case quickStats
    case riskAlerts
    case cashFlow
    case payoffSummary
    case priority
    case overdue
    case upcoming
    case snapshot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .incomeOverview: return "Financial Overview"
        case .healthScore:    return "Bill Health Score"
        case .quickStats:     return "Quick Stats"
        case .riskAlerts:     return "Risk Alerts"
        case .cashFlow:       return "Cash Flow"
        case .payoffSummary:  return "Payoff Progress"
        case .priority:       return "Priority Bills"
        case .overdue:        return "Past Due"
        case .upcoming:       return "Due Next"
        case .snapshot:       return "Financial Snapshot"
        }
    }

    var systemImage: String {
        switch self {
        case .incomeOverview: return "dollarsign.circle.fill"
        case .healthScore:    return "heart.text.square.fill"
        case .quickStats:     return "square.grid.2x2.fill"
        case .riskAlerts:     return "exclamationmark.triangle.fill"
        case .cashFlow:       return "arrow.left.arrow.right.circle.fill"
        case .payoffSummary:  return "chart.line.downtrend.xyaxis.circle.fill"
        case .priority:       return "flag.fill"
        case .overdue:        return "clock.badge.exclamationmark.fill"
        case .upcoming:       return "tray.full.fill"
        case .snapshot:       return "chart.pie.fill"
        }
    }
}

private struct PayoffSummaryCard: View {
    let summary: BillStore.PayoffSummary

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.downtrend.xyaxis.circle.fill")
                    .foregroundStyle(Theme.Color.accentGreen)
                Text("Payoff Progress")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
                if summary.trackedCount > 0 {
                    Text("\(summary.trackedCount)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(Theme.Color.accentGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.Color.accentGreen.opacity(0.14),
                                    in: Capsule())
                }
            }

            if summary.trackedCount == 0 {
                Text("No payoff balances tracked yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView(value: summary.progress)
                    .tint(Theme.Color.accentGreen)

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Remaining Payoff")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(PaydownPlanService.currency(summary.remainingBalance))
                            .font(.title3.bold().monospacedDigit())
                    }
                    Spacer()
                    Text("\(Int((summary.progress * 100).rounded()))% paid")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.Color.accentGreen)
                }

                Divider()

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    metric("Tracked Balances", summary.originalBalance)
                    metric("Paid Down", summary.paidDown)
                    metric("Monthly Payoff", summary.monthlyPaymentAmount)
                    metric("Remaining", summary.remainingBalance)
                }
            }
        }
        .padding(18)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func metric(_ title: String, _ amount: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(PaydownPlanService.currency(amount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Reorder / show / hide / add dashboard widgets. Drag the handles
/// (press-and-hold) to reorder; swipe or tap the minus to remove; use the
/// + menu to add hidden widgets back.
struct DashboardCustomizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var enabled: [DashboardWidget]
    @State private var hidden: [DashboardWidget]
    let onSave: ([DashboardWidget]) -> Void

    init(enabled: [DashboardWidget], hidden: [DashboardWidget], onSave: @escaping ([DashboardWidget]) -> Void) {
        _enabled = State(initialValue: enabled)
        _hidden = State(initialValue: hidden)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(enabled) { w in
                        Label(w.title, systemImage: w.systemImage)
                            .foregroundStyle(.primary)
                    }
                    .onMove { from, to in enabled.move(fromOffsets: from, toOffset: to) }
                    .onDelete { idx in
                        let removed = idx.map { enabled[$0] }
                        enabled.remove(atOffsets: idx)
                        hidden.append(contentsOf: removed)
                    }
                } header: {
                    Text("On your dashboard")
                } footer: {
                    Text("Drag the handles to reorder. Swipe or tap the minus to remove a widget.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if hidden.isEmpty {
                            Text("All widgets added")
                        } else {
                            ForEach(hidden) { w in
                                Button {
                                    hidden.removeAll { $0 == w }
                                    enabled.append(w)
                                } label: {
                                    Label(w.title, systemImage: w.systemImage)
                                }
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(hidden.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(enabled)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Daily Quote Banner (REMOVED v1.0.9)
//
// Folded into `SacredDailyFocusCard`. The old `DailyQuoteBanner`
// struct has been deleted; if you ever need its layout back, check
// git history for `Views/Dashboard/DashboardView.swift` before
// v1.0.9.

#Preview {
    DashboardView()
        .environmentObject(BillStore())
        .environmentObject(IncomeStore())
        .environmentObject(ManagedProfileStore.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionManager())
        .environmentObject(NoteStore())
        .environmentObject(ScheduleStore())
        .environmentObject(TodoStore())
}
