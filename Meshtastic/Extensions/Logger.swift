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

	/// All logs related to data such as decoding error, parsing issues, etc.
	static let data = Logger(subsystem: subsystem, category: "🗄️ Data")

	/// All logs related to the mesh
	static let mesh = Logger(subsystem: subsystem, category: "🕸️ Mesh")

	/// All logs related to services such as network calls, location, etc.
	static let services = Logger(subsystem: subsystem, category: "🍏 Services")

	/// All logs related to tracking and analytics.
	static let statistics = Logger(subsystem: subsystem, category: "📈 Stats")

	/// Fetch from the logstore
	static public func fetch(since date: Date, predicateFormat: String) async throws -> [String] {

		let store = try OSLogStore(scope: .currentProcessIdentifier)
		let position = store.position(date: date)
		let predicate = NSPredicate(format: predicateFormat)
		let entries = try store.getEntries(at: position, matching: predicate)

		var logs: [String] = []
		for entry in entries {

			try Task.checkCancellation()

		if let log = entry as? OSLogEntryLog {
		logs.append("""
		\(entry.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().secondFraction(.fractional(3)))) \(log.level.description) \
		\(log.category) \(entry.composedMessage)\n
		""")
		} else {
			  logs.append("\(entry.date): \(entry.composedMessage)\n")
			}
		}

		if logs.isEmpty { logs = ["Nothing found"] }
		return logs
	}
}

extension OSLogEntryLog.Level {
	fileprivate var description: String {
		switch self {
		case .undefined: "undefined"
		case .debug: "Debug"
		case .info: "Info"
		case .notice: "Notice"
		case .error: "Error"
		case .fault: "Fault"
		@unknown default: "default"
		}
	}
}
