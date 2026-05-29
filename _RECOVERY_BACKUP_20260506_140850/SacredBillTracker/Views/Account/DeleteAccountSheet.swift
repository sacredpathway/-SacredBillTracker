//
//  DeleteAccountSheet.swift
//  SacredBillTracker
//
//  Apple-compliant confirmation sheet shown before account deletion.
//  Reminds the user to cancel an active App Store subscription first
//  (Guideline 3.1.2 / 5.1.1(v) requires a clear cancel-subscription
//  prompt when deleting an account in an app that sells subscriptions).
//

import SwiftUI

struct DeleteAccountSheet: View {
    let onContinue: () -> Void
    let onCancel: () -> Void

    private let manageSubscriptionURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            // Header icon
            ZStack {
                Circle()
                    .fill(Theme.Color.danger.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Theme.Color.danger)
            }
            .padding(.top, Theme.Spacing.l)

            Text("Delete Account?")
                .font(Theme.Font.largeTitle)
                .multilineTextAlignment(.center)

            Text("Deleting your account does not automatically cancel an active Apple subscription. To avoid future charges, cancel your subscription through the App Store first.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.Color.secondaryText)
                .padding(.horizontal, Theme.Spacing.l)

            VStack(spacing: Theme.Spacing.m) {
                Button {
                    openURL(manageSubscriptionURL)
                } label: {
                    Label("Manage Subscription in App Store", systemImage: "creditcard.fill")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(role: .destructive) {
                    onContinue()
                } label: {
                    Label("Continue to Delete Account", systemImage: "trash.fill")
                }
                .buttonStyle(PrimaryButtonStyle(color: Theme.Color.danger))

                Button("Cancel", action: onCancel)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.Color.secondaryText)
                    .padding(.top, Theme.Spacing.xs)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.s)

            Spacer(minLength: 0)
        }
        .padding(.bottom, Theme.Spacing.l)
        .background(Theme.Color.background.ignoresSafeArea())
    }
}

#Preview {
    DeleteAccountSheet(onContinue: {}, onCancel: {})
}
