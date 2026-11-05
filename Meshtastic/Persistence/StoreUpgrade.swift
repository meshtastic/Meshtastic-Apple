//
//  StoreUpgrade.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/5/26.
//

import Foundation
import OSLog
import SwiftData

/// The one-time work that brings older data into the store: the Core Data migration and the
/// recovery of the store the app group move left behind.
///
/// Both used to run inside `PersistenceController.init`, on the main thread before the first
/// screen. A large store took longer than the 20 seconds iOS allows an app to launch, iOS killed
/// the app, and the work started over on the next launch and never finished (#2891). They now run
/// off the main thread once the app is up. Until they finish, the app shows the database-reset
/// placeholder, so no view holds the store, and `AccessoryManager.connect` waits.
@MainActor
enum StoreUpgrade {

	private static var task: Task<Void, Never>?

	/// Whether there is anything to do. Cheap: file checks only.
	static func isNeeded(liveStoreURL: URL) -> Bool {
		CoreDataMigrationService.legacyStoreExists() || LegacyStoreRecovery.isPending(liveStoreURL: liveStoreURL)
	}

	/// Starts the upgrade if there is one. Call before the first frame so the placeholder is up
	/// from the start.
	static func startIfNeeded(persistence: PersistenceController, appState: AppState) {
		guard task == nil,
			  !persistence.inMemory,
			  !persistence.isUsingVolatileStore,
			  !persistence.isProvisionalPendingFirstUnlock,
			  isNeeded(liveStoreURL: PersistenceController.storeURL) else { return }
		let container = persistence.container
		appState.isUpgradingStore = true
		appState.isDatabaseResetting = true
		task = Task {
			Logger.data.info("💾 Store upgrade started")
			if CoreDataMigrationService.legacyStoreExists() {
				do {
					try await Task.detached(priority: .userInitiated) {
						try CoreDataMigrationService.migrate(into: container)
					}.value
				} catch {
					// The SwiftData store is usable even if the migration fails.
					Logger.data.error("⬆️ CoreDataMigrationService failed: \(error.localizedDescription, privacy: .public)")
				}
			}
			await LegacyStoreRecovery.recoverIfNeeded(into: container, liveStoreURL: PersistenceController.storeURL)
			appState.databaseResetID = UUID()
			appState.isDatabaseResetting = false
			appState.isUpgradingStore = false
			Logger.data.info("💾 Store upgrade finished")
		}
	}

	/// Returns once the upgrade, if one is running, has finished.
	static func waitUntilFinished() async {
		await task?.value
	}
}
