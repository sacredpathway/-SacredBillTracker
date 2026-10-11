//
//  SupabaseConfig.swift
//  SacredBillTracker
//
//  Single source of truth for Supabase endpoint + anon key.
//
//  To activate Supabase sync:
//    1. Paste your Project URL and anon key below.
//    2. In SacredBillTrackerApp, swap:
//         LocalBillRepository()
//       for:
//         CachingBillRepository(
//             local:  LocalBillRepository(),
//             remote: SupabaseBillRepository(client: SupabaseConfig.client)
//         )
//
//  The key below is the `anon` (public) key — safe to embed in a shipped
//  iOS binary as long as RLS is enabled on every table (which it is for
//  `bills`). The anon key alone cannot read another user's rows.
//

import Foundation

#if canImport(Supabase)
import Supabase

enum SupabaseConfig {

    // MARK: - Fill these in after creating your Supabase project

    /// e.g. "https://abcdefghijklmnop.supabase.co"
    #if SBT_STAGING_ACCEPTANCE
    static let url = SBTStagingRoute.required.url
    #elseif SBT_ISOLATED_VALIDATION
    static let url = URL(string: "https://sbt-native-validation.invalid")!
    #else
    static let url = URL(string: "https://zziauybwemoiqfpidiur.supabase.co")!
    #endif

    /// Supabase **publishable** key (new format, starts with `sb_publishable_`).
    /// This is the client-safe key — safe to embed because RLS on every
    /// table prevents unauthorized access. If the SDK ever rejects this
    /// format, swap in the legacy anon JWT from the same screen.
    #if SBT_STAGING_ACCEPTANCE
    static let anonKey = SBTStagingRoute.required.key
    #else
    static let anonKey = "sb_publishable_PhYldjkyyE4DhJQJVjeM4Q_u02pyXVH"
    #endif
    static var networkSession: URLSession {
        #if SBT_STAGING_ACCEPTANCE
        return SBTStagingRoute.session
        #else
        return .shared
        #endif
    }

    // MARK: - Shared client

    /// A lazily-built, process-wide Supabase client. All repositories and
    /// the AuthService share this so sessions stay in sync.
    static let client: SupabaseClient = {
        #if SBT_STAGING_ACCEPTANCE
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey,
            options: .init(auth: .init(storageKey: "sbt.staging.acceptance.auth"),
                           global: .init(session: networkSession)))
        #else
        return SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
        #endif
    }()
}
#endif


#if SBT_STAGING_ACCEPTANCE && !DEBUG
#error("Staging acceptance is Debug-only; never archive or release it")
#endif

/// Pure validation shared by the development-only route and configuration tests.
enum SBTStagingRoute {
    static var cacheService: String {
        #if SBT_STAGING_ACCEPTANCE
        return "com.sacredbilltracker.entitlement.staging.v1"
        #else
        return "com.sacredbilltracker.entitlement.production.v1"
        #endif
    }
    static let project = "thwjnpofhrpxfuvwkfgd"
    static let host = project + ".supabase.co"
    struct Configuration { let url: URL; let key: String }
    enum Invalid: Error { case configuration }
    static func resolve(_ environment: [String: String]) throws -> Configuration {
        guard environment["SBT_STAGING_PROJECT"] == project,
              let raw = environment["SBT_STAGING_URL"], let url = URL(string: raw),
              raw == "https://" + host,
              let key = environment["SBT_STAGING_PUBLIC_KEY"],
              let claims = publicKeyClaims(key),
              claims["ref"] as? String == project,
              claims["role"] as? String == "anon" else { throw Invalid.configuration }
        // JWT metadata restricts target/privilege; the server validates signature.
        return Configuration(url: url, key: key)
    }
    static func publicKeyClaims(_ key: String) -> [String: Any]? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func permits(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == host && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
    }
    #if SBT_STAGING_ACCEPTANCE
    static let required: Configuration = {
        do { return try resolve(ProcessInfo.processInfo.environment) }
        catch { fatalError("STAGING configuration failed: expected isolated project and matching public key; no fallback") }
    }()
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SBTStagingRejectProtocol.self]
        return URLSession(configuration: configuration, delegate: SBTStagingRedirectGuard(), delegateQueue: nil)
    }()
    #endif
}
#if SBT_STAGING_ACCEPTANCE
private final class SBTStagingRejectProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { !SBTStagingRoute.permits(request.url) }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    override func stopLoading() {}
}
private final class SBTStagingRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(SBTStagingRoute.permits(request.url) ? request : nil)
    }
}
#endif
