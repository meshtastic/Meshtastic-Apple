//
//  WidgetSnapshotStore.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/16/26.
//
//  Reads and writes the widget snapshot in the shared app group container.
//  File protection is class C (complete until first user authentication) so
//  CarPlay and StandBy widgets can still read it while the phone is locked
//  in the car. That is a deliberate tradeoff: the snapshot carries message
//  text and node coordinates, and after the first unlock those stay readable
//  on the locked device — the same exposure every lock-screen-capable widget
//  store accepts, and on-screen redaction is still the system's
//  privacySensitive handling. Every access guards against a missing group
//  container — Catalyst provisioning can leave the group unavailable, and
//  the store must quietly do nothing there.
//

import Foundation
import OSLog

enum WidgetSnapshotStore {
	static let appGroupID = "group.gvh.MeshtasticClient"
	static let snapshotFilename = "widget-snapshot.json"

	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Meshtastic",
		category: "🧩 WidgetSharing"
	)

	static var snapshotURL: URL? {
		FileManager.default
			.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
			.appendingPathComponent(snapshotFilename)
	}

	static func save(_ snapshot: WidgetSnapshot) {
		guard let url = snapshotURL else {
			logger.warning("No app group container; widget snapshot not written.")
			return
		}
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .millisecondsSince1970
			let data = try encoder.encode(snapshot)
			try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
			logger.debug("Wrote widget snapshot (\(snapshot.nodes.count) nodes, \(snapshot.recentMessages.count) messages).")
		} catch {
			logger.error("Could not write the widget snapshot: \(error.localizedDescription, privacy: .public)")
		}
	}

	static func load() -> WidgetSnapshot? {
		guard let url = snapshotURL,
			  let data = try? Data(contentsOf: url) else {
			return nil
		}
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .millisecondsSince1970
		guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
			  snapshot.version == WidgetSnapshot.currentVersion else {
			return nil
		}
		return snapshot
	}

	static func delete() {
		guard let url = snapshotURL else { return }
		try? FileManager.default.removeItem(at: url)
	}
}
