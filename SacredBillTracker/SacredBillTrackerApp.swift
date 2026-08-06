//
//  SacredBillTrackerApp.swift
//  SacredBillTracker
//
//  App entry point. Wires up:
//    - Authentication via Sign in with Apple → Supabase
//    - Offline-first CachingBillRepository (local cache + Supabase sync)
//    - BillStore observed by every view
//    - NotificationManager for local reminders
//
//  Before sign-in completes, we render `SignInView`. After, `ContentView`.
//

import SwiftUI

// MARK: - Attribution (AppsFlyer) — additive, off until the SPM package is linked
//
// Everything AppsFlyer-related is wrapped in `#if canImport(AppsFlyerLib)`.
// Until you add the `AppsFlyerFramework` Swift Package, these blocks compile
// to nothing, so the current build/behaviour is unchanged. After you add the
// package + the Info.plist keys (see SacredBillTracker_iOS_AppsFlyer_Integration.md),
// installs flow to TikTok via AppsFlyer. Touches no other app feature.
#if canImport(AppsFlyerLib)
import AppsFlyerLib
import AppTrackingTransparency
#endif

// MARK: - Root scene
//
// Wraps the auth-routed view so we can attach `@Environment(\.requestReview)`
// — that environment value is only available inside a SwiftUI View, so it
// cannot live directly on the App-level body.

private struct RootScene: View {

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var review: ReviewPromptService
    @EnvironmentObject private var versionGate: VersionGateService
    @Environment(\.requestReview) private var requestReview

    /// v1.0.9 — Read the user's Appearance preference at the root so
    /// `.preferredColorScheme(_:)` reflects it across the whole app.
    @AppStorage("sbt.appearance.v1") private var appearanceRaw: String = AppearancePreference.system.rawValue

    @State private var showOptionalUpdateSheet = false

    // NOTE — v1.2 spec briefly required a hard paywall gate immediately
    // after sign-in. Reversed in v1.2.1 to protect existing free-tier
    // users from a forced upgrade prompt on first launch after update.
    // Paywall is now only triggered contextually (Reports tab, 6th bill,
    // business bills, Pro features in Settings) — the existing
    // `ProLockCard` / `.paywallSheet` infrastructure handles those.

    var body: some View {
        Group {
            switch versionGate.gateState {
            case .blocked(let message, let url):
                // HARD BLOCK — root view is replaced entirely. Cannot
                // be dismissed; ContentView/AuthGateView never mount.
                ForceUpdateView(message: message, appStoreURL: url)

            case .loading, .allowed, .optionalUpdate:
                Group {
                    if !auth.isSignedIn {
                        // Not signed in — show the auth chooser (email/
                        // password sign-in, create account, or Sign in
                        // with Apple).
                        AuthGateView()
                    } else {
                        // Signed in (any tier) — go straight to the app.
                        // Paywall is surfaced contextually by ProLockCard
                        // / FreeTierLimits when the user attempts a Pro
                        // feature.
                        ContentView()
                    }
                }
                .sheet(isPresented: $showOptionalUpdateSheet) {
                    if case .optionalUpdate(let latestBuild) = versionGate.gateState,
                       let cfg = versionGate.lastConfig,
                       let url = URL(string: cfg.appStoreURL) {
                        UpdateAvailableSheet(
                            latestBuild: latestBuild,
                            appStoreURL: url,
                            onDismiss: { versionGate.dismissOptionalUpdate() }
                        )
                    }
                }
                .onChange(of: versionGate.gateState) { _, newState in
                    if case .optionalUpdate = newState {
                        showOptionalUpdateSheet = true
                    } else {
                        showOptionalUpdateSheet = false
                    }
                }
            }
        }
        .onChange(of: review.pendingReviewRequest) { _, newValue in
            guard newValue != nil else { return }
            // Apple's system sheet — never a custom replacement.
            requestReview()
            review.markRequested()
        }
        // v1.0.9 — applies the user's Appearance picker choice
        // (Light / Dark / System) instantly across the whole app.
        .preferredColorScheme(
            AppearancePreference.from(rawValue: appearanceRaw).colorScheme
        )
    }
}

@main
struct SacredBillTrackerApp: App {

    // MARK: - Repository stack

    /// Pure-local fallback repo.
    private static let localRepo = LocalBillRepository()

    /// Offline-first decorator that syncs to Supabase when online.
    /// If the user hasn't filled in `SupabaseConfig` (or the SPM package
    /// isn't linked yet), `SupabaseBillRepository` transparently falls
    /// back to local — so this never crashes a fresh build.
    private static let repo: BillRepository = CachingBillRepository(
        local:  localRepo,
        remote: SupabaseBillRepository()
    )

    // MARK: - State

    @StateObject private var store = BillStore(repository: repo)
    @StateObject private var incomeStore = IncomeStore()
    @StateObject private var profileStore = ManagedProfileStore.shared
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var auth = AuthService.shared
    @StateObject private var subscriptions = SubscriptionManager()
    /// 3-tier plan entitlements (Essential / Business / Unlimited).
    @StateObject private var tiers = TierEntitlementManager()
    @StateObject private var reviewPrompt = ReviewPromptService.shared
    @StateObject private var versionGate = VersionGateService.shared
    /// v1.0.9.x — Sacred Focus productivity system stores.
    @StateObject private var noteStore = NoteStore()
    @StateObject private var scheduleStore = ScheduleStore()
    @StateObject private var todoStore = TodoStore()

    /// Tracks foreground/background so we can re-fetch the version gate
    /// every time the user returns to the app — that catches the
    /// "user kept the app suspended for two days" case where a force
    /// update may have shipped in the meantime.
    @Environment(\.scenePhase) private var scenePhase

    /// Owns the Supabase Realtime channel for the current user's bills.
    private let realtime = BillsRealtimeService()

    init() {
        // Dark-green + gold brand theme — configure UIKit chrome
        // (nav bars, tab bar, List/Form backgrounds) once at launch so
        // every screen adopts the green canvas + gold accents.
        ThemeAppearance.apply()

        // AppsFlyer — set keys only (no network call yet). Inert until the
        // AppsFlyerFramework SPM package is linked.
        #if canImport(AppsFlyerLib)
        AppsFlyerManager.shared.configure()
        #endif

        // TikTok — initialize the Business SDK. Install/launch events are sent
        // AUTOMATICALLY by the SDK once initialized; we never hand-roll them.
        // Inert until the TikTokBusinessSDK SPM package is linked AND real
        // credentials exist in the git-ignored Secrets.xcconfig.
        #if canImport(TikTokBusinessSDK)
        TikTokEventsManager.shared.configureAndInitialize()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootScene()
                .environmentObject(store)
                .environmentObject(incomeStore)
                .environmentObject(profileStore)
                .environmentObject(notifications)
                .environmentObject(auth)
                .environmentObject(subscriptions)
                .environmentObject(tiers)
                .environmentObject(reviewPrompt)
                .task { await tiers.start() }
                .environmentObject(versionGate)
                .environmentObject(noteStore)
                .environmentObject(scheduleStore)
                .environmentObject(todoStore)
                .tint(.appAccentText)
                .task {
                    // DEBUG-only — surfaces PaymentURLValidator regressions
                    // in the Xcode console on first launch. No-op in Release.
                    _runPaymentURLValidatorSelfCheck()

                    // Forced-update gate — fetch on cold launch BEFORE
                    // anything else. Safe-fallback on failure (allowed).
                    await versionGate.refresh()
                    await subscriptions.refreshEntitlements()
                    profileStore.applyPremiumAccess(subscriptions.canManagedProfiles)
                    applyProfileContext()

                    // Once-per-cold-launch counter for the in-app review gate.
                    reviewPrompt.recordAppLaunch()
                    // Pull a fresh quote from Quotable / ZenQuotes in the
                    // background. The cached + day-of-year fallback already
                    // shows on screen by now, so this just upgrades it.
                    QuoteService.shared.refreshInBackground()
                    // Ask for notification permission on first launch only.
                    if notifications.authorizationStatus == .notDetermined {
                        _ = await notifications.requestAuthorization()
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    // Refresh the gate every time the app returns to the
                    // foreground.
                    if newPhase == .active {
                        Task { await versionGate.refresh() }

                        // AppsFlyer — resolve ATT, then start the active session.
                        // Guarded so it's a no-op until the package is linked.
                        #if canImport(AppsFlyerLib)
                        AppsFlyerManager.shared.requestATTThenStart()
                        #endif

                        // TikTok — the SDK never prompts for ATT itself, so we
                        // request it here, once, only after the UI is active.
                        // No-op unless NSUserTrackingUsageDescription exists.
                        #if canImport(TikTokBusinessSDK)
                        TikTokEventsManager.shared.requestATTOnce()
                        #endif
                    }
                }
                .onChange(of: auth.currentUserID) { _, newUserID in
                    Task { await handleUserChange(newUserID) }
                }
                // Session restore finished. When `bootstrap()` finds NO session,
                // `currentUserID` goes nil → nil, which is not a change, so the
                // handler above never fires. Without this the stores would stay
                // in the `.unresolved` restore window forever: the income profile
                // partition would never re-engage, and a merely *expired* session
                // (as opposed to an explicit signOut, which clears the cache)
                // would keep the previous owner's income readable.
                .onChange(of: auth.hasResolvedSession) { _, _ in
                    applyProfileContext()
                }
                .onChange(of: subscriptions.canManagedProfiles) { _, canProfiles in
                    profileStore.applyPremiumAccess(canProfiles)
                    applyProfileContext()
                }
                // Use onChange (fires AFTER the value updates) rather than
                // onReceive($published) (fires in willSet, BEFORE the value
                // updates). Reading profileStore.context inside onReceive saw
                // the stale, pre-tap selection, so switching profiles lagged
                // one tap behind. onChange reads the committed value.
                .onChange(of: profileStore.selection) { _, _ in
                    applyProfileContext()
                }
                .onChange(of: profileStore.profiles) { _, _ in
                    applyProfileContext()
                }
                .onChange(of: auth.currentUserEmail) { _, _ in
                    // Re-check DEBUG-only local QA helpers when the user's
                    // email becomes known. Do not touch StoreKit here;
                    // products/receipts load only from paywall/subscription
                    // surfaces.
                    subscriptions.recheckOwnerOverride()
                }
        }
    }

    // MARK: - Auth → repository glue

    /// When a user signs in, migrate local-only bills up and then pull
    /// the authoritative remote set into the store.
    @MainActor
    private func handleUserChange(_ userID: UUID?) async {
        guard let userID else {
            // Signed out — tear down realtime, wipe the in-memory list,
            // AND clear the on-disk local cache so a different user
            // signing in on this same device cannot read the previous
            // user's bills out of UserDefaults before the remote refresh
            // completes. (Privacy + App Store Guideline 5.1.1.)
            await realtime.stop()
            profileStore.resetForSignedOutUser()
            applyProfileContext()
            store.resetForSignedOutUser()
            subscriptions.clearForSignedOutUser()
            // Reset the 3-tier entitlement state too, so the paywall never
            // shows the previous account's tier / "CURRENT" badge after a
            // sign-out → sign-in on the same device.
            tiers.clearForSignedOutUser()
            if let caching = Self.repo as? CachingBillRepository {
                await caching.clearLocalCache()
            }
            return
        }

        // New user signed in — reset any stale 3-tier entitlement from the
        // previous account, then re-resolve for THIS user from local StoreKit
        // entitlements + the backend `current_subscription_tier` RPC. Without
        // this, the paywall could show the prior account's tier/"CURRENT".
        tiers.clearForSignedOutUser()
        await tiers.refreshFromStoreKit()
        await tiers.refreshFromBackend()

        await profileStore.loadForSignedInUser(userID: userID, displayName: auth.displayName)
        applyProfileContext()

        if let caching = Self.repo as? CachingBillRepository {
            await caching.migrateLocalToRemoteIfNeeded(userID: userID)
            let fresh = (try? await caching.refreshFromRemote()) ?? []

            #if DEBUG
            // DEBUG ONLY: skip the legacy demo purge so dev sample data
            // is never wiped on the simulator. If the signed-in account
            // is empty, BillStore.bootstrap auto-seeds SampleData.
            if fresh.isEmpty {
                await store.reload()
            } else {
                store.replace(bills: fresh)
            }
            // v1.0.9 — DEBUG-only one-shot wipe of any leftover QA
            // sample bills from earlier dev launches. Idempotent —
            // becomes a no-op as soon as no `[QA] Sample` bills remain.
            // Never seeds. Never runs in Release.
            CategoryDetailDebugSeeder.seedIfNeeded(into: store)
            await realtime.start(userID: userID) { [weak store] in
                guard let store else { return }
                let latest = (try? await caching.refreshFromRemote()) ?? []
                store.replace(bills: latest)
            }
            #else
            // Release: run the one-time legacy demo cleanup AFTER pulling
            // the authoritative remote list. The purge issues real
            // DELETEs against Supabase via repository.delete(id:) and
            // only flips the UserDefaults flag if every delete succeeded
            // — so a network failure retries on next launch.
            let cleaned = await store.purgeLegacyDemoBillsIfNeeded(in: fresh)
            store.replace(bills: cleaned)

            // Subscribe to realtime changes so edits from other devices
            // (or the dashboard) propagate without waiting for relaunch.
            // Realtime callbacks also run the purge so demo rows that
            // somehow re-appear (e.g. another stale device pushing them
            // back up) are stripped on receipt.
            await realtime.start(userID: userID) { [weak caching, weak store] in
                guard let caching, let store else { return }
                let latest = (try? await caching.refreshFromRemote()) ?? []
                let cleanedLatest = await store.purgeLegacyDemoBillsIfNeeded(in: latest)
                store.replace(bills: cleanedLatest)
            }
            #endif
        } else {
            await store.reload()
        }
    }

    @MainActor
    private func applyProfileContext() {
        let context = profileStore.context
        store.applyProfileContext(context)
        incomeStore.applyProfileContext(context)
    }
}

// MARK: - AppsFlyer attribution manager
//
// Isolated, additive. Compiles only when the AppsFlyerFramework SPM package
// is linked (`#if canImport(AppsFlyerLib)`); otherwise this whole block is
// absent and the app behaves exactly as before. It does NOT touch billing,
// auth, bills, profiles, reminders, exports, or attachments — it only reports
// the install/launch to AppsFlyer, which posts back to TikTok.
#if canImport(AppsFlyerLib)
import UIKit

final class AppsFlyerManager: NSObject {

    static let shared = AppsFlyerManager()
    /// True only when a real (non-placeholder) Dev Key was found and applied.
    private var isConfigured = false
    private override init() { super.init() }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[AppsFlyer] \(message)")
        #endif
    }

    /// Placeholder/sentinel values that must NOT be treated as a real key.
    private static let placeholderKeys: Set<String> = [
        "", "paste_real_key_here", "APPSFLYER_DEV_KEY_HERE", "$(APPSFLYER_DEV_KEY)"
    ]

    /// Reads APPSFLYER_DEV_KEY (Info.plist key "AppsFlyerDevKey", injected from
    /// Secrets.xcconfig). Returns nil if missing or still a placeholder.
    private static func resolvedDevKey() -> String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return placeholderKeys.contains(raw) ? nil : raw
    }

    /// Call once, early (App.init). Sets keys; sends nothing yet.
    /// If the Dev Key is missing/placeholder, logs a safe warning and does NOT
    /// configure or start AppsFlyer.
    func configure() {
        guard let devKey = Self.resolvedDevKey() else {
            debugLog("Dev Key not configured (placeholder). AppsFlyer will not start.")
            isConfigured = false
            return
        }
        let af = AppsFlyerLib.shared()
        af.appsFlyerDevKey = devKey
        af.appleAppID      = "6762890363"               // Sacred Bill Tracker iOS App ID
        af.delegate        = self
        // Only hold the install postback for ATT when we actually present the
        // ATT prompt (i.e. NSUserTrackingUsageDescription is declared). In the
        // default SKAN-only posture (no usage string) we do NOT wait, so the
        // SKAdNetwork postback fires promptly without an IDFA.
        if Self.hasATTUsageString {
            af.waitForATTUserAuthorization(timeoutInterval: 60)
        }
        // af.isDebug = true   // DEV ONLY — remove before release
        isConfigured = true
        debugLog("SDK configured")
    }

    /// True only when NSUserTrackingUsageDescription is present in the bundle.
    /// Drives whether we present ATT (device-level IDFA path) or run SKAN-only.
    private static var hasATTUsageString: Bool {
        let s = (Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !s.isEmpty
    }

    /// If an ATT usage string is declared, request ATT once then start the SDK.
    /// Otherwise (default SKAN-only posture) start directly without prompting —
    /// SKAdNetwork attribution still works. No-op when the Dev Key is unset.
    func requestATTThenStart() {
        guard isConfigured else {
            debugLog("SDK start skipped (not configured)")
            return
        }
        if #available(iOS 14, *), Self.hasATTUsageString {
            ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
                DispatchQueue.main.async { self?.start() }
            }
        } else {
            start()
        }
    }

    private func start() {
        guard isConfigured else {
            debugLog("SDK start skipped (not configured)")
            return
        }
        // AppsFlyer expects start on each active-session transition. SDK
        // configuration remains one-time in App.init.
        debugLog("SDK start requested")
        AppsFlyerLib.shared().start()
        Task {
            _ = await PurchaseAttributionService.shared.recoverUnfinishedTransactions()
            _ = await PurchaseAttributionService.shared.retryPendingPurchases()
        }
    }

    // MARK: - In-app events (additive)
    //
    // All event methods are safe no-ops while AppsFlyer is dormant (placeholder
    // Dev Key → isConfigured == false). AppsFlyer queues events fired before
    // `start()` and flushes them once the SDK starts, so call sites don't need
    // to care about ordering. Event names use AppsFlyer's standard `af_` keys
    // where one exists, plus custom app engagement events.

    private func logEvent(_ name: String, values: [String: Any]? = nil) {
        guard isConfigured else {
            debugLog("Event skipped (not configured): \(name)")
            return
        }
        debugLog("Event requested: \(name)")
        AppsFlyerLib.shared().logEvent(name, withValues: values)
    }

    /// Fired once when a new account is successfully created (signup_completed).
    func logAccountCreated(method: String = "email") {
        logEvent("af_complete_registration", values: ["af_registration_method": method])
    }

    /// Fired each time the user creates a bill.
    func logBillCreated() {
        logEvent("bill_created")
    }

    /// Fired each time the user creates an income entry.
    func logIncomeCreated() {
        logEvent("income_created")
    }

    /// Purchase events must use this acknowledged path through
    /// PurchaseAttributionService. No StoreKit manager emits directly.
    func logEventAcknowledged(_ name: String, values: [String: Any]) async throws {
        guard isConfigured else {
            throw PurchaseAttributionSenderError.appsFlyerNotConfigured
        }
        debugLog("Acknowledged event requested: \(name)")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            AppsFlyerLib.shared().logEvent(
                name: name,
                values: values,
                completionHandler: { _, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            )
        }
    }
}

extension AppsFlyerManager: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) { /* deferred deep-link data (unused) */ }
    func onConversionDataFail(_ error: Error) { /* no-op */ }
}
#endif

// MARK: - TikTok Business SDK attribution manager
//
// Isolated + additive, mirroring the AppsFlyer block above. Compiles only when
// the `tiktok-business-ios-sdk` SPM package is linked (`#if canImport(TikTokBusinessSDK)`);
// otherwise this whole block is absent and the app behaves exactly as before.
//
// Design notes (verified against the SDK headers, v1.6.1):
//   • `configWithAccessToken:appId:tiktokAppId:` is the CURRENT initializer.
//     The `initWithAppId:tiktokAppId:` form is DEPRECATED and is not used here.
//   • InstallApp / LaunchAPP are sent AUTOMATICALLY after `initializeSdk`.
//     We never hand-roll app-open or install events.
//   • The SDK does NOT prompt for ATT. `requestTrackingAuthorization…` must be
//     called by the app, after the UI is active.
//   • Events use `trackTTEvent:` (the `trackEvent:` family is DEPRECATED).
//
// Runs dormant (never initializes, never sends) until BOTH the package is
// linked AND real credentials exist in the git-ignored Secrets.xcconfig.
#if canImport(TikTokBusinessSDK)
import TikTokBusinessSDK

final class TikTokEventsManager: NSObject {

    static let shared = TikTokEventsManager()

    /// True only once `initializeSdk` reported success.
    private var didInitialize = false
    /// Ensures ATT is presented at most once per process.
    private var didRequestATT = false

    private override init() { super.init() }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[TikTok] \(message)")
        #endif
    }

    /// Apple App Store ID — public identifier (same value AppsFlyer uses).
    private static let appleAppID = "6762890363"

    /// Sentinel values that must NOT be treated as real credentials. If the
    /// build setting is undefined, `$(VAR)` substitutes to an empty string.
    private static let placeholders: Set<String> = [
        "",
        "paste_real_value_here",
        "TIKTOK_ACCESS_TOKEN_HERE",
        "TIKTOK_APP_ID_HERE",
        "$(TIKTOK_ACCESS_TOKEN)",
        "$(TIKTOK_APP_ID)"
    ]

    /// Reads a value injected from Secrets.xcconfig via Info.plist.
    /// Returns nil when missing or still a placeholder.
    private static func infoValue(_ key: String) -> String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return placeholders.contains(raw) ? nil : raw
    }

    /// True only when NSUserTrackingUsageDescription is present in the bundle.
    /// Drives whether we present ATT at all.
    private static var hasATTUsageString: Bool {
        let s = (Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !s.isEmpty
    }

    /// Call once, early (App.init). Initializes the SDK; sends nothing directly.
    /// InstallApp/LaunchAPP flow automatically afterwards.
    func configureAndInitialize() {
        guard let accessToken = Self.infoValue("TikTokAccessToken"),
              let tiktokAppId = Self.infoValue("TikTokAppID") else {
            debugLog("Credentials not configured (placeholder/empty). SDK will NOT initialize.")
            return
        }
        guard let config = TikTokConfig(accessToken: accessToken,
                                        appId: Self.appleAppID,
                                        tiktokAppId: tiktokAppId) else {
            debugLog("TikTokConfig returned nil. SDK will NOT initialize.")
            return
        }

        // OPTIONAL — deliberately NOT called (see below).
        //
        // The SDK can hold its first event flush until the user answers ATT, via
        // the Objective-C selector `-setDelayForATTUserAuthorizationInSeconds:`.
        // That header carries no NS_SWIFT_NAME, so the Swift spelling is derived
        // by the Objective-C importer and could not be confirmed without a
        // compiler. Rather than ship a guessed selector (a guaranteed build
        // error), it is omitted.
        //
        // TO ENABLE (1 line, 10 seconds, inside this method, after `config` is
        // created): type `config.setDelayFor` and accept Xcode's autocomplete,
        // passing 30. Wrap it in `if Self.hasATTUsageString { … }`.
        //
        // Consequence of leaving it out: on the very first launch the automatic
        // InstallApp/LaunchAPP events may flush before ATT is answered, so they
        // can lack the IDFA. SKAdNetwork and TikTok's self-attributing network
        // are unaffected, as are all later events (Subscribe / StartTrial).

        #if DEBUG
        // Enables TikTokBusiness.getTestEventCode() for Events Manager "Test event".
        config.enableDebugMode()
        #endif

        TikTokBusiness.initializeSdk(config) { [weak self] success, error in
            self?.didInitialize = success
            if success {
                self?.debugLog("SDK initialized (v\(TikTokBusiness.getSDKVersion()))")
            } else {
                self?.debugLog("SDK init FAILED: \(String(describing: error))")
            }
        }
    }

    /// Request ATT exactly once, after the UI is active. The SDK never prompts.
    /// No-op when no usage string is declared (SKAN-only posture).
    func requestATTOnce() {
        guard Self.hasATTUsageString else {
            debugLog("ATT skipped (no NSUserTrackingUsageDescription).")
            return
        }
        guard !didRequestATT else { return }
        didRequestATT = true
        TikTokBusiness.requestTrackingAuthorization { [weak self] status in
            self?.debugLog("ATT authorization status: \(status)")
        }
    }

    // MARK: - Events
    //
    // Only ever called from a VERIFIED StoreKit transaction. Never from a
    // paywall view, a button tap, or unverified local state.

    private func track(_ name: String, properties: [String: Any]) {
        guard TikTokBusiness.isInitialized() else {
            debugLog("Event skipped (SDK not initialized): \(name)")
            return
        }
        let event = TikTokBaseEvent(eventName: name)
        for (key, value) in properties {
            _ = event.addProperty(withKey: key, value: value)
        }
        TikTokBusiness.trackTTEvent(event)
        debugLog("Event sent: \(name) \(properties)")
    }

    /// Fired when a verified transaction applied an introductory (free-trial) offer.
    func logStartTrial(productID: String, value: Decimal, currency: String) {
        track("StartTrial", properties: [
            "content_id": productID,
            "value": NSDecimalNumber(decimal: value),
            "currency": currency
        ])
    }

    /// Fired when a verified transaction started a paid subscription.
    func logSubscribe(productID: String, value: Decimal, currency: String) {
        track("Subscribe", properties: [
            "content_id": productID,
            "value": NSDecimalNumber(decimal: value),
            "currency": currency
        ])
    }
}
#endif
