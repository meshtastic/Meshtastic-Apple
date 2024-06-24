//
//  Logger.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 6/3/24.
//

import OSLog

extension Logger {

	/// The logger's subsystem.
	private static var subsystem = Bundle.main.bundleIdentifier!

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

	/// Fetch from the logstore
	static public func fetch(predicateFormat: String) async throws -> [OSLogEntryLog] {

		let store = try OSLogStore(scope: .currentProcessIdentifier)
		let position = store.position(timeIntervalSinceLatestBoot: 0)
		// let calendar = Calendar.current
		// let dayAgo = calendar.date(byAdding: .day, value: -1, to: Date.now)
		// let position = store.position(date: dayAgo!)
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

extension OSLogEntryLog.Level {
	var description: String {
		switch self {
		case .undefined: "undefined"
		case .debug: "🪲 Debug"
		case .info: "ℹ️ Info"
		case .notice: "⚠️ Notice"
		case .error: "🚨 Error"
		case .fault: "💥  Fault"
		@unknown default: "default"
		}
	}
}
