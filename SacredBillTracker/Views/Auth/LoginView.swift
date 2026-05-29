//
//  LoginView.swift
//  SacredBillTracker
//
//  Email + password sign-in sheet for existing accounts. Calls
//  AuthService.signIn(email:password:) which is backed by Supabase Auth.
//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isWorking: Bool = false
    @State private var localError: String?
    @State private var showForgot: Bool = false

    var body: some View {
        NavigationStack {
            content
        }
        .preferredColorScheme(.dark)
    }

    private var content: some View {
        ZStack {
            Color.appSacredBlack.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {

                    Text("Welcome back")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 32)

                    Text("Sign in to access your bills and income.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email")
                            .font(.caption.bold())
                            .foregroundStyle(.white.opacity(0.7))
                        TextField("you@example.com", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled(true)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Password")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.7))
                            Spacer()
                            Button {
                                showForgot = true
                            } label: {
                                Text("Forgot password?")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.appAccent)
                            }
                            .buttonStyle(.plain)
                        }
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .foregroundStyle(.white)
                    }

                    if let err = displayedError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await attemptSignIn() }
                    } label: {
                        HStack {
                            if isWorking {
                                ProgressView()
                                    .tint(Color.appSacredBlack)
                            }
                            Text(isWorking ? "Signing in…" : "Sign In")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.appSacredBlack)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.appAccent.opacity(canSubmit ? 1 : 0.5))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || isWorking)
                    .padding(.top, 4)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.appAccent)
            }
        }
        .toolbarBackground(Color.appSacredBlack, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showForgot) {
            ForgotPasswordView(prefilledEmail: email)
                .environmentObject(auth)
        }
    }

    // MARK: - Derived

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private var displayedError: String? {
        localError ?? auth.lastError
    }

    private func attemptSignIn() async {
        localError = nil
        auth.lastError = nil
        isWorking = true
        let ok = await auth.signIn(email: email, password: password)
        isWorking = false
        if ok {
            dismiss()
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService.shared)
}
