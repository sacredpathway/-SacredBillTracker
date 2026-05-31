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

    /// Dashboard-local scope filter (All / Personal / Business). Kept
    /// SEPARATE from `store.filter` so switching the dashboard view never
    /// changes the Bills tab's filter.
    @State private var dashScope: BillTypeFilter = .all

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

    /// Editable Dashboard — local widget order, styles, and widget
    /// settings. Stored in UserDefaults so the dashboard reopens exactly
    /// how the user arranged it without touching bill/income data.
    @State private var dashboardWidgets: [DashboardWidgetConfiguration] = []
    @State private var dashboardLayoutLoaded = false
    @State private var isEditingDashboard = false
    @State private var showWidgetGallery = false
    @State private var widgetBeingEdited: DashboardWidgetConfiguration?

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
                    dashboardEditBar
                    scopeToggle
                    editableDashboardWidgets
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditingDashboard.toggle()
                        }
                    } label: {
                        Text(isEditingDashboard ? "Done" : "Edit Dashboard")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.appAccentText)
                    }
                    .accessibilityLabel(isEditingDashboard ? "Done editing dashboard" : "Edit Dashboard")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        if isEditingDashboard {
                            Button { showWidgetGallery = true } label: {
                                Image(systemName: "square.grid.2x2.badge.plus")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.appAccentText)
                            }
                            .accessibilityLabel("Open Widget Gallery")
                        }
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
            .sheet(isPresented: $showWidgetGallery) {
                WidgetGalleryView(
                    hiddenKinds: hiddenWidgetKinds,
                    onAdd: addWidget
                )
            }
            .sheet(item: $widgetBeingEdited) { widget in
                DashboardWidgetSettingsSheet(
                    configuration: widget,
                    onSave: updateWidget
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
            .onAppear(perform: loadDashboardLayoutIfNeeded)
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
        // Combined Totals → ignore the BillTypeFilter, sum across both
        // Personal + Business. Otherwise fall back to the existing
        // type-filtered values from BillStore.
        let dueToday    = combinedTotals ? store.allDueToday    : store.dueToday
        let dueThisWeek = combinedTotals ? store.allDueThisWeek : store.dueThisWeek
        let overdue     = combinedTotals ? store.allOverdue     : store.overdue
        let upcoming    = combinedTotals ? store.allUpcoming    : store.upcoming

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
        let source = combinedTotals ? store.allOverdue : store.overdue
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
        let pool = combinedTotals ? store.allUpcoming : store.upcoming
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

    // MARK: - Scope toggle (All / Personal / Business)

    /// Active bills scoped by the dashboard-local `dashScope`. "Personal"
    /// maps to the app's `.household` bill type (data model unchanged).
    private var dashScopedBills: [Bill] {
        switch dashScope {
        case .all:       return store.bills
        case .household: return store.bills.filter { $0.type == .household }
        case .business:  return store.bills.filter { $0.type == .business }
        }
    }

    /// Clean 3-segment toggle bound to the dashboard-local `dashScope`.
    /// Independent of `store.filter`, so it never changes the Bills tab.
    /// Drives This Month, Income, the score rings, and the Schedule tab.
    private var scopeToggle: some View {
        HStack(spacing: 4) {
            ForEach(BillTypeFilter.allCases) { f in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { dashScope = f }
                } label: {
                    Text(scopeLabel(f))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(dashScope == f ? Color.primary : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(dashScope == f ? Color(.systemBackground) : Color.clear)
                                .shadow(color: dashScope == f ? Color.black.opacity(0.08) : .clear,
                                        radius: 4, y: 2)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Color.card)
        )
        .padding(.horizontal)
    }

    /// Dashboard-facing label. "Personal" maps to the `.household` bill
    /// type; the data model rawValue is unchanged.
    private func scopeLabel(_ f: BillTypeFilter) -> String {
        switch f {
        case .all:       return "All"
        case .household: return "Personal"
        case .business:  return "Business"
        }
    }

    // MARK: - Reference layout sections (scope-aware)

    /// "This Month" — Personal / Business bill totals. Shows both columns
    /// for All; a single full-width card when a scope is selected. Uses
    /// the real `BillStore.totalThisMonth(for:)`.
    private var thisMonthReferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("This Month")
            HStack(spacing: 12) {
                if dashScope != .business {
                    referenceTotalCard(
                        title: "Personal Bills",
                        total: store.totalThisMonth(for: .household),
                        caption: "Total due this month",
                        systemImage: "house.fill",
                        tint: .appHouseholdText
                    )
                }
                if dashScope != .household {
                    referenceTotalCard(
                        title: "Business Bills",
                        total: store.totalThisMonth(for: .business),
                        caption: "Total due this month",
                        systemImage: "briefcase.fill",
                        tint: .appBusinessText
                    )
                }
            }
            .padding(.horizontal)
        }
    }

    /// "Income" — This Week / Last 30 Days, wired to the real IncomeStore
    /// and scoped by the toggle (All = all types, Personal = .personal,
    /// Business = .business). The "Add" button opens AddEditIncomeView.
    private var incomeReferenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Income")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    showAddIncome = true
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                referenceTotalCard(
                    title: "This Week",
                    total: scopedIncome(in: incomeWeekRange),
                    caption: scopeIncomeCaption,
                    systemImage: "calendar",
                    tint: .appAccentText
                )
                referenceTotalCard(
                    title: "Last 30 Days",
                    total: scopedIncome(in: income30Range),
                    caption: scopeIncomeCaption,
                    systemImage: "clock.arrow.circlepath",
                    tint: .appHouseholdText
                )
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Scoped income helpers

    private var incomeWeekStart: WeekStartDay { WeekStartDay.from(rawValue: weekStartDayRaw) }
    private var incomeWeekRange: ClosedRange<Date> {
        incomeStore.bounds(for: .thisWeek, weekStartDay: incomeWeekStart)
    }
    private var income30Range: ClosedRange<Date> {
        incomeStore.bounds(for: .last30Days, weekStartDay: incomeWeekStart)
    }

    /// Income total in a range, scoped by the dashboard-local toggle.
    private func scopedIncome(in range: ClosedRange<Date>) -> Decimal {
        switch dashScope {
        case .all:       return incomeStore.total(in: range)
        case .household: return incomeStore.total(in: range, type: .personal)
        case .business:  return incomeStore.total(in: range, type: .business)
        }
    }

    private var scopeIncomeCaption: String {
        switch dashScope {
        case .all:       return "Total income"
        case .household: return "Personal income"
        case .business:  return "Business income"
        }
    }

    /// Shared two-column summary card used by both "This Month" and
    /// "Income" so the reference layout stays visually consistent.
    private func referenceTotalCard(
        title: String,
        total: Decimal,
        caption: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(tint)
            Text(currency.string(from: total as NSDecimalNumber) ?? "$0")
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, tint: Color = .primary) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(tint)
            .padding(.horizontal)
    }

    // MARK: - Editable dashboard

    private var dashboardEditBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isEditingDashboard ? "Editable Dashboard" : "Your Dashboard")
                    .font(.title3.bold())
                Text(isEditingDashboard
                     ? "Drag widgets, change styles, or add more from the gallery."
                     : "Personalized bills, income, focus, and cash-flow widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if isEditingDashboard {
                Menu {
                    ForEach(DashboardTemplate.allCases) { template in
                        Button {
                            applyDashboardTemplate(template)
                        } label: {
                            Label(template.title, systemImage: template.systemImage)
                        }
                    }
                } label: {
                    Label("Templates", systemImage: "rectangle.stack.badge.plus")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.appLime.opacity(0.16)))
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
                Button { showWidgetGallery = true } label: {
                    Label("Gallery", systemImage: "square.grid.2x2")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.appAccent.opacity(0.18)))
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private var editableDashboardWidgets: some View {
        VStack(spacing: 14) {
            if dashboardWidgets.isEmpty {
                emptyDashboardWidgetState
            } else {
                ForEach(Array(dashboardWidgetRows.enumerated()), id: \.offset) { _, row in
                    if row.count == 2 {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(row) { config in
                                editableWidgetCard(config)
                                    .frame(maxWidth: .infinity)
                                    .draggable(config.id.uuidString)
                                    .dropDestination(for: String.self) { items, _ in
                                        handleWidgetDrop(items, before: config.id)
                                    }
                            }
                        }
                        .padding(.horizontal)
                    } else if let config = row.first {
                        editableWidgetCard(config)
                            .padding(.horizontal)
                            .draggable(config.id.uuidString)
                            .dropDestination(for: String.self) { items, _ in
                                handleWidgetDrop(items, before: config.id)
                            }
                    }
                }
            }
        }
    }

    private var dashboardWidgetRows: [[DashboardWidgetConfiguration]] {
        var rows: [[DashboardWidgetConfiguration]] = []
        var smallRow: [DashboardWidgetConfiguration] = []

        for widget in dashboardWidgets {
            if widget.size == .small {
                smallRow.append(widget)
                if smallRow.count == 2 {
                    rows.append(smallRow)
                    smallRow.removeAll()
                }
            } else {
                if !smallRow.isEmpty {
                    rows.append(smallRow)
                    smallRow.removeAll()
                }
                rows.append([widget])
            }
        }

        if !smallRow.isEmpty {
            rows.append(smallRow)
        }

        return rows
    }

    private var emptyDashboardWidgetState: some View {
        VStack(spacing: 14) {
            EmptyStateView(
                systemImage: "square.grid.2x2",
                title: "Build your dashboard",
                message: "Add widgets from the gallery to create a dashboard that fits how you track bills."
            )
            Button {
                showWidgetGallery = true
            } label: {
                Label("Open Widget Gallery", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appAccentText)
        }
        .padding(.horizontal)
    }

    private var hiddenWidgetKinds: [DashboardWidgetKind] {
        let shown = Set(dashboardWidgets.map(\.kind))
        return DashboardWidgetKind.allCases.filter { !shown.contains($0) }
    }

    private func loadDashboardLayoutIfNeeded() {
        guard !dashboardLayoutLoaded else { return }
        dashboardWidgets = DashboardWidgetLayoutStore.load()
        dashboardLayoutLoaded = true
    }

    private func persistDashboardLayout() {
        DashboardWidgetLayoutStore.save(dashboardWidgets)
    }

    private func addWidget(_ kind: DashboardWidgetKind) {
        withAnimation(.easeInOut(duration: 0.2)) {
            dashboardWidgets.append(DashboardWidgetConfiguration(kind: kind))
            persistDashboardLayout()
        }
    }

    private func updateWidget(_ config: DashboardWidgetConfiguration) {
        guard let index = dashboardWidgets.firstIndex(where: { $0.id == config.id }) else { return }
        dashboardWidgets[index] = config
        persistDashboardLayout()
    }

    private func removeWidget(_ config: DashboardWidgetConfiguration) {
        withAnimation(.easeInOut(duration: 0.2)) {
            dashboardWidgets.removeAll { $0.id == config.id }
            persistDashboardLayout()
        }
    }

    private func moveWidget(_ sourceID: UUID, before targetID: UUID) {
        guard
            sourceID != targetID,
            let sourceIndex = dashboardWidgets.firstIndex(where: { $0.id == sourceID }),
            let targetIndex = dashboardWidgets.firstIndex(where: { $0.id == targetID })
        else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            let moved = dashboardWidgets.remove(at: sourceIndex)
            let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
            dashboardWidgets.insert(moved, at: adjustedTarget)
            persistDashboardLayout()
        }
    }

    private func handleWidgetDrop(_ items: [String], before targetID: UUID) -> Bool {
        guard
            isEditingDashboard,
            let raw = items.first,
            let draggedID = UUID(uuidString: raw)
        else { return false }
        moveWidget(draggedID, before: targetID)
        return true
    }

    private func moveWidget(_ config: DashboardWidgetConfiguration, direction: DashboardWidgetMoveDirection) {
        guard let index = dashboardWidgets.firstIndex(where: { $0.id == config.id }) else { return }
        let target: Int
        switch direction {
        case .up: target = max(0, index - 1)
        case .down: target = min(dashboardWidgets.count - 1, index + 1)
        }
        guard target != index else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            dashboardWidgets.move(fromOffsets: IndexSet(integer: index), toOffset: target > index ? target + 1 : target)
            persistDashboardLayout()
        }
    }

    private func setWidgetStyle(_ config: DashboardWidgetConfiguration, style: DashboardWidgetStyle) {
        var updated = config
        updated.style = style
        updateWidget(updated)
    }

    private func resetDashboardLayout() {
        withAnimation(.easeInOut(duration: 0.2)) {
            dashboardWidgets = DashboardWidgetLayoutStore.defaultWidgets()
            persistDashboardLayout()
        }
    }

    private func applyDashboardTemplate(_ template: DashboardTemplate) {
        withAnimation(.easeInOut(duration: 0.22)) {
            dashboardWidgets = template.widgets()
            persistDashboardLayout()
        }
    }

    private func editableWidgetCard(_ config: DashboardWidgetConfiguration) -> some View {
        EditableDashboardWidgetCard(
            configuration: config,
            isEditing: isEditingDashboard,
            canMoveUp: dashboardWidgets.first?.id != config.id,
            canMoveDown: dashboardWidgets.last?.id != config.id,
            onMoveUp: { moveWidget(config, direction: .up) },
            onMoveDown: { moveWidget(config, direction: .down) },
            onRemove: { removeWidget(config) },
            onEdit: { widgetBeingEdited = config },
            onStyleChange: { setWidgetStyle(config, style: $0) }
        ) {
            dashboardWidgetContent(config)
        }
    }

    @ViewBuilder
    private func dashboardWidgetContent(_ config: DashboardWidgetConfiguration) -> some View {
        switch config.kind {
        case .financialOverview:
            financialOverviewWidget(config)
        case .scoreCircle:
            scoreCircleWidget(config)
        case .dueToday:
            billMetricWidget(
                bills: dashScopedBills.filter { $0.isDueToday && !$0.isPaid },
                emptyText: "Nothing due today.",
                config: config
            )
        case .thisWeek:
            billMetricWidget(
                bills: dashScopedBills.filter { $0.isDueThisWeek && !$0.isPaid },
                emptyText: "No bills due this week.",
                config: config
            )
        case .overdueBills:
            billMetricWidget(
                bills: dashScopedBills.filter { $0.isOverdue },
                emptyText: "No overdue bills.",
                config: config,
                tint: .appDangerText
            )
        case .incomeSummary:
            incomeSummaryWidget(config)
        case .personalBills:
            typeSnapshotWidget(type: .household, config: config)
        case .businessBills:
            typeSnapshotWidget(type: .business, config: config)
        case .quoteOfTheDay:
            quoteWidget
        case .notes:
            DashboardNotesWidget(style: config.style)
        case .todoList:
            DashboardTodoWidget(style: config.style)
        case .upcomingBills:
            billListWidget(
                bills: Array(dashScopedBills.filter { !$0.isPaid && $0.dueDate >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.dueDate < $1.dueDate }.prefix(config.showsDetails ? 6 : 3)),
                emptyText: "No upcoming bills."
            )
        case .paidThisMonth:
            paidThisMonthWidget(config)
        case .totalIncome:
            totalIncomeWidget(config)
        case .spendingByCategory:
            spendingByCategoryWidget(config)
        case .subscriptionTracker:
            subscriptionTrackerWidget(config)
        case .savingsGoal:
            DashboardSavingsGoalWidget(style: config.style)
        case .calendarPreview:
            calendarPreviewWidget(config)
        case .businessSnapshot:
            typeSnapshotWidget(type: .business, config: config)
        case .personalSnapshot:
            typeSnapshotWidget(type: .household, config: config)
        case .netWorth:
            DashboardNetWorthWidget(style: config.style)
        case .monthlyCashFlow:
            monthlyCashFlowWidget(config)
        case .debtSnowballProgress:
            debtSnowballProgressWidget(config)
        case .emergencyFundTracker:
            DashboardEmergencyFundWidget(style: config.style)
        case .goalProgress:
            DashboardGoalProgressWidget(style: config.style)
        case .upcomingIncome:
            upcomingIncomeWidget(config)
        case .recentTransactions:
            recentTransactionsWidget(config)
        }
    }

    private func financialOverviewWidget(_ config: DashboardWidgetConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                widgetMetricTile(
                    title: "Personal Bills",
                    value: money(store.totalThisMonth(for: .household)),
                    icon: "house.fill",
                    tint: .appHouseholdText
                )
                widgetMetricTile(
                    title: "Business Bills",
                    value: money(store.totalThisMonth(for: .business)),
                    icon: "briefcase.fill",
                    tint: .appBusinessText
                )
                widgetMetricTile(
                    title: "Due Today",
                    value: "\(dashScopedBills.filter { $0.isDueToday && !$0.isPaid }.count)",
                    icon: "clock.fill",
                    tint: .appAmber
                )
                widgetMetricTile(
                    title: "Overdue",
                    value: "\(dashScopedBills.filter { $0.isOverdue }.count)",
                    icon: "exclamationmark.triangle.fill",
                    tint: .appDangerText
                )
            }
            if config.showsDetails {
                NavigationLink {
                    FinancialSnapshotView()
                        .environmentObject(store)
                } label: {
                    HStack {
                        Label("Open financial snapshot", systemImage: "chart.pie.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func scoreCircleWidget(_ config: DashboardWidgetConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardScoreCircles(
                bills: dashScopedBills,
                onHealthTap: {
                    let s = BillHealthScore.compute(from: dashScopedBills)
                    if s.overdueCount > 0       { healthInitialFilter = .overdue }
                    else if s.dueTodayCount > 0 { healthInitialFilter = .dueToday }
                    else if s.dueSoonCount > 0  { healthInitialFilter = .dueThisWeek }
                    else                        { healthInitialFilter = .upcoming }
                    showHealthAttention = true
                }
            )
            if config.showsDetails {
                Text("Score uses overdue bills, due dates, recurrence, autopay, categories, and saved bill details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func billMetricWidget(
        bills: [Bill],
        emptyText: String,
        config: DashboardWidgetConfiguration,
        tint: Color = .appAccentText
    ) -> some View {
        let total = bills.reduce(Decimal(0)) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(bills.count)")
                    .font(.system(size: config.style == .compact ? 30 : 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 2) {
                    Text(money(total))
                        .font(.headline.weight(.bold).monospacedDigit())
                    Text(bills.count == 1 ? "bill" : "bills")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if bills.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if config.showsDetails && config.style != .compact {
                billListWidget(bills: Array(bills.sorted { $0.dueDate < $1.dueDate }.prefix(4)), emptyText: emptyText)
            }
        }
    }

    private func incomeSummaryWidget(_ config: DashboardWidgetConfiguration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                widgetMetricTile(
                    title: "This Week",
                    value: money(scopedIncome(in: incomeWeekRange)),
                    icon: "calendar",
                    tint: .appAccentText
                )
                widgetMetricTile(
                    title: "Last 30 Days",
                    value: money(scopedIncome(in: income30Range)),
                    icon: "clock.arrow.circlepath",
                    tint: .appHouseholdText
                )
            }
            if config.showsDetails {
                Text(scopeIncomeCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func typeSnapshotWidget(type: BillType, config: DashboardWidgetConfiguration) -> some View {
        let monthBills = store.bills.filter { $0.type == type && $0.isDueThisMonth }
        let unpaid = monthBills.filter { !$0.isPaid }
        let paid = monthBills.filter { $0.isPaid }
        let tint: Color = type == .household ? .appHouseholdText : .appBusinessText
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                widgetMetricTile(
                    title: "This Month",
                    value: money(monthBills.reduce(Decimal(0)) { $0 + $1.amount }),
                    icon: type.systemImage,
                    tint: tint
                )
                widgetMetricTile(
                    title: "Unpaid",
                    value: money(unpaid.reduce(Decimal(0)) { $0 + $1.amount }),
                    icon: "clock.fill",
                    tint: .appAmber
                )
            }
            if config.showsDetails {
                HStack {
                    Label("\(paid.count) paid", systemImage: "checkmark.seal.fill")
                    Spacer()
                    Label("\(unpaid.count) unpaid", systemImage: "tray.full.fill")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var quoteWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.title3)
                .foregroundStyle(Color.appAccent)
            Text(quotes.quote.text)
                .font(.system(.body, design: .serif).weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if !quotes.quote.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("— \(quotes.quote.author)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appAccentText)
            }
        }
    }

    private func paidThisMonthWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let paid = dashScopedBills.filter { $0.isPaid && $0.isDueThisMonth }
        return billMetricWidget(
            bills: paid,
            emptyText: "No bills marked paid this month.",
            config: config,
            tint: .appHouseholdText
        )
    }

    private func totalIncomeWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let period = IncomeDashboardPeriod.from(rawValue: incomeDashboardPeriodRaw)
        let range = incomeStore.bounds(for: period, weekStartDay: incomeWeekStart)
        let total = scopedIncome(in: range)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(money(total))
                    .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.appAccentText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer()
            }
            Text("\(period.title) • \(scopeIncomeCaption)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if config.showsDetails {
                NavigationLink {
                    IncomeListView()
                        .environmentObject(incomeStore)
                } label: {
                    Label("View income entries", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func spendingByCategoryWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let rows = categoryBreakdownForCurrentMonth().prefix(config.showsDetails ? 5 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            if rows.isEmpty {
                Text("No spending by category this month yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows), id: \.category) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.category.systemImage)
                            .foregroundStyle(Color.appAccentText)
                            .frame(width: 22)
                        Text(row.category.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(money(row.total))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
    }

    private func subscriptionTrackerWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let subscriptions = dashScopedBills
            .filter { $0.category == .subscriptions && !$0.isPaid }
            .sorted { $0.dueDate < $1.dueDate }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(subscriptions.count)")
                    .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(Color.appAccentText)
                Text("active subscription\(subscriptions.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if config.showsDetails {
                billListWidget(bills: Array(subscriptions.prefix(4)), emptyText: "No active subscription bills.")
            }
        }
    }

    private func calendarPreviewWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let upcoming = dashScopedBills
            .filter { !$0.isPaid && $0.dueDate >= Calendar.current.startOfDay(for: Date()) }
            .sorted { $0.dueDate < $1.dueDate }
        return billListWidget(
            bills: Array(upcoming.prefix(config.showsDetails ? 5 : 3)),
            emptyText: "No bills on the calendar."
        )
    }

    private func monthlyCashFlowWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let income = scopedIncome(in: currentMonthRange)
        let spending = dashScopedBills
            .filter { currentMonthRange.contains($0.dueDate) }
            .reduce(Decimal(0)) { $0 + $1.amount }
        let net = income - spending

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(money(net))
                    .font(.system(.title2, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(net >= 0 ? Color.appAccentText : Color.appDangerText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer()
            }
            HStack(spacing: 10) {
                widgetMetricTile(title: "Income", value: money(income), icon: "arrow.down.circle.fill", tint: .appHouseholdText)
                widgetMetricTile(title: "Bills", value: money(spending), icon: "arrow.up.circle.fill", tint: .appAmber)
            }
            if config.showsDetails {
                Text(net >= 0 ? "Positive monthly cash flow." : "Bills are running ahead of income this month.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func debtSnowballProgressWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let debtBills = dashScopedBills.filter { $0.category.isRevolvingCredit && $0.deletedAt == nil }
        let remaining = debtBills.reduce(Decimal(0)) { $0 + $1.amount }
        let paidThisMonth = debtBills.filter { $0.isPaid && $0.isDueThisMonth }.reduce(Decimal(0)) { $0 + $1.amount }
        let target = max(remaining + paidThisMonth, Decimal(1))
        let progress = min(1, max(0, NSDecimalNumber(decimal: paidThisMonth).dividing(by: NSDecimalNumber(decimal: target)).doubleValue))

        return VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: progress)
                .tint(Color.appAccent)
            HStack(spacing: 10) {
                widgetMetricTile(title: "Remaining", value: money(remaining), icon: "creditcard.fill", tint: .appDangerText)
                widgetMetricTile(title: "Paid", value: money(paidThisMonth), icon: "checkmark.seal.fill", tint: .appHouseholdText)
            }
            if config.showsDetails {
                Text(debtBills.isEmpty ? "Add credit card or line of credit bills to track payoff progress." : "\(debtBills.count) debt bill\(debtBills.count == 1 ? "" : "s") in the snowball.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func upcomingIncomeWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        let upcoming = incomeStore.entries
            .filter { Calendar.current.startOfDay(for: $0.entryDate) >= today }
            .sorted { $0.entryDate < $1.entryDate }
        let visible = Array(upcoming.prefix(config.showsDetails ? 5 : 3))

        return VStack(alignment: .leading, spacing: 10) {
            if visible.isEmpty {
                Text("No upcoming income entries yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { entry in
                    incomeRow(entry)
                }
            }
        }
    }

    private func recentTransactionsWidget(_ config: DashboardWidgetConfiguration) -> some View {
        let billRows = dashScopedBills.map {
            DashboardTransactionRow(
                id: "bill-\($0.id.uuidString)",
                title: $0.name,
                subtitle: $0.dueDate.formatted(date: .abbreviated, time: .omitted),
                amount: -$0.amount,
                date: $0.dueDate,
                icon: $0.category.systemImage,
                tint: $0.type.accentColor
            )
        }
        let incomeRows = incomeStore.entries.map {
            DashboardTransactionRow(
                id: "income-\($0.id.uuidString)",
                title: $0.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Income" : $0.sourceName,
                subtitle: $0.entryDate.formatted(date: .abbreviated, time: .omitted),
                amount: $0.amount,
                date: $0.entryDate,
                icon: "banknote.fill",
                tint: .appAccentText
            )
        }
        let rows = Array((billRows + incomeRows).sorted { $0.date > $1.date }.prefix(config.showsDetails ? 6 : 3))

        return VStack(alignment: .leading, spacing: 8) {
            if rows.isEmpty {
                Text("No recent transactions yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    transactionRow(row)
                }
            }
        }
    }

    private var currentMonthRange: ClosedRange<Date> {
        let cal = Calendar.current
        let now = Date()
        guard let interval = cal.dateInterval(of: .month, for: now) else {
            return cal.startOfDay(for: now)...now
        }
        let end = cal.date(byAdding: .second, value: -1, to: interval.end) ?? interval.end
        return interval.start...end
    }

    private func billListWidget(bills: [Bill], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if bills.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(bills) { bill in
                    Button {
                        billToEdit = bill
                    } label: {
                        simpleBillRow(bill)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func simpleBillRow(_ bill: Bill) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bill.category.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(bill.type.accentColor)
                .frame(width: 26, height: 26)
                .background(bill.type.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(bill.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(bill.dueDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(bill.formattedAmount)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 2)
    }

    private func incomeRow(_ entry: WeeklyIncome) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.type.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appAccentText)
                .frame(width: 26, height: 26)
                .background(Color.appAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Income" : entry.sourceName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(entry.entryDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(entry.formattedAmount)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.appAccentText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 2)
    }

    private func transactionRow(_ row: DashboardTransactionRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(row.tint)
                .frame(width: 26, height: 26)
                .background(row.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(row.amount))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(row.amount >= 0 ? Color.appAccentText : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 2)
    }

    private func widgetMetricTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 8))
            Text(value)
                .font(.headline.weight(.heavy).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func categoryBreakdownForCurrentMonth() -> [(category: BillCategory, total: Decimal)] {
        let cal = Calendar.current
        let now = Date()
        let scoped = dashScopedBills.filter {
            cal.component(.month, from: $0.dueDate) == cal.component(.month, from: now)
            && cal.component(.year, from: $0.dueDate) == cal.component(.year, from: now)
        }
        let grouped = Dictionary(grouping: scoped, by: \.category)
        return grouped
            .map { (category: $0.key, total: $0.value.reduce(Decimal(0)) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private func money(_ value: Decimal) -> String {
        currency.string(from: value as NSDecimalNumber) ?? "$0"
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

// MARK: - Editable dashboard catalog

private struct DashboardTransactionRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let amount: Decimal
    let date: Date
    let icon: String
    let tint: Color
}

enum DashboardWidgetMoveDirection {
    case up
    case down
}

enum DashboardWidgetStyle: String, CaseIterable, Identifiable, Codable {
    case compact
    case large
    case card
    case circle
    case minimal
    case sacredFocus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Compact"
        case .large: return "Large"
        case .card: return "Card"
        case .circle: return "Circle"
        case .minimal: return "Minimal"
        case .sacredFocus: return "Sacred Focus"
        }
    }
}

enum DashboardWidgetSize: String, CaseIterable, Identifiable, Codable {
    case small
    case medium
    case large
    case fullWidth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .fullWidth: return "Full Width"
        }
    }

    var minHeight: CGFloat {
        switch self {
        case .small: return 132
        case .medium: return 168
        case .large: return 230
        case .fullWidth: return 190
        }
    }
}

enum DashboardWidgetColorTheme: String, CaseIterable, Identifiable, Codable {
    case sacredGold
    case midnightBlack
    case forestGreen
    case oceanBlue
    case light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sacredGold: return "Sacred Gold"
        case .midnightBlack: return "Midnight Black"
        case .forestGreen: return "Forest Green"
        case .oceanBlue: return "Ocean Blue"
        case .light: return "Light"
        }
    }

    var accent: Color {
        switch self {
        case .sacredGold: return Color.appAccentText
        case .midnightBlack: return Color.appSacredBlack
        case .forestGreen: return Color.appHouseholdText
        case .oceanBlue: return Color.blue
        case .light: return Color.appAccentText
        }
    }

    var softFill: Color {
        switch self {
        case .sacredGold: return Color.appAccent.opacity(0.12)
        case .midnightBlack: return Color.appSacredBlack.opacity(0.08)
        case .forestGreen: return Color.appHouseholdText.opacity(0.10)
        case .oceanBlue: return Color.blue.opacity(0.10)
        case .light: return Theme.Color.card
        }
    }

    var border: Color {
        switch self {
        case .sacredGold: return Color.appAccent.opacity(0.28)
        case .midnightBlack: return Color.appSacredBlack.opacity(0.24)
        case .forestGreen: return Color.appHouseholdText.opacity(0.24)
        case .oceanBlue: return Color.blue.opacity(0.24)
        case .light: return Color.appHairline
        }
    }
}

enum DashboardWidgetKind: String, CaseIterable, Identifiable, Codable {
    case financialOverview
    case scoreCircle
    case dueToday
    case thisWeek
    case overdueBills
    case incomeSummary
    case personalBills
    case businessBills
    case quoteOfTheDay
    case notes
    case todoList
    case upcomingBills
    case paidThisMonth
    case totalIncome
    case spendingByCategory
    case subscriptionTracker
    case savingsGoal
    case calendarPreview
    case businessSnapshot
    case personalSnapshot
    case netWorth
    case monthlyCashFlow
    case debtSnowballProgress
    case emergencyFundTracker
    case goalProgress
    case upcomingIncome
    case recentTransactions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .financialOverview: return "Financial Overview"
        case .scoreCircle: return "Score Circle"
        case .dueToday: return "Due Today"
        case .thisWeek: return "This Week"
        case .overdueBills: return "Overdue Bills"
        case .incomeSummary: return "Income Summary"
        case .personalBills: return "Personal Bills"
        case .businessBills: return "Business Bills"
        case .quoteOfTheDay: return "Quote of the Day"
        case .notes: return "Notes"
        case .todoList: return "To-Do List"
        case .upcomingBills: return "Upcoming Bills"
        case .paidThisMonth: return "Paid This Month"
        case .totalIncome: return "Total Income"
        case .spendingByCategory: return "Spending by Category"
        case .subscriptionTracker: return "Subscription Tracker"
        case .savingsGoal: return "Savings Goal"
        case .calendarPreview: return "Calendar Preview"
        case .businessSnapshot: return "Business Snapshot"
        case .personalSnapshot: return "Personal Snapshot"
        case .netWorth: return "Net Worth"
        case .monthlyCashFlow: return "Monthly Cash Flow"
        case .debtSnowballProgress: return "Debt Snowball Progress"
        case .emergencyFundTracker: return "Emergency Fund Tracker"
        case .goalProgress: return "Goal Progress"
        case .upcomingIncome: return "Upcoming Income"
        case .recentTransactions: return "Recent Transactions"
        }
    }

    var systemImage: String {
        switch self {
        case .financialOverview: return "dollarsign.circle.fill"
        case .scoreCircle: return "gauge.with.dots.needle.67percent"
        case .dueToday: return "clock.fill"
        case .thisWeek: return "calendar.badge.clock"
        case .overdueBills: return "exclamationmark.triangle.fill"
        case .incomeSummary: return "chart.line.uptrend.xyaxis"
        case .personalBills: return "house.fill"
        case .businessBills: return "briefcase.fill"
        case .quoteOfTheDay: return "quote.bubble.fill"
        case .notes: return "note.text"
        case .todoList: return "checklist"
        case .upcomingBills: return "tray.full.fill"
        case .paidThisMonth: return "checkmark.seal.fill"
        case .totalIncome: return "banknote.fill"
        case .spendingByCategory: return "chart.pie.fill"
        case .subscriptionTracker: return "repeat.circle.fill"
        case .savingsGoal: return "target"
        case .calendarPreview: return "calendar"
        case .businessSnapshot: return "building.2.fill"
        case .personalSnapshot: return "person.crop.circle.fill"
        case .netWorth: return "scalemass.fill"
        case .monthlyCashFlow: return "arrow.left.arrow.right.circle.fill"
        case .debtSnowballProgress: return "snowflake.circle.fill"
        case .emergencyFundTracker: return "shield.lefthalf.filled"
        case .goalProgress: return "flag.checkered.circle.fill"
        case .upcomingIncome: return "arrow.down.circle.fill"
        case .recentTransactions: return "clock.arrow.circlepath"
        }
    }

    var defaultStyle: DashboardWidgetStyle {
        switch self {
        case .quoteOfTheDay: return .sacredFocus
        case .scoreCircle, .savingsGoal, .emergencyFundTracker, .goalProgress: return .circle
        case .financialOverview, .netWorth, .monthlyCashFlow: return .large
        case .dueToday, .thisWeek, .overdueBills, .paidThisMonth, .totalIncome: return .compact
        default: return .card
        }
    }

    var defaultSize: DashboardWidgetSize {
        switch self {
        case .financialOverview, .scoreCircle, .monthlyCashFlow, .netWorth:
            return .fullWidth
        case .dueToday, .thisWeek, .overdueBills, .paidThisMonth, .totalIncome:
            return .small
        case .quoteOfTheDay, .notes, .todoList, .upcomingBills, .spendingByCategory, .recentTransactions:
            return .large
        default:
            return .medium
        }
    }

    var galleryDescription: String {
        switch self {
        case .financialOverview: return "Personal, business, due today, and overdue totals."
        case .scoreCircle: return "Bill health and organization score rings."
        case .dueToday: return "Bills due today with count and total."
        case .thisWeek: return "Bills due this week."
        case .overdueBills: return "Past-due bills that need attention."
        case .incomeSummary: return "This week and 30-day income."
        case .personalBills: return "Personal monthly bill snapshot."
        case .businessBills: return "Business monthly bill snapshot."
        case .quoteOfTheDay: return "Daily quote in Sacred Focus style."
        case .notes: return "A quick local scratchpad."
        case .todoList: return "Dashboard tasks synced with Sacred Focus."
        case .upcomingBills: return "Next unpaid bills in date order."
        case .paidThisMonth: return "Bills marked paid this month."
        case .totalIncome: return "Income total for the selected dashboard period."
        case .spendingByCategory: return "Top categories for the current month."
        case .subscriptionTracker: return "Recurring subscription bills."
        case .savingsGoal: return "A simple local savings target."
        case .calendarPreview: return "A quick preview of upcoming due dates."
        case .businessSnapshot: return "Business bills, paid, and unpaid totals."
        case .personalSnapshot: return "Personal bills, paid, and unpaid totals."
        case .netWorth: return "Editable assets minus liabilities."
        case .monthlyCashFlow: return "Income minus bills for the current month."
        case .debtSnowballProgress: return "Credit-card and line-of-credit payoff progress."
        case .emergencyFundTracker: return "Track your emergency cash cushion."
        case .goalProgress: return "Track any custom savings or payoff goal."
        case .upcomingIncome: return "Next income entries in date order."
        case .recentTransactions: return "Recent bill and income activity together."
        }
    }
}

struct DashboardWidgetConfiguration: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: DashboardWidgetKind
    var style: DashboardWidgetStyle
    var size: DashboardWidgetSize
    var colorTheme: DashboardWidgetColorTheme
    var titleOverride: String
    var showsDetails: Bool

    init(
        id: UUID = UUID(),
        kind: DashboardWidgetKind,
        style: DashboardWidgetStyle? = nil,
        size: DashboardWidgetSize? = nil,
        colorTheme: DashboardWidgetColorTheme = .sacredGold,
        titleOverride: String = "",
        showsDetails: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.style = style ?? kind.defaultStyle
        self.size = size ?? kind.defaultSize
        self.colorTheme = colorTheme
        self.titleOverride = titleOverride
        self.showsDetails = showsDetails
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, style, size, colorTheme, titleOverride, showsDetails
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.kind = try c.decode(DashboardWidgetKind.self, forKey: .kind)
        self.style = try c.decodeIfPresent(DashboardWidgetStyle.self, forKey: .style) ?? kind.defaultStyle
        self.size = try c.decodeIfPresent(DashboardWidgetSize.self, forKey: .size) ?? kind.defaultSize
        self.colorTheme = try c.decodeIfPresent(DashboardWidgetColorTheme.self, forKey: .colorTheme) ?? .sacredGold
        self.titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride) ?? ""
        self.showsDetails = try c.decodeIfPresent(Bool.self, forKey: .showsDetails) ?? true
    }

    var displayTitle: String {
        let trimmed = titleOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.title : trimmed
    }
}

enum DashboardTemplate: String, CaseIterable, Identifiable {
    case personalFinance
    case businessOwner
    case familyBudget
    case debtPayoff
    case subscriptionManager
    case minimalist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personalFinance: return "Personal Finance"
        case .businessOwner: return "Business Owner"
        case .familyBudget: return "Family Budget"
        case .debtPayoff: return "Debt Payoff"
        case .subscriptionManager: return "Subscription Manager"
        case .minimalist: return "Minimalist"
        }
    }

    var systemImage: String {
        switch self {
        case .personalFinance: return "house.fill"
        case .businessOwner: return "briefcase.fill"
        case .familyBudget: return "person.3.fill"
        case .debtPayoff: return "creditcard.fill"
        case .subscriptionManager: return "repeat.circle.fill"
        case .minimalist: return "circle.grid.cross"
        }
    }

    func widgets() -> [DashboardWidgetConfiguration] {
        switch self {
        case .personalFinance:
            return [
                .init(kind: .scoreCircle),
                .init(kind: .financialOverview),
                .init(kind: .dueToday),
                .init(kind: .thisWeek),
                .init(kind: .monthlyCashFlow),
                .init(kind: .savingsGoal),
                .init(kind: .recentTransactions)
            ]
        case .businessOwner:
            return [
                .init(kind: .businessSnapshot, colorTheme: .forestGreen),
                .init(kind: .incomeSummary, colorTheme: .forestGreen),
                .init(kind: .monthlyCashFlow, colorTheme: .forestGreen),
                .init(kind: .upcomingIncome, colorTheme: .forestGreen),
                .init(kind: .spendingByCategory, colorTheme: .forestGreen),
                .init(kind: .calendarPreview, colorTheme: .forestGreen)
            ]
        case .familyBudget:
            return [
                .init(kind: .personalSnapshot),
                .init(kind: .dueToday),
                .init(kind: .thisWeek),
                .init(kind: .upcomingBills),
                .init(kind: .todoList),
                .init(kind: .emergencyFundTracker)
            ]
        case .debtPayoff:
            return [
                .init(kind: .scoreCircle),
                .init(kind: .debtSnowballProgress, colorTheme: .midnightBlack),
                .init(kind: .overdueBills, colorTheme: .midnightBlack),
                .init(kind: .monthlyCashFlow, colorTheme: .midnightBlack),
                .init(kind: .goalProgress, colorTheme: .midnightBlack),
                .init(kind: .notes, colorTheme: .midnightBlack)
            ]
        case .subscriptionManager:
            return [
                .init(kind: .subscriptionTracker, colorTheme: .oceanBlue),
                .init(kind: .upcomingBills, colorTheme: .oceanBlue),
                .init(kind: .monthlyCashFlow, colorTheme: .oceanBlue),
                .init(kind: .paidThisMonth, colorTheme: .oceanBlue),
                .init(kind: .calendarPreview, colorTheme: .oceanBlue)
            ]
        case .minimalist:
            return [
                .init(kind: .dueToday, style: .minimal, colorTheme: .light),
                .init(kind: .thisWeek, style: .minimal, colorTheme: .light),
                .init(kind: .scoreCircle, style: .minimal, colorTheme: .light),
                .init(kind: .quoteOfTheDay)
            ]
        }
    }
}

enum DashboardWidgetLayoutStore {
    private static let key = "sbt.dashboard.editableWidgets.v2"
    private static let editableV1Key = "sbt.dashboard.editableWidgets.v1"
    private static let legacyOrderKey = "sbt.dash.widgetOrder.v1"

    static func defaultWidgets() -> [DashboardWidgetConfiguration] {
        [
            .init(kind: .financialOverview, style: .large),
            .init(kind: .scoreCircle, style: .circle),
            .init(kind: .dueToday, style: .compact),
            .init(kind: .thisWeek, style: .compact),
            .init(kind: .overdueBills, style: .compact),
            .init(kind: .incomeSummary, style: .card),
            .init(kind: .personalBills, style: .card),
            .init(kind: .businessBills, style: .card)
        ]
    }

    static func load(defaults: UserDefaults = .standard) -> [DashboardWidgetConfiguration] {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DashboardWidgetConfiguration].self, from: data),
           !decoded.isEmpty {
            save(decoded, defaults: defaults)
            return decoded
        }
        if let data = defaults.data(forKey: editableV1Key),
           let decoded = try? JSONDecoder().decode([DashboardWidgetConfiguration].self, from: data),
           !decoded.isEmpty {
            save(decoded, defaults: defaults)
            return decoded
        }
        if let migrated = migrateLegacyOrder(defaults: defaults), !migrated.isEmpty {
            save(migrated, defaults: defaults)
            return migrated
        }
        return defaultWidgets()
    }

    static func save(_ widgets: [DashboardWidgetConfiguration], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(widgets) else { return }
        defaults.set(data, forKey: key)
    }

    private static func migrateLegacyOrder(defaults: UserDefaults) -> [DashboardWidgetConfiguration]? {
        guard let raw = defaults.string(forKey: legacyOrderKey), !raw.isEmpty else { return nil }
        let mapped = raw
            .split(separator: ",")
            .compactMap { legacyKind(rawValue: String($0)) }
            .map { DashboardWidgetConfiguration(kind: $0, style: $0.defaultStyle) }
        return mapped.isEmpty ? nil : mapped
    }

    private static func legacyKind(rawValue: String) -> DashboardWidgetKind? {
        switch rawValue {
        case "incomeOverview": return .financialOverview
        case "healthScore": return .scoreCircle
        case "quickStats": return .financialOverview
        case "riskAlerts": return .overdueBills
        case "cashFlow": return .financialOverview
        case "priority": return .upcomingBills
        case "overdue": return .overdueBills
        case "upcoming": return .upcomingBills
        case "snapshot": return .spendingByCategory
        default: return nil
        }
    }
}

struct EditableDashboardWidgetCard<Content: View>: View {
    let configuration: DashboardWidgetConfiguration
    let isEditing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void
    let onEdit: () -> Void
    let onStyleChange: (DashboardWidgetStyle) -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if configuration.style == .sacredFocus {
                baseCard
                    .environment(\.colorScheme, .dark)
            } else {
                baseCard
            }
        }
        .animation(.easeInOut(duration: 0.18), value: configuration.style)
        .animation(.easeInOut(duration: 0.18), value: configuration.size)
        .animation(.easeInOut(duration: 0.18), value: configuration.colorTheme)
    }

    private var baseCard: some View {
        VStack(alignment: .leading, spacing: spacing) {
            header
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, minHeight: configuration.size.minHeight, alignment: .topLeading)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: configuration.kind.systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 30, height: 30)
                .background(iconBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(configuration.displayTitle)
                .font(titleFont)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            if isEditing {
                editControls
            }
        }
    }

    private var editControls: some View {
        HStack(spacing: 8) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .disabled(!canMoveUp)
            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .disabled(!canMoveDown)
            Menu {
                ForEach(DashboardWidgetStyle.allCases) { style in
                    Button {
                        onStyleChange(style)
                    } label: {
                        Label(style.title, systemImage: style == configuration.style ? "checkmark" : "rectangle")
                    }
                }
            } label: {
                Image(systemName: "paintpalette.fill")
            }
            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill")
            }
        }
        .font(.caption.weight(.bold))
        .buttonStyle(.borderless)
        .foregroundStyle(controlColor)
        .accessibilityElement(children: .contain)
    }

    private var padding: CGFloat {
        switch configuration.style {
        case .compact: return 14
        case .minimal: return 12
        case .circle: return 18
        case .large, .card, .sacredFocus: return 18
        }
    }

    private var spacing: CGFloat {
        configuration.style == .compact ? 10 : 14
    }

    private var cornerRadius: CGFloat {
        switch configuration.style {
        case .circle: return 32
        case .minimal: return 14
        default: return 22
        }
    }

    private var titleFont: Font {
        switch configuration.style {
        case .compact, .minimal: return .subheadline.weight(.bold)
        case .large, .circle, .sacredFocus: return .title3.weight(.bold)
        case .card: return .headline.weight(.bold)
        }
    }

    private var background: some ShapeStyle {
        switch configuration.style {
        case .sacredFocus:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.appSacredBlack, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .minimal:
            return AnyShapeStyle(Color.clear)
        case .circle:
            return AnyShapeStyle(configuration.colorTheme.softFill)
        default:
            return AnyShapeStyle(configuration.colorTheme == .light ? Theme.Color.card : configuration.colorTheme.softFill)
        }
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(borderColor, lineWidth: configuration.style == .minimal ? 0.8 : 1)
    }

    private var borderColor: Color {
        switch configuration.style {
        case .sacredFocus: return Color.appAccent.opacity(0.35)
        case .minimal: return configuration.colorTheme.border.opacity(0.8)
        case .circle: return configuration.colorTheme.border
        default: return configuration.colorTheme.border
        }
    }

    private var iconColor: Color {
        configuration.style == .sacredFocus ? Color.appAccent : configuration.colorTheme.accent
    }

    private var iconBackground: Color {
        configuration.style == .sacredFocus ? Color.white.opacity(0.08) : configuration.colorTheme.accent.opacity(0.14)
    }

    private var titleColor: Color {
        configuration.style == .sacredFocus ? .white : .primary
    }

    private var controlColor: Color {
        configuration.style == .sacredFocus ? Color.appAccent : configuration.colorTheme.accent
    }

    private var shadowColor: Color {
        configuration.style == .minimal ? .clear : Color.black.opacity(configuration.style == .sacredFocus ? 0.22 : 0.08)
    }

    private var shadowRadius: CGFloat {
        configuration.style == .minimal ? 0 : 14
    }

    private var shadowY: CGFloat {
        configuration.style == .minimal ? 0 : 6
    }
}

struct WidgetGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    let hiddenKinds: [DashboardWidgetKind]
    let onAdd: (DashboardWidgetKind) -> Void

    var body: some View {
        NavigationStack {
            List {
                if hiddenKinds.isEmpty {
                    ContentUnavailableView(
                        "All widgets added",
                        systemImage: "checkmark.seal.fill",
                        description: Text("Remove a widget from the editable dashboard to add it again later.")
                    )
                } else {
                    Section("Widget Gallery") {
                        ForEach(hiddenKinds) { kind in
                            Button {
                                onAdd(kind)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: kind.systemImage)
                                        .foregroundStyle(Color.appAccentText)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(kind.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(kind.galleryDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Widget Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

struct DashboardWidgetSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DashboardWidgetConfiguration
    let onSave: (DashboardWidgetConfiguration) -> Void

    init(configuration: DashboardWidgetConfiguration, onSave: @escaping (DashboardWidgetConfiguration) -> Void) {
        _draft = State(initialValue: configuration)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Widget") {
                    TextField("Widget title", text: $draft.titleOverride)
                    Picker("Style", selection: $draft.style) {
                        ForEach(DashboardWidgetStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    Picker("Size", selection: $draft.size) {
                        ForEach(DashboardWidgetSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    Picker("Color Theme", selection: $draft.colorTheme) {
                        ForEach(DashboardWidgetColorTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    Toggle("Show details", isOn: $draft.showsDetails)
                }
                Section {
                    Label(draft.kind.galleryDescription, systemImage: draft.kind.systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct DashboardNotesWidget: View {
    @StateObject private var notes = QuickNotesStore()
    @State private var draft = ""
    let style: DashboardWidgetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Add a note", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
            if notes.notes.isEmpty {
                Text("No notes yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notes.notes.prefix(style == .compact ? 2 : 4)) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(Color.appAccent)
                            .padding(.top, 7)
                        Text(note.text)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            notes.delete(note)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func add() {
        notes.add(draft)
        draft = ""
    }
}

struct DashboardTodoWidget: View {
    @EnvironmentObject private var todoStore: TodoStore
    @State private var draft = ""
    let style: DashboardWidgetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Add a task", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
            if visibleItems.isEmpty {
                Text("No tasks yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleItems) { task in
                    HStack(spacing: 9) {
                        Button {
                            todoStore.toggleComplete(task)
                        } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isComplete ? Color.appHouseholdText : Color.appAccentText)
                        }
                        .buttonStyle(.plain)
                        Text(task.title)
                            .font(.subheadline)
                            .strikethrough(task.isComplete)
                            .foregroundStyle(task.isComplete ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private var visibleItems: [FocusTodo] {
        Array(todoStore.items.prefix(style == .compact ? 3 : 6))
    }

    private func add() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        todoStore.add(FocusTodo(title: trimmed))
        draft = ""
    }
}

struct DashboardSavingsGoalWidget: View {
    @AppStorage("sbt.dashboard.savingsGoal.name.v1") private var goalName = "Emergency Fund"
    @AppStorage("sbt.dashboard.savingsGoal.current.v1") private var currentAmount = 0.0
    @AppStorage("sbt.dashboard.savingsGoal.target.v1") private var targetAmount = 1000.0
    let style: DashboardWidgetStyle

    private var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, max(0, currentAmount / targetAmount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Goal name", text: $goalName)
                .textFieldStyle(.roundedBorder)
            ProgressView(value: progress)
                .tint(Color.appAccent)
            HStack {
                moneyField("Saved", value: $currentAmount)
                moneyField("Goal", value: $targetAmount)
            }
            Text("\(Int(progress * 100))% funded")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func moneyField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct DashboardNetWorthWidget: View {
    @AppStorage("sbt.dashboard.netWorth.assets.v1") private var assets = 0.0
    @AppStorage("sbt.dashboard.netWorth.liabilities.v1") private var liabilities = 0.0
    let style: DashboardWidgetStyle

    private var netWorth: Double { assets - liabilities }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(netWorth, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                .foregroundStyle(netWorth >= 0 ? Color.appAccentText : Color.appDangerText)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            HStack {
                moneyField("Assets", value: $assets)
                moneyField("Liabilities", value: $liabilities)
            }
            if style != .compact {
                Text("Net worth updates locally as you edit assets and liabilities.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moneyField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct DashboardEmergencyFundWidget: View {
    @AppStorage("sbt.dashboard.emergencyFund.current.v1") private var currentAmount = 0.0
    @AppStorage("sbt.dashboard.emergencyFund.target.v1") private var targetAmount = 2500.0
    let style: DashboardWidgetStyle

    private var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, max(0, currentAmount / targetAmount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(value: progress)
                .tint(Color.appAccent)
            HStack {
                moneyField("Saved", value: $currentAmount)
                moneyField("Target", value: $targetAmount)
            }
            Text("\(Int(progress * 100))% funded")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            if style != .compact {
                Text("Keep a cushion for surprises before they become emergencies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moneyField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct DashboardGoalProgressWidget: View {
    @AppStorage("sbt.dashboard.goal.name.v1") private var goalName = "Next Goal"
    @AppStorage("sbt.dashboard.goal.current.v1") private var currentAmount = 0.0
    @AppStorage("sbt.dashboard.goal.target.v1") private var targetAmount = 500.0
    let style: DashboardWidgetStyle

    private var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, max(0, currentAmount / targetAmount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Goal name", text: $goalName)
                .textFieldStyle(.roundedBorder)
            ProgressView(value: progress)
                .tint(Color.appAccent)
            HStack {
                moneyField("Current", value: $currentAmount)
                moneyField("Target", value: $targetAmount)
            }
            Text("\(Int(progress * 100))% complete")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
            if style != .compact {
                Text(goalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Track a goal that matters." : goalName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func moneyField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
        }
    }
}

// MARK: - Daily Quote Banner (REMOVED v1.0.9)
//
// Folded into `SacredDailyFocusCard`. The old `DailyQuoteBanner`
// struct has been deleted; if you ever need its layout back, check
// git history for `Views/Dashboard/DashboardView.swift` before
// v1.0.9.

// MARK: - Sacred Focus Hub Card (reference layout, expanded)
//
// The premium black Sacred card now holds three things behind a compact
// segmented switcher so the dashboard stays calm:
//   • Daily quote (with Share)
//   • Quick Notes
//   • Quick To-Do (writes to the shared TodoStore, so items also appear
//     inside Sacred Focus)
//
struct SacredFocusHubCard: View {

    let quote: MotivationalQuote
    /// Active bills already scoped by the dashboard's All/Personal/Business
    /// toggle. Drives the Schedule tab (no dependency on store.filter).
    var scheduleBills: [Bill] = []

    @EnvironmentObject private var todoStore: TodoStore
    @StateObject private var notes = QuickNotesStore()

    private enum Tab: String, CaseIterable, Identifiable {
        case quote    = "Quote"
        case schedule = "Schedule"
        case todo     = "To-Do"
        case notes    = "Notes"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .quote:    return "quote.bubble.fill"
            case .schedule: return "calendar"
            case .todo:     return "checklist"
            case .notes:    return "note.text"
            }
        }
    }

    @State private var tab: Tab = .quote
    @State private var noteDraft = ""
    @State private var taskDraft = ""
    @FocusState private var fieldFocused: Bool

    private static let appStoreURL =
        "https://apps.apple.com/us/app/sacred-bill-tracker/id6762890363"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandRow
            switcher
            Group {
                switch tab {
                case .quote:    quoteContent
                case .schedule: scheduleContent
                case .todo:     todoContent
                case .notes:    notesContent
                }
            }
            .animation(.easeInOut(duration: 0.2), value: tab)
        }
        .padding(16)
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
                .stroke(Color.appAccent.opacity(0.30), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 8)
    }

    // MARK: Brand row

    private var brandRow: some View {
        HStack(spacing: 12) {
            brandIcon
            VStack(alignment: .leading, spacing: 1) {
                Text("Sacred Bill Tracker")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.appAccent)
                Text("Rooted in what matters.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            if tab == .todo, openTaskCount > 0 {
                Text("\(openTaskCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appOnGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.appAccent))
            }
        }
    }

    private var openTaskCount: Int {
        todoStore.items.filter { !$0.isComplete }.count
    }

    /// App icon (Assets.xcassets → AppLogo). Falls back to a branded gold
    /// finance badge — never the leaf — if the asset is unavailable.
    private var brandIcon: some View {
        Group {
            if UIImage(named: "AppLogo") != nil {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Circle().fill(Color.appAccent.opacity(0.20))
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.appLime.opacity(0.85), lineWidth: 1.5))
    }

    // MARK: Switcher

    private var switcher: some View {
        HStack(spacing: 5) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                    fieldFocused = false
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: t.icon).font(.caption2)
                        Text(t.rawValue)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        Capsule().fill(tab == t ? Color.appAccent : Color.white.opacity(0.08))
                    )
                    .foregroundStyle(tab == t ? Color.appOnGold : Color.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Quote

    private var quoteContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "quote.opening")
                .font(.title3)
                .foregroundStyle(Color.appAccent.opacity(0.85))
            Text(quote.text)
                .font(.system(.title3, design: .serif).weight(.medium))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            HStack {
                if !quote.author.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("— \(quote.author)")
                        .font(.subheadline)
                        .foregroundStyle(Color.appAccent)
                }
                Spacer()
                ShareLink(item: shareText, subject: Text("Quote from Sacred Bill Tracker")) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appAccent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share today's quote")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shareText: String {
        var parts: [String] = ["“\(quote.text)”"]
        let author = quote.author.trimmingCharacters(in: .whitespaces)
        if !author.isEmpty { parts.append("— \(author)") }
        parts.append("")
        parts.append("Sent from Sacred Bill Tracker")
        parts.append(Self.appStoreURL)
        return parts.joined(separator: "\n")
    }

    // MARK: Notes

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickAddRow(placeholder: "Add a quick note…", draft: $noteDraft) {
                notes.add(noteDraft); noteDraft = ""
            }
            if notes.notes.isEmpty {
                emptyHint("Jot anything — a reminder, a number, a thought.")
            } else {
                VStack(spacing: 8) {
                    ForEach(notes.notes.prefix(4)) { note in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color.appAccent)
                                .padding(.top, 6)
                            Text(note.text)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                notes.delete(note)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if notes.notes.count > 4 {
                    Text("+ \(notes.notes.count - 4) more")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: Schedule (real bill data, scoped by the dashboard toggle)

    private var scheduleOverdue: [Bill] {
        scheduleBills.filter { $0.isOverdue }.sorted { $0.dueDate < $1.dueDate }
    }
    private var scheduleToday: [Bill] {
        scheduleBills.filter { $0.isDueToday && !$0.isPaid }.sorted { $0.dueDate < $1.dueDate }
    }
    private var scheduleUpcoming: [Bill] {
        let today = Calendar.current.startOfDay(for: Date())
        return scheduleBills
            .filter { !$0.isPaid && !$0.isDueToday && Calendar.current.startOfDay(for: $0.dueDate) >= today }
            .sorted { $0.dueDate < $1.dueDate }
    }
    private var schedulePaidThisMonth: Int {
        scheduleBills.filter { $0.isPaid && $0.isDueThisMonth }.count
    }

    private var scheduleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quick counts.
            HStack(spacing: 6) {
                countChip("Due Today", scheduleToday.count,    Color.appAccent)
                countChip("Upcoming",  scheduleUpcoming.count,  Color.appLime)
                countChip("Overdue",   scheduleOverdue.count,   Color.appDanger)
                countChip("Paid",      schedulePaidThisMonth,   .green)
            }
            if scheduleOverdue.isEmpty && scheduleToday.isEmpty && scheduleUpcoming.isEmpty {
                emptyHint("Nothing scheduled. Add a bill to see it here.")
            } else {
                scheduleSection(title: "Overdue",   bills: Array(scheduleOverdue.prefix(4)))
                scheduleSection(title: "Due Today", bills: Array(scheduleToday.prefix(4)))
                scheduleSection(title: "Upcoming",  bills: Array(scheduleUpcoming.prefix(6)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countChip(_ label: String, _ value: Int, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func scheduleSection(title: String, bills: [Bill]) -> some View {
        if !bills.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)
                ForEach(bills) { scheduleRow($0) }
            }
        }
    }

    private func scheduleRow(_ bill: Bill) -> some View {
        HStack(spacing: 10) {
            Image(systemName: bill.type.systemImage)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(bill.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(bill.dueDate, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 6)
            Text(bill.formattedAmount)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.appAccent)
            statusPill(bill.effectiveStatus)
        }
    }

    private func statusPill(_ status: PaymentStatus) -> some View {
        Text(status.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(status.color.opacity(0.20)))
    }

    // MARK: To-Do (full list — add / complete / delete / active+completed)

    private var todoContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            quickAddRow(placeholder: "Add a task…", draft: $taskDraft) {
                let trimmed = taskDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                todoStore.add(FocusTodo(title: trimmed))
                taskDraft = ""
            }
            if todoStore.items.isEmpty {
                emptyHint("Add what needs doing. Tap the circle to complete.")
            } else {
                VStack(spacing: 8) {
                    ForEach(todoStore.items) { task in
                        HStack(spacing: 10) {
                            Button {
                                todoStore.toggleComplete(task)
                            } label: {
                                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isComplete ? Color.appLime : Color.appAccent)
                            }
                            .buttonStyle(.plain)
                            Text(task.title)
                                .font(.callout)
                                .strikethrough(task.isComplete, color: .white.opacity(0.4))
                                .foregroundStyle(task.isComplete ? .white.opacity(0.4) : .white.opacity(0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                todoStore.delete(task)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text("\(activeTaskCount) active • \(completedTaskCount) done")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if completedTaskCount > 0 {
                        Button {
                            for task in todoStore.items where task.isComplete {
                                todoStore.delete(task)
                            }
                        } label: {
                            Text("Clear Completed")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeTaskCount: Int {
        todoStore.items.filter { !$0.isComplete }.count
    }

    private var completedTaskCount: Int {
        todoStore.items.filter { $0.isComplete }.count
    }

    // MARK: Shared bits

    private func quickAddRow(
        placeholder: String,
        draft: Binding<String>,
        submit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            TextField("", text: draft, prompt: Text(placeholder).foregroundColor(.white.opacity(0.4)))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($fieldFocused)
                .foregroundStyle(.white)
                .onSubmit(submit)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            Button(action: submit) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.appOnGold)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.appAccent))
            }
            .buttonStyle(.plain)
            .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.45))
            .padding(.vertical, 6)
    }
}

// MARK: - Quick Notes store (local, dashboard scratchpad)

struct SacredQuickNote: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

@MainActor
final class QuickNotesStore: ObservableObject {

    @Published private(set) var notes: [SacredQuickNote] = []

    private let key = "sbt.dashboard.quicknotes.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(SacredQuickNote(text: trimmed), at: 0)
        persist()
    }

    func delete(_ note: SacredQuickNote) {
        notes.removeAll { $0.id == note.id }
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        notes = (try? JSONDecoder().decode([SacredQuickNote].self, from: data)) ?? []
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Dashboard Score Circles (Bill Health + Financial Organization)

struct DashboardScoreCircles: View {

    let bills: [Bill]
    var onHealthTap: (() -> Void)? = nil

    private var health: BillHealthScore { BillHealthScore.compute(from: bills) }
    private var org: FinancialOrganizationScore { FinancialOrganizationScore.compute(from: bills) }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let onHealthTap {
                    Button(action: onHealthTap) { healthRing }
                        .buttonStyle(.plain)
                } else {
                    healthRing
                }
            }
            DashboardScoreRing(
                title: "Organization",
                score: org.score,
                label: org.status.rawValue,
                systemImage: org.status.systemImage,
                tint: orgColor
            )
        }
    }

    private var healthRing: some View {
        DashboardScoreRing(
            title: "Bill Health",
            score: health.score,
            label: health.status.rawValue,
            systemImage: health.status.systemImage,
            tint: healthColor
        )
        .contentShape(Rectangle())
    }

    private var healthColor: Color {
        switch health.status {
        case .great:     return .appHousehold
        case .attention: return .appAccent
        case .overdue:   return .appDanger
        }
    }

    private var orgColor: Color {
        switch org.status {
        case .solid:    return .appHousehold
        case .building: return .appAccent
        case .empty:    return .secondary
        }
    }
}

struct DashboardScoreRing: View {
    let title: String
    let score: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.14), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: score)
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("/100")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 72, height: 72)
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.caption2)
                        .foregroundStyle(tint)
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
        .accessibilityLabel("\(title): \(score) out of 100. \(label).")
    }
}

// MARK: - Financial Organization Score
//
// Deterministic companion to BillHealthScore. BillHealthScore answers
// "are my bills under control right now?"; this answers "how organized is
// my setup?" — recurrence, autopay, categorization, documentation.
// 100-point model, proportional to the tracked (non-deleted) bill set.
//
struct FinancialOrganizationScore {

    let score: Int
    let status: Status

    enum Status: String {
        case empty    = "Start tracking"
        case building = "Getting organized"
        case solid    = "Well organized"

        var systemImage: String {
            switch self {
            case .empty:    return "tray"
            case .building: return "square.stack.3d.up"
            case .solid:    return "checkmark.seal.fill"
            }
        }
    }

    static func compute(from bills: [Bill]) -> FinancialOrganizationScore {
        let tracked = bills.filter { $0.deletedAt == nil }
        guard !tracked.isEmpty else {
            return FinancialOrganizationScore(score: 0, status: .empty)
        }
        let total = Double(tracked.count)

        let categorized = tracked.filter { $0.category != .other }.count
        let recurring   = tracked.filter { $0.recurrence.isRecurring }.count
        let autopay     = tracked.filter { $0.autoPay }.count
        let documented  = tracked.filter {
            !$0.notes.trimmingCharacters(in: .whitespaces).isEmpty
            || !($0.paymentURL ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }.count

        var s = 0.0
        s += (Double(categorized) / total) * 30
        s += (Double(recurring)   / total) * 25
        s += (Double(autopay)     / total) * 20
        s += (Double(documented)  / total) * 25

        let rounded = max(0, min(100, Int(s.rounded())))
        let status: Status = rounded >= 75 ? .solid : .building
        return FinancialOrganizationScore(score: rounded, status: status)
    }
}

#Preview {
    DashboardView()
        .environmentObject(BillStore())
        .environmentObject(IncomeStore())
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionManager())
        .environmentObject(ScheduleStore())
        .environmentObject(TodoStore())
}
