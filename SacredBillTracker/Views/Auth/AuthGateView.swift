//
//  AuthGateView.swift
//  SacredBillTracker
//
//  Top-level auth chooser shown when no Supabase session exists. Lets
//  the user pick between Sign In, Create Account, or the existing
//  Sign in with Apple flow. Premium matte-black + sacred-gold styling
//  to match the rest of the app.
//

import SwiftUI
import AuthenticationServices

struct AuthGateView: View {

    @EnvironmentObject private var auth: AuthService
    #if DEBUG
    @EnvironmentObject private var billStore: BillStore
    #endif

    @State private var showLogin = false
    @State private var showCreate = false

    var body: some View {
        ZStack {
            Color.appSacredBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {

                    Spacer(minLength: 40)

                    BrandHeaderView(compact: false)
                        .padding(.horizontal, 32)

                    VStack(spacing: 10) {
                        Text("Sacred Bill Tracker")
                            .font(.title2).bold()
                            .foregroundStyle(.white)

                        Text("Sign in or create an account to start tracking every bill, every dollar.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                    }

                    Spacer(minLength: 24)

                    VStack(spacing: 14) {

                        // Primary CTA — Create Account
                        Button {
                            showCreate = true
                        } label: {
                            Text("Create Account")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.appSacredBlack)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.appAccent)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)

                        // Secondary — Sign In
                        Button {
                            showLogin = true
                        } label: {
                            Text("Sign In")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.appAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(Color.appAccent.opacity(0.6), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)

                        // Divider with "or"
                        HStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 1)
                            Text("or")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.6))
                            Rectangle()
                                .fill(Color.white.opacity(0.18))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 8)

                        // Tertiary — Sign in with Apple (kept as alternative)
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
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                                .padding(.top, 4)
                        }

                        Text("We never store your password. Auth is handled securely by Supabase.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 4)

                        #if DEBUG
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

                        Button {
                            auth.signInForDevelopment()
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
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showLogin) {
            LoginView()
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCreate) {
            CreateAccountView()
                .environmentObject(auth)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview {
    AuthGateView()
        .environmentObject(AuthService.shared)
        .environmentObject(BillStore())
}
