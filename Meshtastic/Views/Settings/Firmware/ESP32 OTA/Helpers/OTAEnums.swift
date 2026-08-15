//
//  OTAEnums.swift
//  Meshtastic
//
//  Created by jake on 12/22/25.
//

import Foundation

// Removed DeviceBLEOTAStatusCode as the device now communicates via Text (OK/ERR)

enum LocalOTAStatusCode: String, CustomStringConvertible {
	var description: String { return self.rawValue }
	case idle = "Ready"
	case waitingForConnection = "Waiting for Connection"
	case connected = "Connected"
	case preparing = "Preparing"
	case transferring = "Uploading"
	case completed = "Completed"
	case error = "Error"
}

enum ESP32OTAStreamDecision: Equatable {
	case advance
	case complete
}

enum ESP32OTAProtocol {
	static let terminalResponseTimeout: TimeInterval = 30.0

	static func chunkDecision(response: String, nextOffset: Int, fileSize: Int) throws -> ESP32OTAStreamDecision {
		let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
		switch trimmed {
		case "ACK":
			return .advance
		case "OK":
			if nextOffset >= fileSize {
				return .complete
			}
			throw BLEOTAFailure.unexpectedResponse("Premature OK received at offset \(nextOffset)")
		default:
			throw BLEOTAFailure.unexpectedResponse(trimmed)
		}
	}

	static func validateTerminalResponse(_ response: String) throws {
		let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed == "OK" else {
			throw BLEOTAFailure.unexpectedResponse(trimmed)
		}
	}
}
