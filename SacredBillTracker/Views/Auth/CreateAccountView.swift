//
//  CreateAccountView.swift
//  SacredBillTracker
//
//  Email + password sign-up sheet. Calls AuthService.signUp which
//  hands off to Supabase Auth. Validates: email present, password
//  ≥ 8 chars, confirm matches. Passwords are NEVER stored locally —
//  only the resulting Supabase JWT (keychain-backed) persists.
//

import SwiftUI

struct CreateAccountView: View {

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isWorking: Bool = false
    @State private var localError: String?

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
                VStack(alignment: .leading, spacing: 18) {

                    Text("Create your account")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 32)

                    Text("Start tracking your bills, income, and real profit.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 4)

                    field(label: "Name (optional)",
                          placeholder: "First Last",
                          text: $name,
                          isSecure: false,
                          contentType: .name,
                          keyboard: .default,
                          autocap: .words,
                          autocorrect: true)

                    field(label: "Email",
                          placeholder: "you@example.com",
                          text: $email,
                          isSecure: false,
                          contentType: .username,
                          keyboard: .emailAddress,
                          autocap: .never,
                          autocorrect: false)

                    field(label: "Password",
                          placeholder: "At least 8 characters",
                          text: $password,
                          isSecure: true,
                          contentType: .newPassword,
                          keyboard: .default,
                          autocap: .never,
                          autocorrect: false)

                    field(label: "Confirm password",
                          placeholder: "Re-enter password",
                          text: $confirmPassword,
                          isSecure: true,
                          contentType: .newPassword,
                          keyboard: .default,
                          autocap: .never,
                          autocorrect: false)

                    if let err = displayedError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(Color.appDangerText)
                    } else if !password.isEmpty && password.count < 8 {
                        Text("Password must be at least 8 characters.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    } else if !confirmPassword.isEmpty && password != confirmPassword {
                        Text("Passwords don't match.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Button {
                        Task { await attemptSignUp() }
                    } label: {
                        HStack {
                            if isWorking {
                                ProgressView()
                                    .tint(Color.appSacredBlack)
                            }
                            Text(isWorking ? "Creating account…" : "Create Account")
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

                    Text("By creating an account you agree to the Terms of Use and Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 24)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.appAccentText)
            }
        }
        .toolbarBackground(Color.appSacredBlack, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Field builder

    @ViewBuilder
    private func field(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        contentType: UITextContentType,
        keyboard: UIKeyboardType,
        autocap: TextInputAutocapitalization,
        autocorrect: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.7))
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .textContentType(contentType)
                } else {
                    TextField(placeholder, text: text)
                        .textContentType(contentType)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(autocap)
                        .autocorrectionDisabled(!autocorrect)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .foregroundStyle(.white)
        }
    }

    // MARK: - Derived

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 8 &&
        password == confirmPassword
    }

    private var displayedError: String? {
        localError ?? auth.lastError
    }

    private func attemptSignUp() async {
        localError = nil
        auth.lastError = nil

        // Client-side guards before hitting the network — keeps the
        // server from rejecting obviously-invalid input and gives the
        // user instant feedback.
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            localError = "Email is required."
            return
        }
        guard password.count >= 8 else {
            localError = "Password must be at least 8 characters."
            return
        }
        guard password == confirmPassword else {
            localError = "Passwords don't match."
            return
        }

        isWorking = true
        let ok = await auth.signUp(email: email,
                                   password: password,
                                   displayName: name.isEmpty ? nil : name)
        isWorking = false
        if ok {
            dismiss()
        }
        // On failure, AuthService.lastError already populated — bound
        // to `displayedError` above so the form re-renders with it.
    }
}

#Preview {
    CreateAccountView()
        .environmentObject(AuthService.shared)
}
