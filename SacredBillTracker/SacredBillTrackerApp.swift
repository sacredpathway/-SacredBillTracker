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
                .environmentObject(reviewPrompt)
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
                    profileStore.applyPremiumAccess(subscriptions.isPro)
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
                .onChange(of: scenePhase) { _, newPhase in
                    // Refresh the gate every time the app returns to the
                    // foreground.
                    if newPhase == .active {
                        Task { await versionGate.refresh() }

                        // AppsFlyer — request ATT once, then start the SDK once.
                        // Guarded so it's a no-op until the package is linked.
                        #if canImport(AppsFlyerLib)
                        AppsFlyerManager.shared.requestATTThenStart()
                        #endif
                    }
                }
                .onChange(of: auth.currentUserID) { _, newUserID in
                    Task { await handleUserChange(newUserID) }
                }
                .onChange(of: subscriptions.isPro) { _, isPro in
                    profileStore.applyPremiumAccess(isPro)
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
            if let caching = Self.repo as? CachingBillRepository {
                await caching.clearLocalCache()
            }
            return
        }

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
    private var didStart = false
    /// True only when a real (non-placeholder) Dev Key was found and applied.
    private var isConfigured = false
    private override init() { super.init() }

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
            print("[AppsFlyer] Dev Key not configured (placeholder). AppsFlyer will not start. " +
                  "Set APPSFLYER_DEV_KEY in Secrets.xcconfig.")
            isConfigured = false
            return
        }
        let af = AppsFlyerLib.shared()
        af.appsFlyerDevKey = devKey
        af.appleAppID      = "6762890363"               // Sacred Bill Tracker iOS App ID
        af.delegate        = self
        // Hold the install postback until ATT is answered (or 60s) so the
        // IDFA is included when the user grants tracking.
        af.waitForATTUserAuthorization(timeoutInterval: 60)
        // af.isDebug = true   // DEV ONLY — remove before release
        isConfigured = true
    }

    /// Request ATT once, then start the SDK once. SKAdNetwork still works if
    /// the user denies ATT. No-op when the Dev Key is not configured.
    func requestATTThenStart() {
        guard isConfigured else { return }
        if #available(iOS 14, *) {
            ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
                DispatchQueue.main.async { self?.start() }
            }
        } else {
            start()
        }
    }

    private func start() {
        guard isConfigured, !didStart else { return }
        didStart = true
        AppsFlyerLib.shared().start()
    }
}

extension AppsFlyerManager: AppsFlyerLibDelegate {
    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) { /* deferred deep-link data (unused) */ }
    func onConversionDataFail(_ error: Error) { /* no-op */ }
}
#endif
