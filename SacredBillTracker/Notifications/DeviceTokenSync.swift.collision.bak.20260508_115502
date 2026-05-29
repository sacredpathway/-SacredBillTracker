//
//  DeviceTokenSync.swift
//  Sacred Pathway Driver Hub — P5
//
//  Pure URLSession implementation (no project-specific SupabaseClient dependency).
//  Reads SUPABASE_URL + SUPABASE_ANON_KEY from Info.plist; falls back to no-op if missing.
//

import Foundation
import UIKit

@MainActor
final class DeviceTokenSync {

    static let shared = DeviceTokenSync()

    private let cacheKey  = "sph.push.lastUploadedToken.v1"
    private let userIdKey = "sph.push.userId.v1"

    private init() {}

    func register(tokenHex: String) async {
        let cached = UserDefaults.standard.string(forKey: cacheKey)
        if cached == tokenHex { return }

        do {
            try await upsert(tokenHex: tokenHex)
            UserDefaults.standard.set(tokenHex, forKey: cacheKey)
            #if DEBUG
            print("[push] device token uploaded")
            #endif
        } catch {
            #if DEBUG
            print("[push] device token upload failed: \(error.localizedDescription)")
            #endif
        }
    }

    func clearCache() { UserDefaults.standard.removeObject(forKey: cacheKey) }

    func deactivate() async {
        let deviceId = installationId()
        guard let (url, key) = supabaseConfig() else { return }
        var req = URLRequest(url: url
            .appendingPathComponent("rest/v1/device_tokens")
            .appendingQueryItem(name: "device_id", value: "eq.\(deviceId)"))
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(currentBearerToken() ?? key)", forHTTPHeaderField: "Authorization")
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONEncoder().encode([
            "active": AnyCodable(false),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ])
        _ = try? await URLSession.shared.data(for: req)
        clearCache()
    }

    // MARK: - Private

    private func upsert(tokenHex: String) async throws {
        guard let (url, key) = supabaseConfig() else {
            throw NSError(domain: "DeviceTokenSync", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Supabase config missing in Info.plist"])
        }
        let payload: [String: AnyCodable] = [
            "user_id":     AnyCodable(currentUserId()),
            "device_id":   AnyCodable(installationId()),
            "apns_token":  AnyCodable(tokenHex),
            "platform":    AnyCodable("ios"),
            "app_version": AnyCodable(appVersion()),
            "os_version":  AnyCodable(UIDevice.current.systemVersion),
            "active":      AnyCodable(true)
        ]

        var req = URLRequest(url: url.appendingPathComponent("rest/v1/device_tokens"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(currentBearerToken() ?? key)", forHTTPHeaderField: "Authorization")
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Upsert keyed on device_id (unique) — see 20_supabase_device_tokens_schema.sql
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode(payload)

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw NSError(domain: "DeviceTokenSync", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private func supabaseConfig() -> (URL, String)? {
        guard
            let urlStr = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String)
                       ?? ProcessInfo.processInfo.environment["SUPABASE_URL"],
            let key    = (Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String)
                       ?? ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
            let url    = URL(string: urlStr)
        else { return nil }
        return (url, key)
    }

    /// If your auth layer stores a bearer JWT in UserDefaults / Keychain under a known key,
    /// override this. Falls back to anon key when nil.
    private func currentBearerToken() -> String? {
        UserDefaults.standard.string(forKey: "sph.auth.accessToken")
    }

    private func installationId() -> String {
        let key = "sph.installation.id.v1"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }

    private func currentUserId() -> String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    private func appVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

// MARK: - Type-erased Codable helper for heterogeneous payloads

private struct AnyCodable: Codable {
    let value: Any
    init(_ value: Any?) { self.value = value ?? () }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is Void: try c.encodeNil()
        case let v as String: try c.encode(v)
        case let v as Bool:   try c.encode(v)
        case let v as Int:    try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String?: if let v = v { try c.encode(v) } else { try c.encodeNil() }
        default: try c.encodeNil()
        }
    }
    init(from decoder: Decoder) throws { value = () }
}

private extension URL {
    func appendingQueryItem(name: String, value: String) -> URL {
        guard var comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        comps.queryItems = items
        return comps.url ?? self
    }
}
