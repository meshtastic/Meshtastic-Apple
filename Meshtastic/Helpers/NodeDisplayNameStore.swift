//
//  NodeDisplayNameStore.swift
//  Meshtastic
//
//  Local display names for nodes (keyed by node num). Used only for UI; device identity unchanged.
//

import Foundation

enum NodeDisplayNameStore {
	private static let key = "nodeDisplayNames"

	/// Posted when any display name is set or cleared so UI can refresh.
	static let didChangeNotification = Notification.Name("NodeDisplayNameStoreDidChange")

	/// Returns the local display name for a node, or nil if none is set.
	static func displayName(for nodeNum: Int64) -> String? {
		let all = load()
		return all[storageKey(nodeNum)]
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
		NotificationCenter.default.post(name: didChangeNotification, object: nil)
	}

	private static func storageKey(_ nodeNum: Int64) -> String {
		String(nodeNum)
	}

	private static func load() -> [String: String] {
		guard let data = UserDefaults.standard.data(forKey: key),
		      let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
			return [:]
		}
		return decoded
	}

	private static func save(_ dict: [String: String]) {
		guard let data = try? JSONEncoder().encode(dict) else { return }
		UserDefaults.standard.set(data, forKey: key)
	}
}
