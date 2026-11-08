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
		var all = load()
		let key = storageKey(nodeNum)
		if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
			all[key] = name
		} else {
			all.removeValue(forKey: key)
		}
		save(all)
		NotificationCenter.default.post(name: didChangeNotification, object: nodeNum)
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

	private static func save(_ dict: [String: String]) {
		guard let data = try? JSONEncoder().encode(dict) else { return }
		UserDefaults.standard.set(data, forKey: key)
		lock.lock()
		cache = dict
		lock.unlock()
	}
}
