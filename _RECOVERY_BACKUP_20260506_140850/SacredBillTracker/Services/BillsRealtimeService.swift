//
//  BillsRealtimeService.swift
//  SacredBillTracker
//
//  Subscribes to Supabase Realtime changes on `public.bills` so edits
//  made on another device (or the dashboard) appear on this device
//  within ~1 second, without waiting for the next app launch.
//
//  Wiring:
//    SacredBillTrackerApp ties the subscription lifecycle to the user's
//    auth state — subscribe on sign-in, unsubscribe on sign-out.
//
//  Requires: supabase-swift 2.43.x (Realtime is included in the umbrella).
//

import Foundation

#if canImport(Supabase)
import Supabase
import Realtime

/// Owns a single Supabase Realtime channel for the `bills` table.
/// Sends raw changes to a callback; the store decides how to apply them.
@MainActor
final class BillsRealtimeService {

    private var channel: RealtimeChannelV2?
    private var changeTask: Task<Void, Never>?

    /// Start listening for INSERT / UPDATE / DELETE on `public.bills`
    /// for the given user. Safe to call repeatedly — disconnects any
    /// prior subscription first.
    func start(
        userID: UUID,
        onChange: @MainActor @escaping () async -> Void
    ) async {
        await stop()

        let client = SupabaseConfig.client
        let channelName = "bills-\(userID.uuidString)"
        let channel = client.realtimeV2.channel(channelName)
        self.channel = channel

        // One stream covers INSERT + UPDATE + DELETE. RLS on the Postgres
        // side already scopes what we can hear to our own rows, so no
        // client-side filter is strictly required — but we add one for
        // efficiency on the wire.
        let stream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "bills",
            filter: "user_id=eq.\(userID.uuidString)"
        )

        await channel.subscribe()

        changeTask = Task { [onChange] in
            for await _ in stream {
                await onChange()
            }
        }
    }

    /// Tear down the channel and cancel the consumer task.
    func stop() async {
        changeTask?.cancel()
        changeTask = nil

        if let channel {
            await channel.unsubscribe()
            self.channel = nil
        }
    }
}

#else

// ---------- Fallback when supabase-swift isn't linked ----------

@MainActor
final class BillsRealtimeService {
    func start(userID: UUID, onChange: @MainActor @escaping () async -> Void) async {}
    func stop() async {}
}

#endif
