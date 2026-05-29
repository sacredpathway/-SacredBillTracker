//
//  SubscriptionGateView.swift
//  SacredBillTracker
//
//  Full-screen hard paywall — DISABLED in v1.2.1.
//
//  Originally wired into RootScene as a sign-in-time forced upgrade
//  prompt. Reverted to protect existing free-tier users from being
//  locked out after the v1.2 update; the app now uses contextual
//  paywalls (ProLockCard / FreeTierLimits / .paywallSheet) instead.
//
//  File is kept compiled (no behavior change) so a future opt-in
//  experiment can re-wire it without re-implementing the gate.
//

import SwiftUI

struct SubscriptionGateView: View {

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var subs: SubscriptionManager

    @State private var isRestoring = false
    @State private var signOutConfirm = false

    var body: some View {
        // PaywallView renders the actual upgrade UI. We don't push it
        // into a sheet here — it's the root view, so its own ✕ button
        // becomes a no-op (it calls dismiss(), which has no effect at
        // the root). That's the intended behavior — the gate cannot be
        // dismissed; the user must purchase, restore, or sign out.
        PaywallView(
            reason: "Sacred Bill Tracker requires an active subscription to continue.",
            showCloseButton: false
        )
        .environmentObject(subs)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        Task {
                            isRestoring = true
                            await subs.restorePurchases()
                            isRestoring = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isRestoring {
                                ProgressView().controlSize(.small)
                            }
                            Text(isRestoring ? "Restoring…" : "Restore Purchases")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        signOutConfirm = true
                    } label: {
                        Text("Sign Out")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Sign out? You can sign back in anytime with your email.",
                isPresented: $signOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

#Preview {
    SubscriptionGateView()
        .environmentObject(AuthService.shared)
        .environmentObject(SubscriptionManager())
}
