import StoreKit
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

    @State private var showPurchasePreferences = false
    #if DEBUG
    @State private var showResetConfirm = false
    #endif
    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var showPaywall = false
    @State private var paywallReason: String?
    @State private var showAutoTrackPaywall = false
    @State private var showBillPDFPreview = false

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
                    if notifications.authorizationStatus == .notDetermined {
                        Button {
                            Task { _ = await notifications.requestAuthorization() }
                        } label: {
                            Label("Enable Notifications", systemImage: "bell")
                        }
                    } else if notifications.authorizationStatus == .denied {
                        Text("Notifications are off. You can enable them in iOS Settings when you’re ready.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Notifications are disabled in iOS Settings")
                    }
                    Picker("Bill reminder", selection: Binding(
                        get: { notifications.leadTimeDays },
                        set: { notifications.leadTimeDays = $0
                               Task { await notifications.rescheduleAll(for: store.allStoredBills) } }
                    )) {
                        Text("On the due date").tag(0)
                        Text("1 day before").tag(1)
                        Text("3 days before").tag(3)
                        Text("7 days before").tag(7)
                    }
                }

                Section {
                    if subs.effectiveTier > .free {
                        HStack {
                            Label("Current plan", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Color.appAccentText)
                            Spacer()
                            Text(subs.effectiveTier.displayName)
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
                            .foregroundStyle(Color.appAccentText)
                        Text("Subscription")
                    }
                } footer: {
                    if subs.effectiveTier > .free {
                        Text("Thanks for supporting Sacred Bill Tracker.")
                            .font(.footnote)
                    } else {
                        Text("Free includes up to \(FreeTierLimits.maxBills) household bills. Upgrade anytime.")
                            .font(.footnote)
                    }
                }

                Section {
                    if subs.hasAutoTrack {
                        HStack {
                            Label("AutoTrack Premium", systemImage: "building.columns.fill")
                                .foregroundStyle(Color.appAccentText)
                            Spacer()
                            Text("Active").foregroundStyle(.secondary)
                        }
                        NavigationLink {
                            AutoTrackConnectView()
                        } label: {
                            Label("Connect a bank account", systemImage: "link")
                        }
                        Button {
                            Task { await subs.openManageSubscriptions() }
                        } label: {
                            Label("Manage Subscription", systemImage: "creditcard")
                        }
                    } else {
                        Button {
                            showAutoTrackPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("AutoTrack Premium").font(.headline)
                                    Text("Connect your bank with Plaid to auto-detect bills, spending, and subscriptions.")
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
                    }
                } header: {
                    HStack {
                        Image(systemName: "building.columns")
                            .foregroundStyle(Color.appAccentText)
                        Text("AutoTrack Premium")
                    }
                } footer: {
                    Text("Premium financial automation. Secure connection powered by Plaid; you stay in control before any suggested bill is confirmed.")
                        .font(.footnote)
                }

                if ReceiptJarReleaseGate.isEnabled {
                    Section {
                        NavigationLink {
                            ReceiptJarView()
                                .environmentObject(subs)
                                .environmentObject(store)
                        } label: {
                            HStack {
                                Label("Receipt Jar", systemImage: "shippingbox.fill")
                                Spacer()
                                Text(subs.hasReceiptJar ? "Unlocked" : "$49.99")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(subs.hasReceiptJar ? Color.appAccent : .secondary)
                            }
                        }
                    } header: {
                        HStack {
                            Image(systemName: "receipt.fill")
                                .foregroundStyle(Color.appAccentText)
                            Text("Receipts")
                        }
                    } footer: {
                        Text("One-time premium add-on for receipt photos, PDFs, manual entries, OCR review, search, bill links, and approved email receipt discovery.")
                            .font(.footnote)
                    }
                }

                Section {
                    ProfileSwitcherBar()

                    if subs.canManagedProfiles {
                        NavigationLink {
                            ManagedProfilesView()
                                .environmentObject(profileStore)
                                .environmentObject(subs)
                        } label: {
                            HStack {
                                Label("Manage Profiles", systemImage: "person.2.badge.gearshape")
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
                            .foregroundStyle(Color.appAccentText)
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
                            .foregroundStyle(Color.appHouseholdText)
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
                            .foregroundStyle(Color.appAccentText)
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
                            .foregroundStyle(Color.appAccentText)
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
                    Button { showBillPDFPreview = true } label: {
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

                #if DEBUG
                // QA-ONLY tier simulator. Compiled out of Release builds — used
                // to exercise Essential/Business/Unlimited gates when local
                // StoreKit Testing isn't engaging in the simulator. Sets the
                // 3-tier plan only; Focus+ and AutoTrack stay separate.
                Section {
                    Picker("Simulated tier (DEBUG)", selection: Binding(
                        get: { subs.debugTierOverride ?? .free },
                        set: { subs.debugTierOverride = ($0 == .free ? nil : $0) }
                    )) {
                        Text("Free (off)").tag(PlanTier.free)
                        Text("Essential").tag(PlanTier.essential)
                        Text("Business").tag(PlanTier.business)
                        Text("Unlimited").tag(PlanTier.unlimited)
                    }
                    HStack {
                        Text("effectiveTier")
                        Spacer()
                        Text(subs.effectiveTier.displayName).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Focus+ / AutoTrack")
                        Spacer()
                        Text("\(subs.hasFocusPlus ? "F+" : "—") / \(subs.hasAutoTrack ? "AT" : "—")")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("QA — Tier Override", systemImage: "ladybug")
                } footer: {
                    Text("DEBUG only. Promotes the 3-tier plan for gate testing. Not compiled into Release.")
                }
                #endif

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
                            .foregroundStyle(Color.appHouseholdText)
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
                            .foregroundStyle(Color.appAccentText)
                        Text("Appearance")
                    }
                } footer: {
                    Text("Choose how the app looks. ‘Use System Setting’ matches your iPhone's Light or Dark mode automatically.")
                        .font(.footnote)
                }

                Section {
                    HelpCenterSettingsLink()

                    NavigationLink {
                        EarnRewardsView()
                    } label: {
                        Label("Earn Rewards", systemImage: "gift.fill")
                            .foregroundStyle(Color.appAccentText)
                    }
                } header: {
                    Text("Help and referrals")
                } footer: {
                    Text("Learn every major feature, then share Sacred Bill Tracker with people who need it.")
                }

                Section("Subscription and privacy") {
                    Button("Purchases, offers and recovery") { showPurchasePreferences = true }
                        .sheet(isPresented: $showPurchasePreferences) {
                            NavigationStack {
                                SBTAccountPreferences()
                                    .toolbar {
                                        ToolbarItem(placement: .topBarTrailing) {
                                            Button("Done") { showPurchasePreferences = false }
                                        }
                                    }
                            }
                        }
                }

                #if DEBUG
                if ProcessInfo.processInfo.environment["SBT_STAGING_UI"] == "1" {
                    Section("Development validation") {
                        NavigationLink("Premium and email staging") {
                            SBTStagingPreferences { await subs.openManageSubscriptions() }
                        }
                    }
                }
                #endif

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
                    Link(destination: URL(string: "https://www.sacredpathwayllc.com")!) {
                        HStack {
                            Label("Visit Sacred Pathway LLC", systemImage: "globe")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://www.sacredpathwayllc.com/sacred-bill-tracker/privacy-policy")!) {
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
            .sheet(isPresented: $showBillPDFPreview) {
                BillPDFPreviewView(bills: store.bills)
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
            .autoTrackPaywallSheet(isPresented: $showAutoTrackPaywall)
            .task { await subs.refreshAutoTrackEntitlementFromBackend() }
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

#if DEBUG
/// Development-only surface. No entitlement override, price simulation, or email transport.
private struct SBTStagingPreferences: View {
    let manage: () async -> Void
    @State private var endpoint = ""
    @State private var token = ""
    @State private var email = ""
    @State private var consent = false
    @State private var busy = false
    @State private var message = ""
    var body: some View {
        Form {
            Section {
                Text("Staging validation").font(.title2.bold())
                Text("No production emails, discounts, or Premium grants are enabled here.")
                Button("Continue to Apple Subscription Management") {
                    Task { await manage() }
                }
                .accessibilityHint("Opens Apple's subscription controls without completing this form")
            }
            Section("Local service connection") {
                TextField("HTTPS development endpoint", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Local test account token", text: $token)
                Text("Use a dedicated development account. Credentials are kept only in this screen's memory.")
                    .font(.footnote)
            }
            Section("Premium retention") {
                Text("Before you go…").font(.headline)
                Text("We'd love to keep helping you stay ahead of your bills.")
                Button("Check offer availability") {
                    perform("retention", [:])
                }.disabled(busy)
                Text("A discount must be configured and verified by the store. Lifetime access requires verified server eligibility and approved terms. Neither is available from this test screen.")
                    .font(.footnote)
                Text("Lifetime Premium does not automatically cancel an existing App Store or Google Play subscription. Manage or cancel it through Apple to avoid renewal charges.")
                    .font(.footnote)
            }
            Section("Email preferences") {
                Text("Get helpful bill reminders & Sacred Bill Tracker updates").font(.headline)
                Text("Receive budgeting tips, product updates, special offers, and occasional Sacred Bill Tracker news by email.")
                TextField("Email address", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                Toggle("Yes, send me Sacred Bill Tracker emails", isOn: $consent)
                Button("Record test opt-in") {
                    perform("marketing/opt-in", ["email": email.trimmingCharacters(in: .whitespacesAndNewlines),
                        "consent": consent, "source": "ios_settings", "version": "sbt-marketing-v1-draft"])
                }.disabled(busy || !consent || email.isEmpty)
                Button("Opt out of marketing") { perform("marketing/opt-out", [:]) }
                    .disabled(busy)
                Text("Marketing is optional. Opting out does not remove Premium, delete your account, or disable app reminders.")
                    .font(.footnote)
                Link("Privacy Policy", destination: URL(string: "https://www.sacredpathwayllc.com/sacred-bill-tracker/privacy-policy")!)
            }
            if !message.isEmpty { Section { Text(message).accessibilityLabel(message) } }
        }
        .navigationTitle("Premium & email")
    }
    private func perform(_ path: String, _ body: [String: Any]) {
        guard !busy, let url = URL(string: endpoint), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, !token.isEmpty else {
            message = "Enter a dedicated HTTPS development service and test account token."
            return
        }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                var request = URLRequest(url: url.appendingPathComponent(path))
                request.httpMethod = "POST"
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let config = URLSessionConfiguration.ephemeral
                config.httpShouldSetCookies = false
                config.urlCache = nil
                let session = URLSession(configuration: config, delegate: SBTStagingRedirectGuard(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (data,response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    message = "Request was not accepted. Your subscription and reminders are unchanged."
                    return
                }
                if path == "retention" {
                    message = "No store-backed retention offer is configured. You can continue directly to Apple Subscription Management."
                } else if json["status"] as? String == "confirmation_required" {
                    message = "Test consent request saved as pending. This staging service sends no confirmation or marketing email."
                } else if json["status"] as? String == "suppressed" {
                    consent = false
                    message = "Marketing suppressed for this test account."
                } else { message = "Unrecognized response; no success assumed." }
            } catch { message = "Service unavailable. Subscription management remains available above." }
        }
    }
}
private final class SBTStagingRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
#endif


/// Normal subscription controls stay available even when account services are offline.
struct SBTAccountPreferences: View {
    @EnvironmentObject private var tiers: TierEntitlementManager
    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var auth: AuthService
    @StateObject private var account = SBTAccountIntegration()
    #if DEBUG && canImport(Supabase)
    @ObservedObject private var sandboxSession = SBTSandboxSession.shared
    @State private var sandboxEmail = ""
    @State private var sandboxPassword = ""
    #endif
    @State private var redeem = false
    @State private var redemptionMessage = ""
    @State private var emailConsent = false
    @State private var reason = "Prefer not to say"
    @AppStorage(AnalyticsPrivacy.consentKey) private var analyticsConsent = false
    var body: some View {
        Form {
            Section("Apple purchases") {
                Text("Current plan: \(tiers.activeTier.displayName)")
                Button("Redeem an Apple offer code") { redeem = true }
                Text("Apple checks eligibility and displays the offer terms. Access changes only after StoreKit verifies a transaction.")
                    .font(.footnote)
                Button("Restore Apple purchases") {
                    Task { await tiers.restore(); await subs.refreshEntitlements() }
                }
                Button("Manage or cancel Apple subscriptions") { Task { await tiers.manageSubscriptions() } }
                    .accessibilityHint("Opens Apple's subscription controls immediately")
                if !redemptionMessage.isEmpty { Text(redemptionMessage).accessibilityLabel(redemptionMessage) }
            }
            #if DEBUG && canImport(Supabase)
            Section("Sandbox account testing") {
                Text("Real authentication and SAVE20 validation are deferred. No test account has been created.")
                TextField("Dedicated test email", text: $sandboxEmail)
                    .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Test account password", text: $sandboxPassword).textContentType(.password)
                Button("Sign in to sandbox") {
                    let email = sandboxEmail, password = sandboxPassword
                    sandboxPassword = ""
                    Task { await sandboxSession.signIn(email: email, password: password) }
                }.disabled(!sandboxSession.isConfigured || sandboxSession.busy || sandboxEmail.isEmpty || sandboxPassword.isEmpty)
                Button("Refresh sandbox session") { Task { await sandboxSession.refresh() } }.disabled(!sandboxSession.isConfigured || sandboxSession.busy)
                Button("Sign out of sandbox") { account.clear(); Task { await sandboxSession.signOut() } }.disabled(!sandboxSession.isConfigured || sandboxSession.busy)
                Text(sandboxSession.message)
            }
            #endif
            Section("Account recovery") {
                Text("Sign in to the same Sacred Bill Tracker account on each device, then restore your purchases. Purchases without an account binding require ownership review before account benefits can be linked.")
                Button("Check account benefits") { Task { await account.refresh() } }.disabled(account.busy)
                if !account.message.isEmpty { Text(account.message) }
                ForEach(account.snapshot?.subscriptions ?? [], id: \.original_transaction_id) { subscription in
                    Text("Sandbox subscription: \(subscription.tier(at: Date()).displayName). This test record does not unlock production benefits.")
                }
                if let lifetime = account.snapshot?.lifetime {
                    Text("Sandbox lifetime record: \(lifetime.tier). This test record does not unlock production benefits.")
                }
            }
            Section("Before you go") {
                Text("Managing or canceling your subscription never requires answering these questions.")
                Picker("Optional cancellation reason", selection: $reason) {
                    ForEach(["Prefer not to say", "Cost", "Not using enough", "Missing features", "Technical issue"], id: \.self) { Text($0) }
                }
                Text("No verified retention offer is currently available.")
                Text(SBTAccountConnection.lifetimeWarning)
                    .font(.body).fixedSize(horizontal: false, vertical: true)
            }
            Section("Email preferences") {
                Text("Marketing email sending is off. Account and purchase access do not require marketing consent.")
                Toggle("Send me product updates and offers by email", isOn: $emailConsent)
                    .disabled(!account.isConfigured)
                Button("Save email opt-in") {
                    Task { await account.optIn(email: auth.currentUserEmail ?? "", consent: emailConsent) }
                }.disabled(!emailConsent || account.busy || !account.isConfigured)
                Button("Opt out of marketing email") {
                    emailConsent = false
                    Task { await account.optOut() }
                }.disabled(account.busy || !account.isConfigured)
                if let marketing = account.snapshot?.marketing {
                    Text("Saved email preference: \(marketing.state)")
                    if marketing.suppressed { Text("Delivery is suppressed.") }
                }
                Text("Opt-in is separate from analytics. Preferences are confirmed by the account service; an unavailable service never enrolls you.").font(.footnote)
            }
            Section("Analytics privacy") {
                Toggle("Share feature usage events", isOn: $analyticsConsent)
                Text("Optional usage events exclude bill names, amounts, income, balances, notes, and email addresses. Marketing consent is separate.").font(.footnote)
                Link("Privacy Policy", destination: URL(string: "https://www.sacredpathwayllc.com/sacred-bill-tracker/privacy-policy")!)
            }
        }
        .navigationTitle("Purchases and privacy")
        .onAppear { AnalyticsService.shared.track(.retentionStarted, source: "retention") }
        .onChange(of: auth.currentUserID) { _, _ in account.clear(); emailConsent = false }
        .onDisappear {
            account.clear(); emailConsent = false
            #if DEBUG && canImport(Supabase)
            sandboxPassword = ""
            #endif
        }
        #if DEBUG && canImport(Supabase)
        .onChange(of: sandboxSession.revision) { _, _ in account.clear() }
        #endif
        .offerCodeRedemption(isPresented: $redeem) { result in
            Task { @MainActor in
                await tiers.refreshFromStoreKit()
                await subs.refreshEntitlements()
                switch result {
                case .success:
                    redemptionMessage = "Apple's redemption sheet closed. Current verified plan: \(tiers.activeTier.displayName)."
                case .failure:
                    redemptionMessage = "Apple could not complete redemption. Check the code and eligibility in Apple's sheet, or try again later."
                }
            }
        }
    }
}
