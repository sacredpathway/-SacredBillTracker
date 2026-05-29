//
//  CloudBackedDefaults.swift
//  SacredBillTracker
//
//  Thin wrapper that mirrors small Data blobs to BOTH UserDefaults and
//  NSUbiquitousKeyValueStore (iCloud key-value store).
//
//  WHY: UserDefaults lives inside the app sandbox — when the user deletes
//  and reinstalls the app, every UserDefaults key is wiped. iCloud KV
//  store persists across reinstalls and syncs to the same Apple ID on
//  other devices. By dual-writing we get:
//    • survival across app delete/reinstall (the original bug)
//    • cross-device sync for free
//    • offline-first read (UserDefaults is the local cache)
//
//  LIMITS (Apple): 1 MB total, 1024 keys, 1 MB per value. Income/load
//  blobs are well under that.
//
//  Requires entitlement: com.apple.developer.ubiquity-kvstore-identifier
//

import Foundation

final class CloudBackedDefaults {

    static let shared = CloudBackedDefaults()

    private let defaults: UserDefaults
    private let cloud: NSUbiquitousKeyValueStore

    private init(defaults: UserDefaults = .standard,
                 cloud: NSUbiquitousKeyValueStore = .default) {
        self.defaults = defaults
        self.cloud = cloud
        // Pull whatever the cloud already has on launch (covers reinstall).
        self.cloud.synchronize()
        // Listen for changes pushed from other devices / restored from iCloud.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(cloudDidChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: self.cloud
        )
    }

    // MARK: - Read

    /// Returns iCloud value if present, otherwise local. Hydrates local
    /// cache from iCloud on first hit so subsequent reads are fast.
    func data(forKey key: String) -> Data? {
        if let cloudData = cloud.data(forKey: key) {
            // Hydrate local cache so offline reads see the same bytes.
            if defaults.data(forKey: key) != cloudData {
                defaults.set(cloudData, forKey: key)
            }
            return cloudData
        }
        return defaults.data(forKey: key)
    }

    // MARK: - Write

    /// Writes to BOTH stores. Local first (synchronous, never fails);
    /// cloud second (best-effort, syncs in background).
    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
        cloud.set(data, forKey: key)
        cloud.synchronize()
    }

    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
        cloud.removeObject(forKey: key)
        cloud.synchronize()
    }

    // MARK: - External changes

    /// Posted to NotificationCenter whenever iCloud pushes new values in.
    /// Views/stores can observe this to reload from disk.
    static let storeDidUpdateLocally = Notification.Name(
        "CloudBackedDefaults.storeDidUpdateLocally"
    )

    @objc private func cloudDidChange(_ note: Notification) {
        guard
            let userInfo = note.userInfo,
            let keys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
        else { return }

        // Mirror every changed key down into UserDefaults so a subsequent
        // synchronous read returns the latest bytes.
        for key in keys {
            if let data = cloud.data(forKey: key) {
                defaults.set(data, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        NotificationCenter.default.post(
            name: CloudBackedDefaults.storeDidUpdateLocally,
            object: nil,
            userInfo: ["keys": keys]
        )
    }
}
