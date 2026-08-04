// RadioStorePaths.swift
// Meshtastic

import Foundation

struct RadioStorePaths: Equatable {
	let legacyStoreURL: URL
	let registryStoreURL: URL
	let radioStoreDirectory: URL

	init(applicationSupportDirectory: URL) {
		legacyStoreURL = applicationSupportDirectory.appendingPathComponent("Meshtastic.store")
		registryStoreURL = applicationSupportDirectory.appendingPathComponent("RadioRegistry.store")
		radioStoreDirectory = applicationSupportDirectory.appendingPathComponent(
			"RadioStores",
			isDirectory: true
		)
	}

	func radioStoreURL(for storeKey: UUID) -> URL {
		radioStoreDirectory
			.appendingPathComponent(storeKey.uuidString.lowercased())
			.appendingPathExtension("store")
	}

	static func production() throws -> RadioStorePaths {
		let directory = try FileManager.default.url(
			for: .applicationSupportDirectory,
			in: .userDomainMask,
			appropriateFor: nil,
			create: true
		)
		return RadioStorePaths(applicationSupportDirectory: directory)
	}
}
