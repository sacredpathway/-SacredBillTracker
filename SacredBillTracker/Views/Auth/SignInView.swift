//
//  SignInView.swift
//  SacredBillTracker
//
//  Shown when the user is signed out. Hosts the Sign in with Apple
//  button, which routes through `AuthService`.
//

import SwiftUI
import AuthenticationServices

struct SignInView: View {

    @EnvironmentObject private var auth: AuthService
    #if DEBUG
    @EnvironmentObject private var billStore: BillStore
    #endif
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.appSacredBlack.ignoresSafeArea()

            VStack(spacing: 28) {

                Spacer(minLength: 16)

                // Brand mark
                BrandHeaderView(compact: false)
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    Text("Sacred Bill Tracker")
                        .font(.title2).bold()
                        .foregroundStyle(.white)

                    Text("Every bill, every month — household and business in one sacred space.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }

                Spacer(minLength: 16)

                VStack(spacing: 14) {
                    SignInWithAppleButton(.signIn,
                        onRequest: { req in
                            auth.configure(request: req)
                        },
                        onCompletion: { result in
                            Task { await auth.handle(result: result) }
                        }
                    )
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .cornerRadius(14)
                    .padding(.horizontal, 24)

                    if let error = auth.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Color.appDangerText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    Text("We use Apple to sign you in. We never see your email unless you share it.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    #if DEBUG
                    // Simulator / dev-only shortcut. Stripped from Release builds.
                    Button {
                        auth.signInForDevelopment()
                    } label: {
                        Text("Continue as Dev Tester (DEBUG)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 18)
                            .background(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)

                    // DEBUG-only: signs in as dev tester AND seeds the
                    // 5 App Store screenshot bills. Used by the marketing
                    // screenshot pipeline only — never appears in Release.
                    Button {
                        auth.signInForDevelopment()
                        // SacredBillTrackerApp's handleUserChange runs on
                        // the auth-state change and replaces the in-memory
                        // bill list with whatever refreshFromRemote returns
                        // (empty in dev — no Supabase session). Wait for
                        // that to settle, THEN seed, so the seed isn't
                        // wiped by the post-signin remote refresh.
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            billStore.seedScreenshotBills()
                        }
                    } label: {
                        Text("Sign In + Seed Screenshots (DEBUG)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 18)
                            .background(
                                Capsule()
                                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    #endif
                }

                Spacer(minLength: 30)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SignInView()
        .environmentObject(AuthService.shared)
        .environmentObject(BillStore())
}
