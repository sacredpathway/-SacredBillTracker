//
//  PartnerBudgetingView.swift
//  SacredBillTracker
//
//  Settings → Partner Budgeting destination.
//
//  Shows:
//    - Hero illustration
//    - Coming-soon banner (when PartnerService.isBackendReady == false)
//    - Email + Send Invite card
//    - Partner status section (no partner / pending / connected)
//
//  Note: there is NO partner discount in this app. Each partner manages
//  their own subscription separately.
//

import SwiftUI

struct PartnerBudgetingView: View {

    @StateObject var service: PartnerService
    @State private var partnerEmail: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @FocusState private var emailFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {

                heroIllustration

                Text("Partner Budgeting")
                    .font(Theme.Font.largeTitle)
                    .multilineTextAlignment(.center)

                Text("Invite your partner to budget together. Each partner manages their own subscription separately.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Color.secondaryText)
                    .padding(.horizontal, Theme.Spacing.xl)

                if !PartnerService.isBackendReady {
                    comingSoonBanner
                }

                inviteCard

                statusSection
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Partner Budgeting")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.loadCurrentInvite() }
        .alert("Heads up", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Hero Illustration

    private var heroIllustration: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.Color.accentGreen.opacity(0.18),
                            Theme.Color.accentGold.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 140)

            HStack(spacing: Theme.Spacing.l) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Color.accentGreen)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Color.accentGold)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Theme.Color.success)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Coming Soon Banner

    private var comingSoonBanner: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "clock.badge.fill")
                .font(.title3)
                .foregroundStyle(Theme.Color.accentGold)
            Text("Partner invites are coming soon.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.accentGold.opacity(0.10))
        )
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Invite Card

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Label("Invite your partner", systemImage: "envelope.fill")
                .font(Theme.Font.cardTitle)

            TextField("Partner email", text: $partnerEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($emailFocused)
                .padding(.horizontal, Theme.Spacing.m)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.Color.background)
                )

            Button {
                Task { await sendInvite() }
            } label: {
                HStack {
                    if service.isLoading { ProgressView().tint(.white) }
                    Text("Send Invite")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(service.isLoading || partnerEmail.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .cardStyle()
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Your Partner Status", systemImage: "person.2.circle.fill")

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                switch service.status {
                case .none:
                    StatusRow(
                        icon: "person.crop.circle.badge.questionmark",
                        tint: Theme.Color.secondaryText,
                        title: "No partner connected",
                        subtitle: "Send an invite above to get started."
                    )
                case .pending:
                    StatusRow(
                        icon: "paperplane.fill",
                        tint: Theme.Color.accentGold,
                        title: "Invite sent",
                        subtitle: service.invite.map { "Waiting for \($0.invitedEmail) to join." } ?? "Waiting for partner to join."
                    )
                case .connected:
                    StatusRow(
                        icon: "checkmark.seal.fill",
                        tint: Theme.Color.accentGreen,
                        title: "Partner joined",
                        subtitle: "You're now sharing the budget."
                    )
                }
            }
            .cardStyle()
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Actions

    private func sendInvite() async {
        emailFocused = false
        let target = partnerEmail
        let ok = await service.sendInvite(toEmail: target)
        if ok {
            alertMessage = "Invite sent to \(target)."
            partnerEmail = ""
        } else {
            alertMessage = service.lastError ?? "Could not send invite."
        }
        showAlert = true
    }
}

// MARK: - Status Row

private struct StatusRow: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Color.secondaryText)
            }
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        PartnerBudgetingView(service: PartnerService(currentUserId: "preview"))
    }
}
