//
//  PaymentURLValidator.swift
//  SacredBillTracker
//
//  Pure helper that takes whatever the user typed in the Payment Link
//  field and decides what to do with it.
//
//  Behavior:
//    • Trims whitespace.
//    • Empty input → nil (the field is optional).
//    • If input already starts with http:// or https:// AND parses as a
//      URL with a host → accept as-is.
//    • If input is missing a scheme but looks like a URL (has a dot in
//      a host-like prefix) → return `.needsHttpsPrefix(normalized)` so
//      the caller can offer to add `https://`.
//    • Anything else → `.invalid`.
//
//  The app NEVER auto-pays. The validated/normalized URL is just handed
//  to `UIApplication.shared.open(_:)` so the user lands on their biller
//  in Safari.
//

import Foundation

enum PaymentURLValidation: Equatable {
    /// Input was empty/whitespace — store nothing.
    case empty
    /// Input was parseable. `url` is the canonical string to persist
    /// (trimmed, with `https://` prepended if the user omitted a
    /// scheme). The Supabase CHECK constraint enforces http(s) only,
    /// so this is what gets written to the wire.
    case valid(url: String)
    /// Input doesn't look like a URL at all.
    case invalid
}

enum PaymentURLValidator {

    /// One pass of validation + normalization. See `PaymentURLValidation`.
    ///
    /// Behavior:
    ///   • Empty / whitespace → `.empty`
    ///   • `http://...` or `https://...` with a host → `.valid` as-is
    ///   • `www.example.com` or `example.com/pay` (no scheme but looks
    ///     like a host) → `.valid("https://" + input)`
    ///   • Anything else → `.invalid`
    ///
    /// We deliberately do NOT pass through other schemes (mailto:, app:,
    /// custom bill-pay apps). The Supabase CHECK constraint only allows
    /// `^https?://`, and the App Store guideline this feature is built
    /// against is "open external website only" — so we keep the
    /// validator strict.
    static func validate(_ raw: String) -> PaymentURLValidation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let lower = trimmed.lowercased()

        // Already has http(s) scheme — must parse with a non-empty host.
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            if let url = URL(string: trimmed),
               let host = url.host, !host.isEmpty {
                return .valid(url: trimmed)
            }
            return .invalid
        }

        // Reject any OTHER scheme up front (mailto:, file:, ftp:, javascript:, …)
        if let colonIdx = lower.firstIndex(of: ":"),
           // looks like "scheme:" before any slash
           lower[..<colonIdx].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) {
            return .invalid
        }

        // No scheme — does it look like a host? (contains a dot, no
        // whitespace, and every dot-separated piece is non-empty.)
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let hasNoWhitespace = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
        let looksLikeHost = trimmed.contains(".")
            && hasNoWhitespace
            && pieces.count >= 2
            && pieces.allSatisfy { !$0.isEmpty }

        if looksLikeHost {
            let normalized = "https://" + trimmed
            if let url = URL(string: normalized),
               let host = url.host, !host.isEmpty {
                return .valid(url: normalized)
            }
        }

        return .invalid
    }

    /// Convenience for places that just want a URL or nil — used by
    /// detail / row / calendar views that open the link in Safari.
    static func openableURL(from stored: String?) -> URL? {
        guard let stored, !stored.isEmpty else { return nil }
        switch validate(stored) {
        case .valid(let s):
            return URL(string: s)
        case .empty, .invalid:
            return nil
        }
    }
}

// MARK: - DEBUG self-check
//
// Runs in DEBUG builds on first reference to the validator (lazy var) so a
// regression in the rules surfaces in the Xcode console immediately —
// without needing a test target wired into the project file. Production
// (Release) builds compile this out entirely.

#if DEBUG
private let _paymentURLValidatorSelfCheck: Void = {
    typealias V = PaymentURLValidation
    let cases: [(String, V)] = [
        ("",                                              .empty),
        ("   ",                                           .empty),
        ("https://chase.com/pay",                         .valid(url: "https://chase.com/pay")),
        ("http://example.com",                            .valid(url: "http://example.com")),
        ("  https://example.com  ",                       .valid(url: "https://example.com")),
        ("www.example.com",                               .valid(url: "https://www.example.com")),
        ("example.com/pay/123",                           .valid(url: "https://example.com/pay/123")),
        ("sub.dom.example.co.uk",                         .valid(url: "https://sub.dom.example.co.uk")),
        ("not a url at all",                              .invalid),
        ("mailto:foo@bar.com",                            .invalid),
        ("ftp://example.com",                             .invalid),
        ("javascript:alert(1)",                           .invalid),
        ("file:///etc/passwd",                            .invalid),
        ("...",                                           .invalid),
    ]
    var failed = 0
    for (input, expected) in cases {
        let actual = PaymentURLValidator.validate(input)
        if actual != expected {
            print("⚠️ PaymentURLValidator FAIL — input=\(input.debugDescription) expected=\(expected) actual=\(actual)")
            failed += 1
        }
    }
    if failed == 0 {
        print("✅ PaymentURLValidator self-check passed (\(cases.count) cases)")
    } else {
        print("❌ PaymentURLValidator self-check: \(failed)/\(cases.count) failed")
    }
}()

/// Call once on app launch to trigger the self-check. No-op in Release.
func _runPaymentURLValidatorSelfCheck() { _ = _paymentURLValidatorSelfCheck }
#else
func _runPaymentURLValidatorSelfCheck() {}
#endif

// MARK: - String helper used by Bill decoder

extension String {
    /// Returns nil when self is empty after trimming whitespace. Handy
    /// when decoding optional URL strings that may have round-tripped
    /// through DBs as `""` instead of NULL.
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
