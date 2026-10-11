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

// MARK: - Session owner cache

/// Remembers the last signed-in owner ID **solely** so that the cold-launch
/// window — after `AuthService.bootstrap()` starts but before the Supabase
/// session comes back — can keep showing that user's locally cached income
/// instead of collapsing every total to $0.
///
/// Cleared on sign-out and on account deletion, so a signed-out device never
/// reveals the previous user's rows.
enum SessionOwnerCache {

    private static let key = "sacred.bill.tracker.auth.lastOwnerID.v1"

    static var lastKnownOwnerID: UUID? {
        UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func remember(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - Public API

@MainActor
final class AuthService: NSObject, ObservableObject {

    /// True once a Supabase session exists.
    @Published private(set) var isSignedIn: Bool = false

    /// The Supabase-assigned user ID. `nil` while signed out.
    @Published private(set) var currentUserID: UUID?

    /// `false` until the initial session restore (`bootstrap()`) finishes —
    /// success, no session, or error alike.
    ///
    /// Consumers MUST NOT treat `currentUserID == nil` as "signed out" until
    /// this is `true`. Before that it means "we don't know yet". Conflating
    /// the two is what made monthly income read $0 on every cold launch.
    @Published private(set) var hasResolvedSession: Bool = false

    /// Human-readable name from the Apple credential, if we captured one
    /// on first sign-in. Cached in UserDefaults because Apple only
    /// returns it the *first* time the user signs in.
    @Published private(set) var displayName: String?

    /// Email on the current Supabase session. Used for account display and
    /// DEBUG-only local QA helpers.
    @Published private(set) var currentUserEmail: String?

    /// Last auth error for UI to surface.
    @Published var lastError: String?

    // Raw nonce kept alive for a single sign-in round-trip.
    private var currentNonce: String?

    static let shared = AuthService()

    private let displayNameKey = "sacred.bill.tracker.auth.displayName.v1"

    private func attributionDebugLog(_ message: String) {
        #if DEBUG
        print("[AppsFlyer][Auth] \(message)")
        #endif
    }

    override init() {
        super.init()
        displayName = UserDefaults.standard.string(forKey: displayNameKey)
        Task { await bootstrap() }
    }

    // MARK: - Bootstrap / session restore

    /// Called on init — loads any existing Supabase session so the
    /// user stays signed in across launches.
    func bootstrap() async {
        // Resolve exactly once, on every exit path: success, no session,
        // or thrown error. Until this flips, income treats a nil owner as
        // "unknown" rather than "signed out".
        defer { hasResolvedSession = true }

        #if canImport(Supabase)
        do {
            let session = try await SupabaseConfig.client.auth.session
            applySession(userID: session.user.id, email: session.user.email)
        } catch {
            // Network failure does not sign out a previously authenticated
            // cached SDK session. It supplies identity only, never entitlement
            // freshness. Invalid/absent sessions and anonymous users stay denied.
            if error is URLError, let cached = SupabaseConfig.client.auth.currentSession,
               !cached.user.isAnonymous {
                applySession(userID: cached.user.id, email: cached.user.email)
            } else {
                isSignedIn = false
                currentUserID = nil
            }
        }
        #else
        // Without the Supabase package, behave as a single-user local app.
        isSignedIn = true
        currentUserID = DeviceIdentity.localUserID
        SessionOwnerCache.remember(DeviceIdentity.localUserID)
        #endif
    }

    /// Durable account proof only. Never use the DEBUG bypass or device-local ID
    /// to bind a store purchase. Existing local-only purchasing remains available.
    func verifiedPurchaseAccountID() async -> UUID? {
        #if canImport(Supabase)
        guard let expected = currentUserID, isSignedIn,
              let session = try? await SupabaseConfig.client.auth.session,
              session.user.id == expected, currentUserID == expected, isSignedIn,
              !session.user.isAnonymous else { return nil }
        return session.user.id
        #else
        return nil
        #endif
    }

    /// Cached authenticated SDK identity is sufficient to SELECT an existing
    /// verified offline envelope. It is never sufficient to create one.
    var offlineEntitlementAccountID: UUID? {
        #if canImport(Supabase)
        guard isSignedIn, let expected = currentUserID,
              let session = SupabaseConfig.client.auth.currentSession,
              session.user.id == expected, !session.user.isAnonymous else { return nil }
        return expected
        #else
        return nil
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
        self.hasResolvedSession = true
        SessionOwnerCache.remember(devID)
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
                // Attribution: signup_completed (no-op while AppsFlyer dormant).
                #if canImport(AppsFlyerLib)
                attributionDebugLog("Registration success path reached; requesting af_complete_registration")
                AppsFlyerManager.shared.logAccountCreated()
                #endif
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
        hasResolvedSession = true
        SessionOwnerCache.remember(DeviceIdentity.localUserID)
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
        hasResolvedSession = true
        SessionOwnerCache.remember(DeviceIdentity.localUserID)
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
        SBTVerifiedEntitlementStore.shared.signOut()
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
        hasResolvedSession = true
        // Signed out is a *known* state — drop the restore-window hint so the
        // previous owner's income can never be read back.
        SessionOwnerCache.clear()
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

        SBTVerifiedEntitlementStore.shared.signOut()
        // Wipe locally cached identity + display name.
        UserDefaults.standard.removeObject(forKey: displayNameKey)
        displayName = nil
        isSignedIn = false
        currentUserID = nil
        currentUserEmail = nil
        lastError = nil
        hasResolvedSession = true
        SessionOwnerCache.clear()
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
        hasResolvedSession = true
        SessionOwnerCache.remember(deviceID)
        if let name = nameTriplet {
            UserDefaults.standard.set(name.combined, forKey: displayNameKey)
            displayName = name.combined
        }
        #endif

        currentNonce = nil
    }

    private func applySession(userID: UUID, email: String? = nil) {
        SBTVerifiedEntitlementStore.shared.changeAccount(userID)
        self.currentUserID = userID
        self.isSignedIn = true
        self.hasResolvedSession = true
        SessionOwnerCache.remember(userID)
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

// MARK: - Isolated account-service integration

/// An authenticated server response may display sandbox state, never grant Release access.
struct SBTAccountSnapshot: Decodable {
    let account: UUID
    let environment: String
    let lifetime: SBTLifetimeSnapshot?
    let subscriptions: [SBTSubscriptionSnapshot]?
    let offers_enabled: Bool
    let marketing: SBTMarketingSnapshot

    func validate(owner: UUID) -> Bool {
        account == owner && environment == "sandbox" && !offers_enabled &&
        !marketing.production_sending_enabled && (lifetime?.isValidSandboxContract ?? true) &&
        (subscriptions ?? []).allSatisfy { $0.isValidSandboxContract } &&
        Set((subscriptions ?? []).map(\.original_transaction_id)).count == (subscriptions ?? []).count
    }
}
/// Display/recovery data only. Never merged into Release feature gates or persisted offline.
struct SBTSubscriptionSnapshot: Decodable {
    let original_transaction_id: String
    let product: String
    let active: Bool
    let revoked: Bool
    let expires_at: String
    let environment: String
    var expiration: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: expires_at) ?? ISO8601DateFormatter().date(from: expires_at)
    }
    var isValidSandboxContract: Bool {
        environment == "sandbox" && PlanTier.from(productID: product) != .free &&
        !original_transaction_id.isEmpty && original_transaction_id.count <= 64 &&
        original_transaction_id.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } &&
        expiration != nil && !(active && revoked)
    }
    func tier(at now: Date) -> PlanTier {
        guard isValidSandboxContract, active, !revoked, let expiry = expiration, expiry > now else { return .free }
        return PlanTier.from(productID: product)
    }
}
struct SBTLifetimeSnapshot: Decodable {
    let entitlement_id: String
    let environment: String
    let scope: String
    let platform: String
    let product: String
    let tier: String
    let version: Int
    var isValidSandboxContract: Bool {
        entitlement_id == "lifetime_premium_v1" && environment == "sandbox" &&
        scope == "staging-premium-only" && version == 1 && platform == "apple" &&
        ["essential_monthly_499", "business_monthly_999", "unlimited_monthly_1499",
         "com.sacredbilltracker.app.pro.monthly", "com.sacredbilltracker.app.pro.yearly"].contains(product) &&
        tier != "free" && PlanTier.from(productID: product).rawValue == tier
    }
}
struct SBTMarketingSnapshot: Decodable {
    let state: String
    let suppressed: Bool
    let production_sending_enabled: Bool
}

enum SBTAccountConnection {
    static let lifetimeWarning = "Lifetime Premium does not automatically cancel an existing App Store or Google Play subscription."
    static let sandboxAuthIssuer = "https://thwjnpofhrpxfuvwkfgd.supabase.co/auth/v1"
    static let sandboxAccountBase = "https://thwjnpofhrpxfuvwkfgd.supabase.co/functions/v1/sbt-sandbox-account"
    static func approvedOrigin(_ raw: String) -> URL? {
        guard raw == sandboxAccountBase else { return nil }
        return URL(string: raw)
    }
    /// Outbound leak prevention only; the server still verifies JWT signature/claims.
    static func permitsSandboxBearer(_ token: String, owner: UUID, now: Date = Date()) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.count <= 16384 else { return false }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              claims["iss"] as? String == sandboxAuthIssuer,
              claims["aud"] as? String == "authenticated",
              let subject = claims["sub"] as? String, UUID(uuidString: subject) == owner,
              let expiry = claims["exp"] as? Double, expiry > now.timeIntervalSince1970 else { return false }
        return true
    }
    static var configuredOrigin: URL? {
        // No endpoint is guessed. Sandbox access is compiled out of Release.
        #if DEBUG
        return approvedOrigin(ProcessInfo.processInfo.environment["SBT_SANDBOX_ACCOUNT_URL"] ?? "")
        #else
        return nil
        #endif
    }
}

#if DEBUG && canImport(Supabase)
/// Explicitly configured sandbox Auth; never reuses the app's production client/storage.
@MainActor
final class SBTSandboxSession: ObservableObject {
    static let shared = SBTSandboxSession()
    @Published private(set) var revision = 0
    @Published private(set) var message = "Real sandbox authentication is deferred."
    @Published private(set) var busy = false
    private let client: SupabaseClient?
    var isConfigured: Bool { client != nil }
    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        if SBTAccountConnection.approvedOrigin(environment["SBT_SANDBOX_ACCOUNT_URL"] ?? "") != nil,
           let key = environment["SBT_SANDBOX_ANON_KEY"], !key.isEmpty {
            client = SupabaseClient(supabaseURL: URL(string: "https://thwjnpofhrpxfuvwkfgd.supabase.co")!, supabaseKey: key,
                options: .init(auth: .init(storageKey: "sbt.sandbox.thwjnpofhrpxfuvwkfgd.auth", autoRefreshToken: true)))
        } else { client = nil }
    }
    func verifiedSession() async throws -> (owner: UUID, bearer: String) {
        guard let client else { throw URLError(.userAuthenticationRequired) }
        let expectedRevision = revision
        let session = try await client.auth.session
        guard revision == expectedRevision, !session.user.isAnonymous,
              SBTAccountConnection.permitsSandboxBearer(session.accessToken, owner: session.user.id) else {
            throw URLError(.userAuthenticationRequired)
        }
        return (session.user.id, session.accessToken)
    }
    func signIn(email: String, password: String) async {
        guard let client, !busy else { return }
        busy = true
        defer { busy = false }
        revision += 1
        do {
            _ = try await client.auth.signIn(email: email, password: password)
            _ = try await verifiedSession()
            message = "Sandbox sign-in verified."
        } catch { message = "Sandbox sign-in could not be verified." }
        revision += 1
    }
    func refresh() async {
        guard let client, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await client.auth.refreshSession()
            _ = try await verifiedSession()
            message = "Sandbox session refreshed."
        } catch { message = "Sandbox refresh could not be verified." }
        revision += 1
    }
    func signOut() async {
        guard let client, !busy else { return }
        busy = true
        defer { busy = false }
        revision += 1
        var revoked = false
        if let session = try? await verifiedSession(), let origin = SBTAccountConnection.configuredOrigin {
            var request = URLRequest(url: origin.appendingPathComponent("logout"))
            request.httpMethod = "POST"; request.httpBody = Data("{}".utf8); request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer " + session.bearer, forHTTPHeaderField: "Authorization")
            let transport = URLSession(configuration: .ephemeral, delegate: SBTNoRedirect(), delegateQueue: nil)
            defer { transport.invalidateAndCancel() }
            if let (_, response) = try? await transport.data(for: request) { revoked = (response as? HTTPURLResponse)?.statusCode == 200 }
        }
        do {
            try await client.auth.signOut(scope: .global)
            message = revoked ? "Sandbox session signed out and revoked." : "Signed out locally. Sandbox revocation could not be confirmed."
        } catch { message = "Signed out locally. Remote logout could not be confirmed." }
        revision += 1
    }
}
#endif

private final class SBTNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // Never forward an account bearer token to a redirect.
    }
}

@MainActor
final class SBTAccountIntegration: ObservableObject {
    @Published private(set) var snapshot: SBTAccountSnapshot?
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    private var revision = 0
    private let origin: URL? = SBTAccountConnection.configuredOrigin
    var isConfigured: Bool { origin != nil }

    func clear() {
        revision += 1
        snapshot = nil
        message = ""
        busy = false
    }

    func refresh() async { await perform(path: "account", body: [:]) }
    static func appleVerificationPayload(originalTransactionID: String) -> [String: String] {
        ["original_transaction_id": originalTransactionID, "platform": "apple"]
    }

    func verifySubscription(originalTransactionID: String) async {
        await perform(path: "subscriptions/verify", body: Self.appleVerificationPayload(originalTransactionID: originalTransactionID))
    }
    func optIn(email: String, consent: Bool) async {
        guard consent else { return }
        await perform(path: "marketing/opt-in", body: ["email": email, "consent": true,
            "source": "ios_settings", "version": "sbt-marketing-v1-draft"])
    }
    func optOut() async { await perform(path: "marketing/opt-out", body: [:]) }

    private func perform(path: String, body: [String: Any]) async {
        guard !busy else { return }
        guard let origin else {
            message = "Account benefit recovery is not available yet. You can still restore purchases through Apple."
            return
        }
        let requestRevision = revision
        busy = true
        defer { if revision == requestRevision { busy = false } }
        #if DEBUG && canImport(Supabase)
        do {
            let sessionRevision = SBTSandboxSession.shared.revision
            let session = try await SBTSandboxSession.shared.verifiedSession()
            let owner = session.owner
            guard requestRevision == revision else { throw URLError(.userAuthenticationRequired) }
            var request = URLRequest(url: origin.appendingPathComponent(path))
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("Bearer " + session.bearer, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.urlCache = nil
            let transport = URLSession(configuration: config, delegate: SBTNoRedirect(), delegateQueue: nil)
            defer { transport.invalidateAndCancel() }
            let (data, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= 65536,
                  revision == requestRevision,
                  sessionRevision == SBTSandboxSession.shared.revision,
                  owner == (try await SBTSandboxSession.shared.verifiedSession()).owner,
                  revision == requestRevision else { throw URLError(.badServerResponse) }
            let value = try JSONDecoder().decode(SBTAccountSnapshot.self, from: data)
            guard value.validate(owner: owner) else { throw URLError(.cannotParseResponse) }
            snapshot = value
            message = "Sandbox account checked. Production benefits and email sending remain off."
            if path == "marketing/opt-in" { AnalyticsService.shared.track(.marketingOptIn, source: "settings") }
            if path == "marketing/opt-out" { AnalyticsService.shared.track(.marketingOptOut, source: "settings") }
        } catch {
            guard revision == requestRevision else { return }
            snapshot = nil
            message = "Could not verify account preferences. No new access was granted. Try again when connected."
        }
        #else
        message = "Account service unavailable."
        #endif
    }
}
