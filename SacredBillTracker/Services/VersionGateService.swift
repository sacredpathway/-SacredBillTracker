//
//  VersionGateService.swift
//  SacredBillTracker
//
//  Production-safe forced update gate.
//
//  - Fetches `app_version_config` (most-recent row) from Supabase REST.
//  - Compares the running build's CFBundleVersion against
//    `minimum_supported_build`.
//  - Publishes a `gateState` that the root view observes:
//      .allowed         → render the app normally
//      .optionalUpdate  → render the app + a dismissible update prompt
//      .blocked         → render ONLY the full-screen ForceUpdateView
//
//  Safe-fallback policy:
//    - Network/server failure on a clean install → .allowed
//      (we never lock a user out because Supabase is down).
//    - Network/server failure when a previously cached config WAS
//      force-blocking → re-apply that cached decision so an attacker
//      can't bypass by going offline.
//
//  Wired into the App in SacredBillTrackerApp.swift:
//    - .task { await versionGate.refresh() }              on launch
//    - .onChange(of: scenePhase == .active) refresh       on resume
//

import Foundation
import SwiftUI

@MainActor
final class VersionGateService: ObservableObject {

    // MARK: - Public state

    enum GateState: Equatable {
        case loading
        case allowed
        case optionalUpdate(latestBuild: Int)
        case blocked(message: String, appStoreURL: URL)
    }

    static let shared = VersionGateService()

    @Published private(set) var gateState: GateState = .loading
    @Published private(set) var lastConfig: AppVersionConfig?

    /// Tracks whether the user has already dismissed the optional update
    /// prompt for the CURRENT cached `latest_build`. Persisted across
    /// launches so we don't nag every cold start.
    @AppStorage("sbt.versionGate.dismissedLatestBuild")
    private var dismissedLatestBuild: Int = 0

    // MARK: - Constants

    /// Anon key (publishable) — same one used elsewhere. Read-only RLS
    /// on `app_version_config` lets unauthenticated reads work.
    private let supabaseURL = URL(string: "https://zziauybwemoiqfpidiur.supabase.co")!
    private let anonKey = "sb_publishable_PhYldjkyyE4DhJQJVjeM4Q_u02pyXVH"

    private let cacheDefaultsKey = "sbt.versionGate.cachedConfig.v1"

    // MARK: - Init

    private init() {
        // Restore cached config synchronously so a re-launch with an
        // active force-block cannot momentarily flash the unblocked UI
        // while the network call is in flight.
        if let cached = loadCachedConfig() {
            self.lastConfig = cached
            self.gateState = decideState(for: cached)
        }
    }

    // MARK: - Public API

    /// Fetch the latest config and update `gateState`. Safe to call
    /// repeatedly (launch, resume, manual refresh).
    func refresh() async {
        do {
            let fresh = try await fetchRemoteConfig()
            self.lastConfig = fresh
            self.gateState = decideState(for: fresh)
            saveCachedConfig(fresh)
        } catch {
            // Network/server failure path. Honor the safe-fallback rule:
            // - If a cached config existed, KEEP its decision.
            // - Otherwise treat as .allowed so the user is never locked
            //   out on first launch with no internet.
            if lastConfig == nil {
                self.gateState = .allowed
            }
            // else: leave gateState as-is from cache
        }
    }

    /// Mark the current optional update prompt as dismissed. Only valid
    /// when state is `.optionalUpdate(_)`.
    func dismissOptionalUpdate() {
        if case .optionalUpdate(let latestBuild) = gateState {
            dismissedLatestBuild = latestBuild
            gateState = .allowed
        }
    }

    // MARK: - Decision logic

    /// Pure, testable mapping from a config + the current build to a
    /// gate state.
    private func decideState(for config: AppVersionConfig) -> GateState {
        let currentBuild = Self.currentBuildNumber

        // Master kill-switch — if force update is disabled server-side,
        // never hard-block. Optional prompt is still allowed.
        if config.isForceUpdateEnabled,
           currentBuild < config.minimumSupportedBuild {
            let url = URL(string: config.appStoreURL)
                ?? URL(string: "https://apps.apple.com/app/id6762890363")!
            return .blocked(message: config.updateRequiredMessage, appStoreURL: url)
        }

        if currentBuild < config.latestBuild,
           dismissedLatestBuild != config.latestBuild {
            return .optionalUpdate(latestBuild: config.latestBuild)
        }

        return .allowed
    }

    // MARK: - Bundle helpers

    /// Reads CFBundleVersion as Int. CFBundleVersion is a numeric
    /// monotonic build number in this project (17, 18, ...). If parsing
    /// ever fails (unlikely), fall through to Int.max so the app is
    /// NEVER blocked by a corrupt local read.
    static var currentBuildNumber: Int {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Int(raw ?? "") ?? Int.max
    }

    // MARK: - Networking

    private func fetchRemoteConfig() async throws -> AppVersionConfig {
        var components = URLComponents(
            url: supabaseURL.appendingPathComponent("rest/v1/app_version_config"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(name: "limit", value: "1")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([AppVersionConfig].self, from: data)
        guard let first = rows.first else {
            throw URLError(.zeroByteResource)
        }
        return first
    }

    // MARK: - Cache (UserDefaults)

    private func loadCachedConfig() -> AppVersionConfig? {
        guard let data = UserDefaults.standard.data(forKey: cacheDefaultsKey) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AppVersionConfig.self, from: data)
    }

    private func saveCachedConfig(_ config: AppVersionConfig) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(config) {
            UserDefaults.standard.set(data, forKey: cacheDefaultsKey)
        }
    }
}
