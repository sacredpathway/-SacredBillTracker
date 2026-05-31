//
//  PartnerBudgetingView.swift
//  SacredBillTracker
//
//  Settings → Partner Budgeting destination.
//
//  Shows:
//    - Hero illustration
//    - Availability banner (when PartnerService.isBackendReady == false)
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

                // Show incoming invite banner FIRST when present — this
                // is what fixes the build-15 acceptance bug. If someone
                // invited the current user, they need to accept before
                // shared bills cross either way.
                if service.incomingInvite != nil {
                    incomingInviteBanner
                }

                emailPendingBanner

                howItWorksCard

                inviteCard

                statusSection

                privacyFooter
            }
            .padding(.vertical, Theme.Spacing.l)
        }
        .background(Theme.Color.background.ignoresSafeArea())
        .navigationTitle("Partner Budgeting")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await service.loadCurrentInvite() }
        .task { await service.loadCurrentInvite() }
        .alert("Invite created", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // Always-visible banner explaining the current manual delivery path
    // for invite instructions.
    private var emailPendingBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "envelope.badge.fill")
                .foregroundStyle(Theme.Color.accentGold)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Share invite details manually")
                    .font(.subheadline.weight(.semibold))
                Text("Ask your partner to install Sacred Bill Tracker and sign in with the email you invite. Their pending invite will appear instantly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.accentGold.opacity(0.10))
        )
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Incoming Invite Banner (build 16)

    /// When someone has invited the current user, show a green CTA card
    /// at the top of the screen with [Accept]. Without this, the
    /// invitee's invite stays in `pending` forever and shared bills
    /// never cross because the bills RLS policy requires `status = 'connected'`.
    private var incomingInviteBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "envelope.open.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.Color.accentGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're invited to budget together")
                        .font(.subheadline.weight(.semibold))
                    Text("Accept to start sharing bills with your partner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: Theme.Spacing.m) {
                Button {
                    Task { await acceptIncoming() }
                } label: {
                    Label("Accept invite", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(service.isLoading)

                Button(role: .destructive) {
                    Task { await declineIncoming() }
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .font(.subheadline.weight(.medium))
                }
                .disabled(service.isLoading)
            }
        }
        .padding(Theme.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Color.accentGreen.opacity(0.10))
        )
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - How It Works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("How sharing works", systemImage: "info.circle.fill")
                .font(Theme.Font.cardTitle)
            stepRow(num: "1", text: "Send an invite to your partner's email.")
            stepRow(num: "2", text: "They install Sacred Bill Tracker and sign in using that exact same email — Apple ID or otherwise.")
            stepRow(num: "3", text: "On any bill, toggle Share with partner to choose what they can see. Bills you don't toggle stay private.")
            stepRow(num: "4", text: "Either of you can flip a bill off at any time and it disappears from the partner's Shared tab.")
        }
        .cardStyle()
        .padding(.horizontal, Theme.Spacing.l)
    }

    private func stepRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Text(num)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Theme.Color.accentGreen.opacity(0.18), in: Circle())
                .foregroundStyle(Theme.Color.accentGreen)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.Color.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Privacy Footer

    private var privacyFooter: some View {
        VStack(spacing: 4) {
            Label("Your data, your rules", systemImage: "lock.shield.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Color.secondaryText)
            Text("No bank connection required. Sharing is selective — your partner only sees the bills you turn on. You can revoke access anytime.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Color.secondaryText)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.top, Theme.Spacing.m)
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

    // MARK: - Availability Banner

    private var comingSoonBanner: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "clock.badge.fill")
                .font(.title3)
                .foregroundStyle(Theme.Color.accentGold)
            Text("Partner invites are temporarily unavailable.")
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
                        title: "Invite created",
                        subtitle: service.invite.map { "Waiting for \($0.invitedEmail) to install the app and sign in with that exact email." } ?? "Waiting for partner to join."
                    )

                    // Manual share path so the user can deliver the
                    // instructions through any channel they prefer.
                    if let invite = service.invite {
                        let appStoreURL = "https://apps.apple.com/app/id6762890363"
                        let shareText = """
                            I'm using Sacred Bill Tracker and I'd like to budget with you. Install it from the App Store and sign in with your email \(invite.invitedEmail) — your invite will appear automatically.

                            \(appStoreURL)
                            """
                        HStack(spacing: Theme.Spacing.m) {
                            Button {
                                UIPasteboard.general.string = shareText
                                alertMessage = "Instructions copied. Paste them into a text or email to your partner."
                                showAlert = true
                            } label: {
                                Label("Copy instructions", systemImage: "doc.on.doc.fill")
                                    .font(.subheadline.weight(.medium))
                            }
                            ShareLink(item: shareText) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .padding(.top, 4)
                    }

                    Button(role: .destructive) {
                        Task {
                            await service.cancelInvite()
                            alertMessage = "Pending invite cancelled."
                            showAlert = true
                        }
                    } label: {
                        Label("Cancel pending invite", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.top, 4)
                    .disabled(service.isLoading)
                case .connected:
                    StatusRow(
                        icon: "checkmark.seal.fill",
                        tint: Theme.Color.accentGreen,
                        title: "Partner joined",
                        subtitle: service.invite.map { "Connected with \($0.invitedEmail). You're now sharing the budget." } ?? "You're now sharing the budget."
                    )
                }

                if let err = service.lastError, !err.isEmpty,
                   service.status != .connected {
                    Divider()
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Color.appDangerText)
                }
            }
            .cardStyle()

            if service.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Syncing partner status…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }

    // MARK: - Actions

    private func acceptIncoming() async {
        guard let invite = service.incomingInvite else { return }
        let ok = await service.acceptInvite(id: invite.id)
        if ok {
            alertMessage = "You're now connected with \(invite.invitedEmail). Bills your partner shares will appear in your Bills tab under Shared Bills."
        } else {
            alertMessage = service.lastError ?? "Could not accept invite. Please try again."
        }
        showAlert = true
    }

    private func declineIncoming() async {
        guard let invite = service.incomingInvite else { return }
        let ok = await service.declineInvite(id: invite.id)
        alertMessage = ok ? "Invite declined." : (service.lastError ?? "Could not decline invite.")
        showAlert = true
    }

    private func sendInvite() async {
        emailFocused = false
        let target = partnerEmail
        let ok = await service.sendInvite(toEmail: target)
        if ok {
            alertMessage = """
                Invite created for \(target).

                Share the invite instructions with \(target). Ask them to install Sacred Bill Tracker and sign in using exactly that email. The pending invite will appear in their Settings → Partner Budgeting screen.
                """
            partnerEmail = ""
        } else {
            alertMessage = service.lastError ?? "Could not create invite. Please try again."
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
