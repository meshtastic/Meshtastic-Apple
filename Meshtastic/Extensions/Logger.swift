//
//  Logger.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/24.
//

import OSLog

extension Logger {

	/// The logger's subsystem.
	private static let subsystem = Bundle.main.bundleIdentifier!

	/// All admin messages
	static let admin = Logger(subsystem: subsystem, category: "🏛 Admin")

	/// All logs related to data such as decoding error, parsing issues, etc.
	static let data = Logger(subsystem: subsystem, category: "🗄️ Data")

	/// All logs related to the mesh
	static let mesh = Logger(subsystem: subsystem, category: "🕸️ Mesh")

	/// All logs related to MQTT
	static let mqtt = Logger(subsystem: subsystem, category: "📱 MQTT")

	/// All detailed logs originating from the device (radio).
	static let radio = Logger(subsystem: subsystem, category: "📟 Radio")

	/// All logs related to services such as network calls, location, etc.
	static let services = Logger(subsystem: subsystem, category: "🍏 Services")

	/// All logs related to tracking and analytics.
	static let statistics = Logger(subsystem: subsystem, category: "📊 Stats")

	/// All logs related to the transport layer
	static let transport = Logger(subsystem: subsystem, category: "🚚 Transport")

	/// All logs related to TAK server and CoT messages
	static let tak = Logger(subsystem: subsystem, category: "🎯 TAK")

	/// All logs related to Local Mesh Discovery scans
	static let discovery = Logger(subsystem: subsystem, category: "📡 Discovery")

	/// All logs related to the documentation browser and AI assistant
	static let docs = Logger(subsystem: subsystem, category: "📖 Docs")

	/// All logs related to node database backup and restore operations
	static let backup = Logger(subsystem: subsystem, category: "💾 Backup")

	/// Fetch from the logstore.
	/// - Parameter since: when provided, only entries at or after this date are scanned
	///   (used for incremental live tailing, e.g. the Packet Stream). When `nil`, the scan
	///   starts at boot — the historical/full-snapshot behavior.
	static public func fetch(predicateFormat: String, since: Date? = nil) async throws -> [OSLogEntryLog] {

		let store = try OSLogStore(scope: .currentProcessIdentifier)
		let position = if let since {
			store.position(date: since)
		} else {
			store.position(timeIntervalSinceLatestBoot: 0)
		}
		let predicate = NSPredicate(format: predicateFormat)
		let entries = try store.getEntries(at: position, matching: predicate)

		var logs: [OSLogEntryLog] = []
		for entry in entries {

			try Task.checkCancellation()

			if let log = entry as? OSLogEntryLog {
				logs.append(log)
			}
		}

		if logs.isEmpty { logs = [] }
		return logs
	}
}
