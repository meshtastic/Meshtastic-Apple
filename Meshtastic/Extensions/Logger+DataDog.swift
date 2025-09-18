//
//  Logger+DataDog.swift
//  Meshtastic
//
//  Created by Jake Bordens on 9/17/25.
//

import Foundation
import os.log
import DatadogRUM
import DatadogLogs

struct DatadogLogger {
	private let osLogger: os.Logger
	private let ddLogger: any DatadogLogs.LoggerProtocol
	
	// Initialize with a subsystem and category, similar to Logger
	fileprivate init(subsystem: String, category: String) {
		self.osLogger = Logger(subsystem: subsystem, category: category)
		self.ddLogger = DatadogLogs.Logger.create(
			with: Logger.Configuration(
				name: "gvh.Meshtastic",
				networkInfoEnabled: true,
				remoteLogThreshold: .debug,
				consoleLogFormat: .short
			)
		)
	}
	
	// ✨ os.Logger functions like debug, info, etc., are not normal functions.
	// They rely on compiler magic to parse the interpolated string, identify the
	// privacy modifiers (.public, .private), and handle the data securely without
	// ever creating a potentially sensitive string in your app's memory.
	// To do this, the compiler must see the string literal at the point of the call.
	// Since this is going to Datadog, care should be taken to only use these functions
	// with public debug data.
	func debug(_ message: String) {
		osLogger.debug("\(message, privacy: .public)")
		ddLogger.debug(message)
	}

	func info(_ message: String) {
		osLogger.info("\(message, privacy: .public)")
		ddLogger.info(message)
	}

	func warning(_ message: String) {
		osLogger.warning("\(message, privacy: .public)")
		ddLogger.warn(message)
	}

	func error(_ message: String) {
		osLogger.error("\(message, privacy: .public)")
		ddLogger.error(message)
	}
	
	// MARK: - Methods for RUM actions
	func action(name: String, attributes: [String: any Encodable]? = nil) {
		RUMMonitor.shared().addAction(
			type: .custom,
			name: name,
			attributes: attributes ?? [:]
		)
	}
}

extension os.Logger {
	static let datadog = DatadogLogger(subsystem: "datadog", category: "🐶 DataDog")
}
