//
//  NodeDisplayNameStore.swift
//  Meshtastic
//
//  Local display names for nodes (keyed by node num). Used only for UI; device identity unchanged.
//

import Foundation

enum NodeDisplayNameStore {
	private static let key = "nodeDisplayNames"

	/// Posted when a display name is set or cleared, `object` = the node's `num` (`Int64`) so
	/// observers can scope their refresh to the node they're showing — mirrors `.nodeLogAvailabilityDidChange`.
	/// `NSNotification.Name`, not `Notification.Name` — this app declares its own top-level
	/// `Notification` struct (LocalNotificationManager.swift) that shadows Foundation's.
	static let didChangeNotification = NSNotification.Name("NodeDisplayNameStoreDidChange")

	/// Decoded names, kept in memory so lists, searches and sorts don't decode the JSON once per
	/// node. Only `setDisplayName` writes the key, so it refreshes this as it saves.
	private static let lock = NSLock()
	nonisolated(unsafe) private static var cache: [String: String]?
	nonisolated(unsafe) private static var storedRevision = 0

	/// Returns the local display name for a node, or nil if none is set.
	static func displayName(for nodeNum: Int64) -> String? {
		let all = load()
		return all[storageKey(nodeNum)]
	}

	/// Whether any node has a display name, so lists can skip re-sorting when none do.
	static var hasDisplayNames: Bool {
		!load().isEmpty
	}

	/// Sets the local display name for a node. Pass nil to clear.
	static func setDisplayName(_ name: String?, for nodeNum: Int64) {
		// One lock across read, change and save, so two writers can't drop each other's change.
		lock.lock()
		var all = cache ?? decode()
		let key = storageKey(nodeNum)
		if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
			all[key] = name
		} else {
			all.removeValue(forKey: key)
		}
		if let data = try? JSONEncoder().encode(all) {
			UserDefaults.standard.set(data, forKey: self.key)
		}
		cache = all
		storedRevision &+= 1
		lock.unlock()
		NotificationCenter.default.post(name: didChangeNotification, object: nodeNum)
	}

	/// Changes whenever any display name is set or cleared, so cached drawings that name nodes
	/// can tell they need redrawing.
	static var revision: Int {
		lock.lock()
		defer { lock.unlock() }
		return storedRevision
	}

	private static func storageKey(_ nodeNum: Int64) -> String {
		String(nodeNum)
	}

	private static func load() -> [String: String] {
		lock.lock()
		defer { lock.unlock() }
		if let cache { return cache }
		let decoded = decode()
		cache = decoded
		return decoded
	}

	private static func decode() -> [String: String] {
		guard let data = UserDefaults.standard.data(forKey: key),
		      let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
			return [:]
		}
		return decoded
	}
}
