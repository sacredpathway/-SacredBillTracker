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

    // Debounce state for coalescing realtime bursts (see start()).
    private var pendingRefresh: Task<Void, Never>?
    private var lastRefresh = Date.distantPast
    private let refreshQuietWindow: UInt64 = 1_000_000_000  // 1.0s after last event
    private let refreshMaxStaleness: TimeInterval = 5.0     // force a refresh at least this often

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

        // Coalesce bursts of change events into a single refresh.
        //
        // `BillStore.persist()` upserts the user's FULL bill snapshot on
        // every edit, and Supabase Realtime emits ONE event per changed
        // row — so a single "mark paid" could fire dozens of events, each
        // previously triggering a full `refreshFromRemote()` + GET /bills
        // (the observed flood). We debounce: restart a short timer on each
        // event and only refresh once the burst goes quiet. A max-staleness
        // guard still forces a refresh during sustained activity so sync
        // correctness is preserved.
        lastRefresh = .distantPast
        changeTask = Task { [weak self, onChange] in
            for await _ in stream {
                guard let self else { break }
                self.scheduleCoalescedRefresh(onChange)
            }
        }
    }

    /// Trailing-edge debounce with a leading-edge fast path after a quiet
    /// period. All state is MainActor-isolated, so there are no data races.
    private func scheduleCoalescedRefresh(_ onChange: @MainActor @escaping () async -> Void) {
        let now = Date()
        if now.timeIntervalSince(lastRefresh) >= refreshMaxStaleness {
            // Been quiet for a while — refresh immediately (leading edge).
            pendingRefresh?.cancel()
            pendingRefresh = nil
            lastRefresh = now
            Task { await onChange() }
        } else {
            // Inside an active burst — collapse to one trailing refresh.
            pendingRefresh?.cancel()
            pendingRefresh = Task { [weak self, onChange] in
                try? await Task.sleep(nanoseconds: self?.refreshQuietWindow ?? 1_000_000_000)
                if Task.isCancelled { return }
                self?.lastRefresh = Date()
                await onChange()
            }
        }
    }

    /// Tear down the channel and cancel the consumer task.
    func stop() async {
        changeTask?.cancel()
        changeTask = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil

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
