//
//  AccessoryManager+AppData.swift
//  Meshtastic
//
//  Copyright(c) Meshtastic 2026.
//

import Foundation

// MARK: - Clear App Data

extension AccessoryManager {

	/// Erases the app's data, as Clear App Data does on `main`: the store (favorites and saved
	/// routes included), every saved backup, the translation caches and the notifications, then
	/// reloads the bundled device catalog. App settings are kept; Reset App Settings is separate.
	/// With the store gone, no radio is known any more: no service keeps one (W-15), and the
	/// radios' windows close (review V27-4).
	///
	/// The caller disconnects first. Clear App Data disconnects every radio; Remove Radio, when it
	/// removes the only radio, has taken that one offline (T390). Returns false when the store
	/// stopped clearing part-way (`MeshPackets.clearDatabase`).
	@discardableResult
	func eraseAppData() async -> Bool {
		await TranslationCache.shared.clearAll()
		await DocTranslationService.shared.clearUIStringCache()
		for entry in NodeBackupManager.shared.listBackups() {
			_ = NodeBackupManager.shared.deleteBackup(forKey: entry.key)
		}
		await MeshPackets.shared.flushDebouncedSaves()
		let cleared = await MeshPackets.shared.clearDatabase(includeRoutes: true)
		await resetDatabaseAfterClear()
		for service in RadioService.allCases {
			UserDefaults.setServiceRadio(0, for: service)
		}
		await forgetRadiosNotInStore()
		clearNotifications()
		// Repopulate device catalog immediately — no reconnect happens after a full reset.
		try? await MeshtasticAPI.shared.refreshBundledDevicesData()
		// Images and msh.to links are network-backed, so they run in their own task rather than
		// blocking the reset from completing. `Task` rather than `Task.detached` per the repo
		// concurrency guideline; the pass handles its own cancellation.
		Task(priority: .utility) {
			await MeshtasticAPI.shared.refreshDevicesPreferringAPI()
		}
		return cleared
	}
}
