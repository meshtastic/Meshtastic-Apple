//
//  AppIntentErrors.swift
//  Meshtastic
//
//  Created by Benjamin Faershtein on 8/11/24.
//

import Foundation

class AppIntentErrors {
	enum AppIntentError: Swift.Error, CustomLocalizedStringResourceConvertible {
		case notConnected
		case message(_ message: String)

		var localizedStringResource: LocalizedStringResource {
			switch self {
			case let .message(message): return "Error: \(message)"
			case .notConnected: return "No Connected Node"
			}
		}
	}
}
