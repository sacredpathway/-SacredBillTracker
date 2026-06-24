//
//  BillsView.swift
//  SacredBillTracker
//

import SwiftUI

struct BillsView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var incomeStore: IncomeStore
    @EnvironmentObject private var profileStore: ManagedProfileStore
    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var auth: AuthService
    @State private var showAdd = false
    @State private var showPaywall = false
    @State private var searchText = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var scope: BillScope = .mine

    /// v1.0.9 — Single-source bill-edit trigger. `sheet(item:)` is
    /// inherently idempotent: setting it to the same bill twice does
    /// NOT stack a second sheet. Replaces the legacy `NavigationLink`
    /// → `BillDetailView` → "Edit" two-screen flow that the user
    /// perceived as "stacking new pages".
    @State private var billToEdit: Bill?

    // v1.6 — Sacred leaf scroll background tracking.
    @State private var sbtLeafScrollOffset: CGFloat = 0

    /// Persisted sort selection (v1.3). Survives app relaunch and is
    /// shared across the Bills screen only — Dashboard / Calendar /
    /// Reports keep their domain-specific orderings.
    @AppStorage("sbt.bills.sortOption.v1") private var sortRaw: String =
        BillSortOption.dueSoonest.rawValue

    private var sortOption: BillSortOption {
        get { BillSortOption(rawValue: sortRaw) ?? .dueSoonest }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case all, unpaid, paid, overdue
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .unpaid: return "Unpaid"
            case .paid: return "Paid"
            case .overdue: return "Overdue"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // v1.6 — Sacred leaf scroll background sits behind the List.
                // The List uses `.scrollContentBackground(.hidden)` so the
                // leaf field shows through. Reduce Motion is honored inside
                // SacredLeafScrollBackground.
                SacredLeafScrollBackground(scrollOffset: sbtLeafScrollOffset)
                    .background(Theme.Color.background.ignoresSafeArea())

            VStack(spacing: 0) {
                ProfileSwitcherBar()
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Partner Budgeting backend is live (v1.0.5). My / Shared
                // scope picker so users can switch between their own
                // bills and bills shared with their partner.
                //
                // Build 17 fix — segmented selection visual:
                // The previous implementation wrapped each segment in
                // an HStack(Image + Text). UIKit's segmented control
                // (which `.pickerStyle(.segmented)` bridges to) measures
                // the *intrinsic* size of each segment's content; mixed
                // Image+Text containers caused inconsistent widths and
                // the selection indicator only rendering under the
                // first segment. Plain `Text` per segment makes the
                // segments equal-width and the indicator slides cleanly
                // between them.
                Picker("Scope", selection: $scope) {
                    ForEach(BillScope.allCases) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                FilterPicker(selection: $store.filter)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Picker("Status", selection: $statusFilter) {
                    ForEach(StatusFilter.allCases) { f in
                        Text(f.title).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                content
            }
            } // end ZStack (v1.6 leaf background)
            .navigationTitle("Bills")
            .searchable(text: $searchText, prompt: "Search bills")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    shareSummaryButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sortMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if canAddBill {
                            showAdd = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel("Add Bill")
                }
            }
            .sheet(isPresented: $showAdd) {
                QuickAddView()
            }
            .paywallSheet(isPresented: $showPaywall,
                          reason: "Free is capped at \(FreeTierLimits.maxBills) bills. Pro makes it unlimited.")
        }
    }

    /// True when the user can add another bill under their current tier.
    /// Essential ($4.99) and up lift the free bill cap.
    private var canAddBill: Bool {
        subs.canUnlimitedBills || store.allStoredBills.count < FreeTierLimits.maxBills
    }

    /// Native iOS share button — pipes a plain-text summary of the
    /// currently-visible bills through `UIActivityViewController` via
    /// SwiftUI's `ShareLink`. Respects the active scope / search /
    /// status filter so what the user sees is what gets shared.
    ///
    /// PRIVACY: the generator never reads `Bill.notes`. Local-only —
    /// nothing is uploaded; the user picks the destination (Messages,
    /// Mail, Notes, AirDrop, …) from the system share sheet.
    private var shareSummaryButton: some View {
        ShareLink(
            item: BillShareService.makeSummary(
                bills: visibleBills,
                income: BillShareService.IncomeAggregates(
                    thisWeek:   incomeStore.thisWeekTotal,
                    last30Days: incomeStore.last30DaysTotal,
                    thisMonth:  incomeStore.thisMonthTotal,
                    allTime:    incomeStore.allTimeTotal
                )
            ),
            subject: Text("Sacred Bill Tracker Summary"),
            message: Text("My current bill summary")
        ) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
        }
        .accessibilityLabel("Share bill summary")
        .accessibilityHint("Opens the iOS share sheet so you can send your bill summary to Messages, Mail, Notes, or AirDrop.")
        .disabled(visibleBills.isEmpty)
    }

    /// Sort menu — native iOS Picker inside a Menu so the current
    /// selection is shown via the system checkmark. Tap any row to
    /// re-sort instantly; the selection persists via @AppStorage.
    private var sortMenu: some View {
        Menu {
            Picker(selection: Binding(
                get: { sortOption },
                set: { sortRaw = $0.rawValue }
            )) {
                ForEach(BillSortOption.allCases) { opt in
                    Label(opt.title, systemImage: opt.systemImage).tag(opt)
                }
            } label: {
                Text("Sort By")
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .font(.title3)
        }
        .accessibilityLabel("Sort bills")
    }

    /// Empty state, scope-aware. The "Shared Bills" tab gets a different
    /// message because the user can't fix it by tapping + (only their
    /// partner can flip a bill's share toggle).
    @ViewBuilder
    private var emptyState: some View {
        switch scope {
        case .mine:
            EmptyStateView(
                systemImage: "tray",
                title: searchText.isEmpty ? emptyMineTitle : "No bills found",
                message: searchText.isEmpty
                    ? emptyMineMessage
                    : "No bills match your search."
            )
        case .shared:
            EmptyStateView(
                systemImage: "person.2.slash",
                title: "Nothing shared yet",
                message: "Bills your partner shares with you appear here. Ask them to toggle Share with partner on a bill in their app."
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        let list = visibleBills
        if list.isEmpty {
            emptyState
                .padding(.top, 40)
            Spacer()
        } else {
            List {
                ForEach(list) { bill in
                    Button {
                        // Tap the row → open Edit sheet directly. Using
                        // sheet(item:) below means tapping again while
                        // a sheet is presenting is a no-op (no double
                        // stack).
                        billToEdit = bill
                    } label: {
                        BillRowView(bill: bill, maxUnpaidAmount: store.maxUnpaidAmount)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        // Partner-owned bills are read-only — swipe actions
                        // would silently fail at RLS so we hide them.
                        if !isPartnerOwned(bill) {
                            Button(role: .destructive) {
                                store.delete(bill)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if !bill.isPaid {
                                Button {
                                    store.markPaid(bill)
                                } label: {
                                    Label("Paid", systemImage: "checkmark.seal.fill")
                                }
                                .tint(.green)
                            } else {
                                Button {
                                    store.markUnpaid(bill)
                                } label: {
                                    Label("Unpaid", systemImage: "clock.fill")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            // v1.6 — let the leaf background show through the List
            .scrollContentBackground(.hidden)
            .refreshable { await store.reload() }
            // v1.0.9 — single-shot edit sheet. sheet(item:) is
            // idempotent and ties the presented sheet to a specific
            // Bill identity, so the form always opens against the row
            // the user actually tapped.
            .sheet(item: $billToEdit) { bill in
                AddEditBillView(mode: .edit(bill))
                    .environmentObject(store)
                    .environmentObject(subs)
                    .environmentObject(auth)
            }
        }
    }

    /// True when the bill is loaded from the server with an owner that
    /// isn't the signed-in user — i.e. a partner-shared bill.
    private func isPartnerOwned(_ bill: Bill) -> Bool {
        guard let owner = bill.ownerUserID, let me = auth.currentUserID else { return false }
        return owner != me
    }

    private var visibleBills: [Bill] {
        let base: [Bill]
        switch scope {
        case .mine:
            base = store.filteredBills
        case .shared:
            base = store.allStoredBills
                .filter { store.filter.matches($0.type) }
                .filtered(by: .shared, currentUserID: auth.currentUserID)
        }

        let pool = base.filter { bill in
            let matchesSearch = searchText.isEmpty
                || bill.name.localizedCaseInsensitiveContains(searchText)
                || bill.notes.localizedCaseInsensitiveContains(searchText)
                || bill.category.title.localizedCaseInsensitiveContains(searchText)

            let matchesStatus: Bool
            switch statusFilter {
            case .all:     matchesStatus = true
            case .unpaid:  matchesStatus = bill.effectiveStatus == .unpaid
            case .paid:    matchesStatus = bill.effectiveStatus == .paid
            case .overdue: matchesStatus = bill.effectiveStatus == .overdue
            }
            return matchesSearch && matchesStatus
        }
        return pool.sorted(by: sortOption)
    }

    private var emptyMineTitle: String {
        if store.allStoredBills.isEmpty { return "No bills yet" }
        if profileStore.selection == .allProfiles { return "No bills yet" }
        return "No bills in this profile"
    }

    private var emptyMineMessage: String {
        if store.allStoredBills.isEmpty {
            return "No bills yet — tap + to add your first one."
        }
        if profileStore.selection == .allProfiles {
            return "No bills yet — tap + to add your first one."
        }
        return "Add a bill here or switch to All Profiles."
    }
}

#Preview {
    BillsView()
        .environmentObject(BillStore())
        .environmentObject(IncomeStore())
        .environmentObject(ManagedProfileStore.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(SubscriptionManager())
}
