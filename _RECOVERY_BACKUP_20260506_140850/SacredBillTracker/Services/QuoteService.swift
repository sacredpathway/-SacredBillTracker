//
//  QuoteService.swift
//  SacredBillTracker
//
//  Hybrid "always has a quote" service for the Dashboard:
//
//    1. Boot: surface either the last cached API quote or — if none —
//       the day-of-year line from `DailyQuotes` so the UI renders
//       INSTANTLY with no spinner / blank state.
//    2. Background: try the public Quotable API.
//    3. If Quotable fails (network, dead host, malformed JSON), fall
//       back to the public ZenQuotes API.
//    4. If both APIs fail, keep whatever we already showed (no flicker
//       to local fallback) — user perceives the quote source as
//       "always working".
//
//  Both APIs are free / no-auth / HTTPS so no Info.plist changes or
//  paid SDKs are needed. Errors are swallowed so a bad network never
//  surfaces a crash or broken UI on the Dashboard.
//

import Foundation

// MARK: - Model

struct MotivationalQuote: Codable, Hashable {
    let text: String
    let author: String
}

// MARK: - Service

@MainActor
final class QuoteService: ObservableObject {

    static let shared = QuoteService()

    /// What the Dashboard observes. Always non-nil so the banner is
    /// never blank.
    @Published private(set) var quote: MotivationalQuote

    // MARK: - Storage

    private let cacheKey = "sbt.quote.cached.v1"
    private let session: URLSession

    private init(session: URLSession = .shared) {
        self.session = session
        self.quote = QuoteService.boot()
    }

    /// Quote shown immediately on launch — cached API result if we have
    /// one, otherwise today's deterministic line from `DailyQuotes`.
    private static func boot() -> MotivationalQuote {
        if let cached = loadCached() { return cached }
        return MotivationalQuote(
            text: DailyQuotes.today(),
            author: "" // local fallback has no author by design.
        )
    }

    // MARK: - Public API

    /// Fire-and-forget background refresh. Safe to call on every cold
    /// launch; failures are silent.
    func refreshInBackground() {
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            if let q = await self.fetchQuotable() {
                await self.update(q)
                return
            }
            if let q = await self.fetchZenQuotes() {
                await self.update(q)
                return
            }
            // Both APIs unreachable. Keep whatever the user is already
            // looking at — no flicker to local random pool, no spinner.
        }
    }

    // MARK: - Update + cache

    private func update(_ q: MotivationalQuote) {
        guard isClean(q) else { return }
        self.quote = q
        if let data = try? JSONEncoder().encode(q) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCached() -> MotivationalQuote? {
        guard let data = UserDefaults.standard.data(forKey: "sbt.quote.cached.v1") else { return nil }
        return try? JSONDecoder().decode(MotivationalQuote.self, from: data)
    }

    /// Trim, length-cap, and reject anything with profanity-ish tokens
    /// so we never show a broken or off-brand line on the home screen.
    private func isClean(_ q: MotivationalQuote) -> Bool {
        let text = q.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        guard text.count <= 240 else { return false }

        let banned: [String] = [
            "fuck", "shit", "asshole", "bitch", "cunt", "dick",
            "nazi", "rape", "kill yourself", "suicide"
        ]
        let lower = text.lowercased()
        for w in banned where lower.contains(w) { return false }
        return true
    }

    // MARK: - Network

    /// Quotable mapping: `content` → text, `author` → author.
    private func fetchQuotable() async -> MotivationalQuote? {
        guard let url = URL(string:
            "https://api.quotable.io/random?tags=motivational|inspirational|wisdom|business")
        else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: req)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return nil }

            struct Resp: Decodable { let content: String; let author: String }
            let r = try JSONDecoder().decode(Resp.self, from: data)
            return MotivationalQuote(
                text: r.content.trimmingCharacters(in: .whitespacesAndNewlines),
                author: r.author.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            return nil
        }
    }

    /// ZenQuotes mapping: `q` → text, `a` → author. Endpoint returns an
    /// array; we take the first item.
    private func fetchZenQuotes() async -> MotivationalQuote? {
        guard let url = URL(string: "https://zenquotes.io/api/random")
        else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: req)
            guard
                let http = response as? HTTPURLResponse,
                (200..<300).contains(http.statusCode)
            else { return nil }

            struct Item: Decodable { let q: String; let a: String }
            let arr = try JSONDecoder().decode([Item].self, from: data)
            guard let r = arr.first else { return nil }
            return MotivationalQuote(
                text: r.q.trimmingCharacters(in: .whitespacesAndNewlines),
                author: r.a.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            return nil
        }
    }
}
