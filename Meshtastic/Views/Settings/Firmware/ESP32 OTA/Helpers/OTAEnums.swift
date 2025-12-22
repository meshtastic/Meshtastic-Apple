//
//  OTAEnums.swift
//  Meshtastic
//
//  Created by jake on 12/22/25.
//

enum DeviceBLEOTAStatusCode: UInt8 {
	case WAITING_FOR_SIZE = 0
	case ERASING_FLASH = 1
	case READY_FOR_CHUNK = 2
	case CHUNK_ACK = 3
	case OTA_COMPLETE = 4
	case ERROR = 5
}

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
