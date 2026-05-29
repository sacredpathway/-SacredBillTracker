//
//  AccountView.swift
//  SacredBillTracker
//
//  Cleaned-up account surface, parallel to SettingsView's Account
//  section. Currently NOT wired into the tab bar — SettingsView is
//  still the active Settings/Account host. This view is a drop-in
//  upgrade target that can be swapped in once we move Partner +
//  Account out of Settings.
//
//    - Removed: User ID, Backend / Supabase, Delete All Bills
//    - Kept:    Sign Out, Delete Account
//    - Added:   "Partner Budgeting" navigation row
//

import SwiftUI

struct AccountView: View {

    // Inject from your existing AuthService / SessionStore.
    var displayName: String
    var email: String

    var onSignOut: () -> Void
    var onDeleteAccountConfirmed: () async -> Void

    /// User's UUID string — handed to PartnerService.
    var currentUserId: String

    @State private var showDeleteSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {

                // Profile header card
                profileCard

                // Settings section
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Settings", systemImage: "gearshape.fill")

                    VStack(spacing: 0) {
                        NavigationLink {
                            PartnerBudgetingView(
                                service: PartnerService(currentUserId: currentUserId)
                            )
                        } label: {
                            SettingsRow(
                                icon: "person.2.fill",
                                iconTint: Theme.Color.accentGreen,
                                title: "Partner Budgeting",
                                subtitle: "Invite your partner to budget together",
                                showsChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .cardStyle(padding: 0)
                }

                // Account section
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Account", systemImage: "person.crop.circle")

                    VStack(spacing: 0) {
                        Button {
                            onSignOut()
                        } label: {
                            SettingsRow(
                                icon: "rectangle.portrait.and.arrow.right",
                                iconTint: Theme.Color.accentGreen,
                                title: "Sign Out",
                                subtitle: nil,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, 56)

                        Button(role: .destructive) {
                            showDeleteSheet = true
                        } label: {
                            SettingsRow(
                                icon: "trash.fill",
                                iconTint: Theme.Color.danger,
                                title: "Delete Account",
                                titleColor: Theme.Color.danger,
                                subtitle: nil,
                                showsChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .cardStyle(padding: 0)
                }

                Spacer(minLength: Theme.Spacing.xl)
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Account")
        .sheet(isPresented: $showDeleteSheet) {
            DeleteAccountSheet(
                onContinue: {
                    showDeleteSheet = false
                    Task { await onDeleteAccountConfirmed() }
                },
                onCancel: { showDeleteSheet = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                Circle()
                    .fill(Theme.Color.accentGreen.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Color.accentGreen)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.isEmpty ? "Welcome" : displayName)
                    .font(Theme.Font.cardTitle)
                    .foregroundStyle(Theme.Color.primaryText)
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .cardStyle()
        .padding(.horizontal, Theme.Spacing.l)
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    var iconTint: Color = Theme.Color.accentGreen
    let title: String
    var titleColor: Color = Theme.Color.primaryText
    let subtitle: String?
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconTint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(titleColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.secondaryText)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Color.secondaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        AccountView(
            displayName: "Demarquis Hinton",
            email: "sacredbilltracker@gmail.com",
            onSignOut: {},
            onDeleteAccountConfirmed: {},
            currentUserId: "preview-user"
        )
    }
}
