//
//  ForgotPasswordView.swift
//  SacredBillTracker
//
//  Sheet shown from LoginView when the user taps "Forgot password?".
//  Triggers Supabase's password-reset email flow. The user gets a
//  link in their inbox to set a new password; we don't handle the
//  reset step in-app yet (Supabase's hosted page completes it).
//

import SwiftUI

struct ForgotPasswordView: View {

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    /// Pre-fill the email the user typed in LoginView so they don't
    /// re-type it.
    var prefilledEmail: String = ""

    @State private var email: String = ""
    @State private var isWorking: Bool = false
    @State private var sent: Bool = false
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
                VStack(alignment: .leading, spacing: 22) {

                    Text(sent ? "Check your inbox" : "Reset password")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .padding(.top, 32)

                    Text(sent
                         ? "We sent a password reset link to \(email). Open the link on this device to choose a new password."
                         : "Enter the email on your account and we'll send you a reset link.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))

                    if !sent {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.7))
                            TextField("you@example.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled(true)
                                .textContentType(.username)
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
                                .foregroundStyle(Color.appDangerText)
                        }

                        Button {
                            Task { await attemptReset() }
                        } label: {
                            HStack {
                                if isWorking {
                                    ProgressView()
                                        .tint(Color.appSacredBlack)
                                }
                                Text(isWorking ? "Sending…" : "Send reset link")
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
                    } else {
                        Button {
                            dismiss()
                        } label: {
                            Text("Done")
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
                        .padding(.top, 4)
                    }

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
        .onAppear {
            if email.isEmpty { email = prefilledEmail }
        }
    }

    // MARK: - Derived

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var displayedError: String? {
        localError ?? auth.lastError
    }

    private func attemptReset() async {
        localError = nil
        auth.lastError = nil
        isWorking = true
        let ok = await auth.resetPassword(email: email)
        isWorking = false
        if ok {
            sent = true
        }
    }
}

#Preview {
    ForgotPasswordView(prefilledEmail: "you@example.com")
        .environmentObject(AuthService.shared)
}
