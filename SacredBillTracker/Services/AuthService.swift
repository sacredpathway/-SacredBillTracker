//
//  AuthService.swift
//  SacredBillTracker
//
//  Sign in with Apple → Supabase session exchange for supabase-swift 2.43.1.
//
//  Flow:
//    1. SignInWithAppleButton.onRequest  → configure(request:)
//    2. SignInWithAppleButton.onCompletion → handle(result:)
//    3. On success: exchange idToken+nonce with Supabase for a Session
//    4. If Apple returned a name (first sign-in only), persist it to:
//         - UserDefaults (local display cache)
//         - Supabase Auth user metadata (full_name / given_name / family_name)
//
//  The implementation is wrapped in `#if canImport(Supabase)` so the
//  project still compiles before the SPM package is added. In that
//  fallback mode, `isSignedIn` always reports true and `currentUserID`
//  returns a device-local placeholder.
//

import Foundation
import AuthenticationServices
import SwiftUI
import CryptoKit

#if canImport(Supabase)
import Supabase
import Auth   // exposes OpenIDConnectCredentials, Provider, UserAttributes
#endif

// MARK: - Public API

@MainActor
final class AuthService: NSObject, ObservableObject {

    /// True once a Supabase session exists.
    @Published private(set) var isSignedIn: Bool = false

    /// The Supabase-assigned user ID. `nil` while signed out.
    @Published private(set) var currentUserID: UUID?

    /// Human-readable name from the Apple credential, if we captured one
    /// on first sign-in. Cached in UserDefaults because Apple only
    /// returns it the *first* time the user signs in.
    @Published private(set) var displayName: String?

    /// v1.0.9 — Email on the current Supabase session. Used by
    /// `SubscriptionManager` to apply the owner allowlist (Sacred
    /// Focus+ permanently unlocked for the project owner) without
    /// charging through StoreKit.
    @Published private(set) var currentUserEmail: String?

    /// Last auth error for UI to surface.
    @Published var lastError: String?

    // Raw nonce kept alive for a single sign-in round-trip.
    private var currentNonce: String?

    static let shared = AuthService()

    private let displayNameKey = "sacred.bill.tracker.auth.displayName.v1"

    override init() {
        super.init()
        displayName = UserDefaults.standard.string(forKey: displayNameKey)
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap / session restore

    /// Called on init — loads any existing Supabase session so the
    /// user stays signed in across launches.
    func bootstrap() async {
        #if canImport(Supabase)
        do {
            let session = try await SupabaseConfig.client.auth.session
            applySession(userID: session.user.id, email: session.user.email)
        } catch {
            // Not signed in yet, or session expired — that's fine.
            isSignedIn = false
            currentUserID = nil
        }
        #else
        // Without the Supabase package, behave as a single-user local app.
        isSignedIn = true
        currentUserID = DeviceIdentity.localUserID
        #endif
    }

    // MARK: - Apple Sign In entry point

    /// Call this from a SwiftUI `SignInWithAppleButton.onRequest`.
    func configure(request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    /// Call this from a SwiftUI `SignInWithAppleButton.onCompletion`.
    func handle(result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            await exchangeAppleCredential(authorization)
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    // MARK: - Development bypass

    #if DEBUG
    /// Debug-only shortcut that fakes a signed-in state without going
    /// through Apple + Supabase. Used on the simulator when SIWA is
    /// flaky (no iCloud account, provider not configured in Supabase,
    /// etc.) so we can test non-auth features like the paywall.
    ///
    /// This function is compiled out of Release builds entirely, so it
    /// cannot ship to TestFlight or the App Store.
    func signInForDevelopment() {
        let devID = UUID(uuidString: "00000000-0000-0000-0000-0000DEADBEEF")
            ?? DeviceIdentity.localUserID
        self.currentUserID = devID
        self.isSignedIn = true
        self.displayName = "Dev Tester"
        UserDefaults.standard.set("Dev Tester", forKey: displayNameKey)
        self.lastError = nil
    }
    #endif

    // MARK: - Email + password sign-up / sign-in (v1.1)
    //
    // Supabase Auth's primary identifier is an email address, so the
    // user-facing "username" maps to email under the hood. Passwords
    // are NEVER stored locally — only the resulting Supabase JWT
    // (already keychain-backed by supabase-swift) persists.

    /// Create a new account with an email + password. On success the
    /// returned session is applied and `isSignedIn` flips to true.
    /// On failure `lastError` is populated and the call returns false.
    @discardableResult
    func signUp(email: String, password: String, displayName: String? = nil) async -> Bool {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedEmail.isEmpty else {
            lastError = "Email is required."
            return false
        }
        guard password.count >= 8 else {
            lastError = "Password must be at least 8 characters."
            return false
        }

        #if canImport(Supabase)
        do {
            let response = try await SupabaseConfig.client.auth.signUp(
                email: cleanedEmail,
                password: password
            )

            // Supabase may require email confirmation depending on the
            // project's auth settings. If a session is returned the user
            // is signed in immediately; otherwise we surface a helpful
            // message and keep the user on the sign-in screen.
            if let session = response.session {
                applySession(userID: session.user.id, email: session.user.email)
                lastError = nil
            } else {
                lastError = "Account created — check your inbox to confirm your email before signing in."
                return false
            }

            // Best-effort: write the display name to user metadata so
            // it shows in Settings → Account.
            if let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !display.isEmpty {
                _ = try? await SupabaseConfig.client.auth.update(
                    user: UserAttributes(data: ["full_name": .string(display)])
                )
                UserDefaults.standard.set(display, forKey: displayNameKey)
                self.displayName = display
            }
            return true
        } catch {
            lastError = friendlyAuthError(error)
            return false
        }
        #else
        // Without the Supabase package, fall through to a local-only
        // signed-in state so the rest of the app can still be exercised.
        isSignedIn = true
        currentUserID = DeviceIdentity.localUserID
        if let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !display.isEmpty {
            UserDefaults.standard.set(display, forKey: displayNameKey)
            self.displayName = display
        }
        lastError = nil
        return true
        #endif
    }

    /// Sign an existing user in by email + password.
    @discardableResult
    func signIn(email: String, password: String) async -> Bool {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedEmail.isEmpty else {
            lastError = "Email is required."
            return false
        }
        guard !password.isEmpty else {
            lastError = "Password is required."
            return false
        }

        #if canImport(Supabase)
        do {
            let session = try await SupabaseConfig.client.auth.signIn(
                email: cleanedEmail,
                password: password
            )
            applySession(userID: session.user.id, email: session.user.email)
            lastError = nil
            return true
        } catch {
            lastError = friendlyAuthError(error)
            return false
        }
        #else
        isSignedIn = true
        currentUserID = DeviceIdentity.localUserID
        lastError = nil
        return true
        #endif
    }

    /// Trigger a password-reset email for the given address. Returns
    /// true if the request was accepted (the user should now check
    /// their inbox). Surfaces friendly errors via `lastError` on
    /// failure.
    @discardableResult
    func resetPassword(email: String) async -> Bool {
        let cleanedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedEmail.isEmpty else {
            lastError = "Enter the email address on your account."
            return false
        }

        #if canImport(Supabase)
        do {
            try await SupabaseConfig.client.auth.resetPasswordForEmail(cleanedEmail)
            lastError = nil
            return true
        } catch {
            lastError = friendlyAuthError(error)
            return false
        }
        #else
        // No Supabase package — pretend success so the UI flow can be
        // exercised on a sandbox build.
        lastError = nil
        return true
        #endif
    }

    /// Translate Supabase auth errors into user-friendly copy so the
    /// login form doesn't expose stack-trace-style noise.
    private func friendlyAuthError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login") || raw.contains("invalid credentials") {
            return "Invalid email or password."
        }
        if raw.contains("already registered") || raw.contains("user already") {
            return "An account with that email already exists. Try signing in."
        }
        if raw.contains("password should be") || raw.contains("password is too") {
            return "Password is too short — use at least 8 characters."
        }
        if raw.contains("invalid email") {
            return "That doesn't look like a valid email address."
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("connection") {
            return "No internet connection. Try again in a moment."
        }
        return error.localizedDescription
    }

    // MARK: - Sign out

    func signOut() async {
        #if canImport(Supabase)
        do {
            try await SupabaseConfig.client.auth.signOut()
        } catch {
            lastError = error.localizedDescription
        }
        #endif
        isSignedIn = false
        currentUserID = nil
        currentUserEmail = nil
    }

    // MARK: - Delete account (App Store Guideline 5.1.1(v))

    /// Permanently deletes the signed-in user's account and all server-side
    /// data associated with it, then signs out locally.
    ///
    /// Server side, this invokes the `delete_user_account` RPC in Supabase,
    /// which must:
    ///   1. Delete all rows owned by `auth.uid()` in public tables.
    ///   2. Call `auth.admin.delete_user(auth.uid())` via a security-definer
    ///      function so the auth record itself is removed.
    ///
    /// The App Store requires in-app account deletion for any app that
    /// creates accounts, per Guideline 5.1.1(v). This method is the entry
    /// point Settings → "Delete Account" calls.
    ///
    /// - Returns: `true` if the deletion RPC succeeded and the local session
    ///   was cleared, `false` otherwise (error is surfaced via `lastError`).
    @discardableResult
    func deleteAccount() async -> Bool {
        #if canImport(Supabase)
        // Only invoke the server RPC if we actually have a live session
        // with a JWT. A user who signed in via the DEBUG bypass, or whose
        // session expired locally, has nothing to delete on the server —
        // and calling the RPC without a JWT would 401 and confuse the
        // user. In those cases we fall through to the local cleanup.
        let hasLiveSession = (try? await SupabaseConfig.client.auth.session) != nil
        if hasLiveSession {
            do {
                _ = try await SupabaseConfig.client
                    .rpc("delete_user_account")
                    .execute()
            } catch {
                lastError = "Couldn't delete your account: \(error.localizedDescription)"
                return false
            }

            // Clear the auth session — the server already destroyed the
            // user record, so the refresh token is dead anyway, but this
            // evicts it from the keychain so nothing tries to use it.
            _ = try? await SupabaseConfig.client.auth.signOut()
        }
        #endif

        // Wipe locally cached identity + display name.
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        displayName = nil
        isSignedIn = false
        currentUserID = nil
        currentUserEmail = nil
        lastError = nil
        return true
    }

    // MARK: - Private

    private func exchangeAppleCredential(_ authorization: ASAuthorization) async {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
            lastError = "Apple credential missing"
            return
        }

        guard
            let nonce = currentNonce,
            let tokenData = cred.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else {
            lastError = "Apple identity token missing"
            return
        }

        // Extract name once — Apple only returns it on first consent.
        let nameTriplet: (given: String, family: String, combined: String)? = {
            guard
                let fullName = cred.fullName,
                let given = fullName.givenName, !given.isEmpty
            else { return nil }
            let family = fullName.familyName ?? ""
            let combined = family.isEmpty ? given : "\(given) \(family)"
            return (given, family, combined)
        }()

        #if canImport(Supabase)
        do {
            let session = try await SupabaseConfig.client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            applySession(userID: session.user.id, email: session.user.email)
            lastError = nil

            // Push the Apple-provided name to Supabase Auth metadata so
            // it's available on the server. We don't block the sign-in
            // on this — best-effort.
            if let name = nameTriplet {
                // Best-effort metadata write — never block sign-in on it.
                _ = try? await SupabaseConfig.client.auth.update(
                    user: UserAttributes(
                        data: [
                            "full_name":   .string(name.combined),
                            "given_name":  .string(name.given),
                            "family_name": .string(name.family)
                        ]
                    )
                )
                // Cache locally for instant UI.
                UserDefaults.standard.set(name.combined, forKey: displayNameKey)
                displayName = name.combined
            }
        } catch {
            lastError = error.localizedDescription
        }
        #else
        // Without Supabase, pretend we signed in using the Apple user id.
        let deviceID = UUID(uuidString: cred.user) ?? DeviceIdentity.localUserID
        isSignedIn = true
        currentUserID = deviceID
        if let name = nameTriplet {
            UserDefaults.standard.set(name.combined, forKey: displayNameKey)
            displayName = name.combined
        }
        #endif

        currentNonce = nil
    }

    private func applySession(userID: UUID, email: String? = nil) {
        self.currentUserID = userID
        self.isSignedIn = true
        if let email, !email.isEmpty {
            self.currentUserEmail = email.lowercased()
        }
    }

    // MARK: - Nonce helpers (per Apple's Sign in with Apple guide)

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            for r in randoms where remaining > 0 {
                if r < charset.count {
                    result.append(charset[Int(r)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Device fallback identity

/// Stable per-device UUID used when Supabase isn't linked yet.
private enum DeviceIdentity {

    private static let key = "sacred.bill.tracker.device.userID.v1"

    static let localUserID: UUID = {
        if let raw = UserDefaults.standard.string(forKey: key),
           let existing = UUID(uuidString: raw) {
            return existing
        }
        let fresh = UUID()
        UserDefaults.standard.set(fresh.uuidString, forKey: key)
        return fresh
    }()
}
