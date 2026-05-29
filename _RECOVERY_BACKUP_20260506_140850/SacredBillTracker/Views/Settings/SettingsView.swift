//
//  SettingsView.swift
//  SacredBillTracker
//

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: BillStore
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
                               Task { await notifications.rescheduleAll(for: store.bills) } }
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

                #if DEBUG
                // DEBUG-only entry point. Partner Budgeting backend isn't
                // wired yet (`PartnerService.isBackendReady == false`), so
                // we hide the surface from Release / TestFlight / App Store
                // builds to avoid Apple rejecting a non-functional feature.
                // The Partner module — model, service, view, BillScope
                // toggle, Share-with-partner toggle on the bill form —
                // stays in the project; flip this `#if` to ship.
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
                                Text("Coming Soon")
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
                        Text("Partner (DEBUG)")
                    }
                } footer: {
                    Text("Invite your partner to budget together. Each partner manages their own subscription separately.")
                        .font(.footnote)
                }
                #endif

                #if DEBUG
                Section("Data") {
                    // DEBUG-only: developer convenience to load sample
                    // bills locally. NOT shipped to TestFlight / App Store.
                    Button {
                        showResetConfirm = true
                    } label: {
                        Label("Reset with sample data (DEBUG)", systemImage: "arrow.counterclockwise")
                    }
                }
                #endif

                Section("Account") {
                    if let name = auth.displayName {
                        HStack {
                            Label("Name", systemImage: "person.circle")
                            Spacer()
                            Text(name).foregroundStyle(.secondary)
                        }
                    }
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
                        Text("\(store.bills.count)").foregroundStyle(.secondary)
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
                    Link(destination: URL(string: "mailto:demarquishinton@gmail.com?subject=Sacred%20Bill%20Tracker%20Support")!) {
                        HStack {
                            Label("Support", systemImage: "envelope")
                            Spacer()
                            Text("demarquishinton@gmail.com")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            .confirmationDialog(
                "Delete your account? This permanently removes your sign-in, all of your bills, and every device's copy of your data. This cannot be undone.",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        isDeletingAccount = true
                        let ok = await auth.deleteAccount()
                        if ok { store.wipeAll() }
                        isDeletingAccount = false
                    }
                }
                Button("Cancel", role: .cancel) {}
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
            .paywallSheet(isPresented: $showPaywall)
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
}

#Preview {
    SettingsView()
        .environmentObject(BillStore())
        .environmentObject(NotificationManager.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(SubscriptionManager())
}
