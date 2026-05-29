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
    static let url = URL(string: "https://zziauybwemoiqfpidiur.supabase.co")!

    /// Supabase **publishable** key (new format, starts with `sb_publishable_`).
    /// This is the client-safe key — safe to embed because RLS on every
    /// table prevents unauthorized access. If the SDK ever rejects this
    /// format, swap in the legacy anon JWT from the same screen.
    static let anonKey = "sb_publishable_PhYldjkyyE4DhJQJVjeM4Q_u02pyXVH"

    // MARK: - Shared client

    /// A lazily-built, process-wide Supabase client. All repositories and
    /// the AuthService share this so sessions stay in sync.
    static let client: SupabaseClient = {
        SupabaseClient(supabaseURL: url, supabaseKey: anonKey)
    }()
}
#endif
