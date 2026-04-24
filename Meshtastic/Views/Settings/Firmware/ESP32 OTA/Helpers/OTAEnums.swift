//
//  OTAEnums.swift
//  Meshtastic
//
//  Created by jake on 12/22/25.
//

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
