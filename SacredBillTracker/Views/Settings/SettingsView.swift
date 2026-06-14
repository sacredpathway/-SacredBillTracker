//
//  SettingsView.swift
//  SacredBillTracker
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var incomeStore: IncomeStore
    @EnvironmentObject private var profileStore: ManagedProfileStore
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var subs: SubscriptionManager

    #if DEBUG
    @State private var showResetConfirm = false
    #endif
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var showPaywall = false
    @State private var paywallReason: String?

    // Income-tracking preferences (v1.2.2). Persist via AppStorage so
    // every income-aware view (Dashboard, AddEditIncomeView,
    // IncomeListView) reads the same values without a custom store.
    @AppStorage("sbt.income.period.v1") private var incomePeriodRaw: String = IncomePeriod.weekly.rawValue
    @AppStorage("sbt.income.weekStartDay.v1") private var weekStartDayRaw: Int = WeekStartDay.monday.rawValue

    /// v1.0.9 — Appearance preference. Applied at the app root via
    /// `.preferredColorScheme(_:)` so light/dark flips take effect
    /// immediately across the whole app. Default = system.
    @AppStorage("sbt.appearance.v1") private var appearanceRaw: String = AppearancePreference.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Notifications") {
                    HStack {
                        Label("Permission", systemImage: "bell.badge.fill")
                        Spacer()
                        Text(authStatusText)
                            .foregroundStyle(authStatusColor)
                    }
                    if notifications.authorizationStatus != .authorized {
                        Button {
                            Task { _ = await notifications.requestAuthorization() }
                        } label: {
                            Label("Enable Notifications", systemImage: "bell")
                        }
                    }
                    Stepper(value: Binding(
                        get: { notifications.leadTimeDays },
                        set: { notifications.leadTimeDays = $0
                               Task { await notifications.rescheduleAll(for: store.allStoredBills) } }
                    ), in: 0...14) {
                        HStack {
                            Text("Remind")
                            Spacer()
                            Text("\(notifications.leadTimeDays) day\(notifications.leadTimeDays == 1 ? "" : "s") before")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    if subs.isPro {
                        HStack {
                            Label("Current plan", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Color.appAccent)
                            Spacer()
                            Text(subs.currentTier.displayName)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            Task { await subs.openManageSubscriptions() }
                        } label: {
                            Label("Manage Subscription", systemImage: "creditcard")
                        }
                    } else {
                        Button {
                            paywallReason = nil
                            showPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text("Upgrade to Pro")
                                            .font(.headline)
                                        ProBadge()
                                    }
                                    Text("Unlimited bills, business tracking, reports, sync.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button("Restore Purchases") {
                            Task { await subs.restorePurchases() }
                        }
                        .font(.subheadline)
                    }
                } header: {
                    HStack {
                        Image(systemName: "sparkle")
                            .foregroundStyle(Color.appAccent)
                        Text("Subscription")
                    }
                } footer: {
                    if subs.isPro {
                        Text("Thanks for supporting Sacred Bill Tracker.")
                            .font(.footnote)
                    } else {
                        Text("Free includes up to \(FreeTierLimits.maxBills) household bills. Upgrade anytime.")
                            .font(.footnote)
                    }
                }

                Section {
                    ProfileSwitcherBar()

                    if subs.isPro {
                        NavigationLink {
                            ManagedProfilesView()
                                .environmentObject(profileStore)
                                .environmentObject(subs)
                        } label: {
                            HStack {
                                Label("Manage Profiles", systemImage: "person.crop.circle.badge.gearshape")
                                Spacer()
                                Text("\(profileStore.profiles.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            paywallReason = PremiumMessaging.managedProfiles
                            showPaywall = true
                        } label: {
                            HStack {
                                Label("Manage Profiles", systemImage: "lock.fill")
                                Spacer()
                                ProBadge()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.bold())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Image(systemName: "person.3.sequence.fill")
                            .foregroundStyle(Color.appAccent)
                        Text("Profiles")
                    }
                } footer: {
                    Text("Manage your own bills, family bills, business, and property profiles inside this one account and subscription.")
                        .font(.footnote)
                }

                // Partner Budgeting — backend is live as of v1.0.5.
                // Shipped to Release / TestFlight / App Store.
                Section {
                    NavigationLink {
                        PartnerBudgetingView(
                            service: PartnerService(
                                currentUserId: auth.currentUserID?.uuidString ?? ""
                            )
                        )
                    } label: {
                        HStack {
                            Label("Partner Budgeting", systemImage: "person.2.fill")
                            Spacer()
                            if !PartnerService.isBackendReady {
                                Text("Unavailable")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color.appAccent.opacity(0.18))
                                    )
                                    .foregroundStyle(Color.appAmber)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "person.2.circle.fill")
                            .foregroundStyle(Color.appHousehold)
                        Text("Partner")
                    }
                } footer: {
                    Text("Invite your partner to budget together. Each partner uses their own account.")
                        .font(.footnote)
                }

                Section {
                    NavigationLink {
                        IncomeListView()
                            .environmentObject(incomeStore)
                    } label: {
                        HStack {
                            Label("Income Overview",
                                  systemImage: "dollarsign.circle.fill")
                            Spacer()
                            if !incomeStore.profileEntries.isEmpty {
                                Text("\(incomeStore.profileEntries.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink {
                        CPAReadyExportView()
                            .environmentObject(store)
                            .environmentObject(incomeStore)
                    } label: {
                        Label("CPA Ready Export", systemImage: "doc.text.magnifyingglass")
                    }
                } header: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(Color.appAccent)
                        Text("Financial")
                    }
                } footer: {
                    Text("Track income and export an accountant-ready PDF of your bills, expenses, and profit.")
                        .font(.footnote)
                }

                Section {
                    Picker("Period", selection: Binding(
                        get: { currentPeriod },
                        set: { incomePeriodRaw = $0.rawValue }
                    )) {
                        ForEach(IncomePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }

                    Picker("Week starts on", selection: Binding(
                        get: { currentWeekStartDay },
                        set: { weekStartDayRaw = $0.rawValue }
                    )) {
                        ForEach(WeekStartDay.allCases) { day in
                            Text(day.title).tag(day)
                        }
                    }
                    .disabled(currentPeriod == .monthly)
                } header: {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(Color.appAccent)
                        Text("Income Tracking")
                    }
                } footer: {
                    Text(incomeFooterCopy)
                        .font(.footnote)
                }

                Section("Data") {
                    // v1.6 — Share Bill Summary entry point. Built on the
                    // same plain-text generator as the Bills toolbar
                    // button. Local-only: nothing is uploaded; the user
                    // picks the destination in the share sheet.
                    // v1.7 — Now includes an Income Summary section
                    // sourced from `IncomeStore` aggregates.
                    ShareLink(
                        item: BillShareService.makeSummary(
                            bills: store.bills,
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
                        Label("Share Bill Summary", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.bills.filter { $0.deletedAt == nil }.isEmpty)
                    .accessibilityLabel("Share bill summary")
                    .accessibilityHint("Opens the iOS share sheet so you can send your bill summary to Messages, Mail, Notes, or AirDrop.")

                    NavigationLink {
                        TrashView()
                    } label: {
                        HStack {
                            Label("Trash", systemImage: "trash")
                            Spacer()
                            if !store.profileDeletedBills.isEmpty {
                                Text("\(store.profileDeletedBills.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    #if DEBUG
                    // DEBUG-only: developer convenience to load sample
                    // bills locally. NOT shipped to TestFlight / App Store.
                    Button {
                        showResetConfirm = true
                    } label: {
                        Label("Reset with sample data (DEBUG)", systemImage: "arrow.counterclockwise")
                    }
                    #endif
                }

                Section {
                    if let name = auth.displayName {
                        HStack {
                            Label("Name", systemImage: "person.circle")
                            Spacer()
                            Text(name).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Signed in")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                    }
                } header: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(Color.appHousehold)
                        Text("Account")
                    }
                }

                // v1.0.9 — Appearance picker. Applied at app root via
                // .preferredColorScheme so the flip is instant.
                Section {
                    Picker("Appearance", selection: Binding(
                        get: { AppearancePreference.from(rawValue: appearanceRaw) },
                        set: { appearanceRaw = $0.rawValue }
                    )) {
                        ForEach(AppearancePreference.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    HStack {
                        Image(systemName: "paintbrush.fill")
                            .foregroundStyle(Color.appAccent)
                        Text("Appearance")
                    }
                } footer: {
                    Text("Choose how the app looks. ‘Use System Setting’ matches your iPhone's Light or Dark mode automatically.")
                        .font(.footnote)
                }

                Section("About") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                    HStack {
                        Label("Bills Stored", systemImage: "number")
                        Spacer()
                        Text("\(store.allStoredBills.count)").foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://www.sacredpathway.org/sacred-bill-tracker-privacy")!) {
                        HStack {
                            Label("Privacy Policy", systemImage: "hand.raised")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                        HStack {
                            Label("Terms of Use", systemImage: "doc.text")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "mailto:sacredbilltracker@gmail.com?subject=Sacred%20Bill%20Tracker%20Support")!) {
                        HStack {
                            Label("Support", systemImage: "envelope")
                            Spacer()
                            Text("sacredbilltracker@gmail.com")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // v1.0.9 — Destructive actions live at the very bottom
                // so they are the last things the user sees. Order:
                // Sign Out → Delete Account.
                Section {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    Button(role: .destructive) {
                        showDeleteAccountConfirm = true
                    } label: {
                        HStack {
                            Label("Delete Account", systemImage: "person.crop.circle.badge.xmark")
                            if isDeletingAccount {
                                Spacer()
                                ProgressView().controlSize(.small)
                            }
                        }
                    }
                    .disabled(isDeletingAccount)
                } footer: {
                    Text("Deleting your account permanently removes your sign-in and every device's copy of your data.")
                        .font(.footnote)
                }
            }
            .navigationTitle("Settings")
            #if DEBUG
            .confirmationDialog("Reset with sample data? This replaces your current bills.",
                                isPresented: $showResetConfirm,
                                titleVisibility: .visible) {
                Button("Reset", role: .destructive) { store.resetWithSampleData() }
                Button("Cancel", role: .cancel) {}
            }
            #endif
            .confirmationDialog("Sign out? Your bills stay in the cloud and will reload next time you sign in.",
                                isPresented: $showSignOutConfirm,
                                titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showDeleteAccountConfirm) {
                DeleteAccountSheet {
                    showDeleteAccountConfirm = false
                    Task {
                        isDeletingAccount = true
                        let ok = await auth.deleteAccount()
                        if ok {
                            store.wipeAll()
                            incomeStore.wipeAll()
                        }
                        isDeletingAccount = false
                    }
                } onCancel: {
                    showDeleteAccountConfirm = false
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert(
                "Couldn't delete your account",
                isPresented: Binding(
                    get: { auth.lastError != nil && !isDeletingAccount },
                    set: { if !$0 { auth.lastError = nil } }
                ),
                presenting: auth.lastError
            ) { _ in
                Button("OK", role: .cancel) { auth.lastError = nil }
            } message: { message in
                Text(message)
            }
            .paywallSheet(isPresented: $showPaywall, reason: paywallReason)
        }
    }

    private var authStatusText: String {
        switch notifications.authorizationStatus {
        case .authorized:   return "Enabled"
        case .denied:       return "Denied"
        case .notDetermined:return "Not Set"
        case .provisional:  return "Provisional"
        case .ephemeral:    return "Ephemeral"
        @unknown default:   return "Unknown"
        }
    }

    private var authStatusColor: Color {
        switch notifications.authorizationStatus {
        case .authorized, .provisional: return .green
        case .denied: return .red
        default:      return .secondary
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Income preferences (computed)

    private var currentPeriod: IncomePeriod {
        IncomePeriod.from(rawValue: incomePeriodRaw)
    }

    private var currentWeekStartDay: WeekStartDay {
        WeekStartDay.from(rawValue: weekStartDayRaw)
    }

    private var incomeFooterCopy: String {
        switch currentPeriod {
        case .weekly:
            return "Income totals roll over each \(currentWeekStartDay.title). The Add Income sheet pre-fills the current \(currentWeekStartDay.title)-to-\(dayBefore(currentWeekStartDay).title) range."
        case .biweekly:
            return "Income tracks in fixed two-week windows starting on \(currentWeekStartDay.title)."
        case .monthly:
            return "Income tracks by calendar month (first to last day). Week-start day is ignored for monthly periods."
        }
    }

    private func dayBefore(_ day: WeekStartDay) -> WeekStartDay {
        let prev = day.rawValue == 1 ? 7 : day.rawValue - 1
        return WeekStartDay(rawValue: prev) ?? .sunday
    }
}

#Preview {
    SettingsView()
        .environmentObject(BillStore())
        .environmentObject(IncomeStore())
        .environmentObject(ManagedProfileStore.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(SubscriptionManager())
}
