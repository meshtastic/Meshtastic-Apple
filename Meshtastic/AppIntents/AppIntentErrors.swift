//
//  AppIntentErrors.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/11/24.
//

#if canImport(AppIntents)
import Foundation
import OSLog
import SwiftUI

@available(iOS 16.0, *)
class AppIntentErrors {
	enum AppIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
		case notConnected
		case message(_ message: String)

		var localizedStringResource: LocalizedStringResource {
			switch self {
			case let .message(message):
				Logger.services.error("App Intent: \(message, privacy: .public)")
				return "Error: \(message)"
			case .notConnected:
				Logger.services.error("App Intent: No Connected Node")
				return "No Connected Node"
			}
		}
	}
}

#endif
