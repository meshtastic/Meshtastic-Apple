//
//  ESP32OTAIntroSheet.swift
//  Meshtastic
//
//  Created by Jake Bordens on 12/12/25.
//

import SwiftUI
import OSLog

struct ESP32OTAIntroSheet: View {
	@EnvironmentObject var accessoryManager: AccessoryManager
	@Environment(\.dismiss) var dismiss

	let binFileURL: URL

	var body: some View {
		switch OTAMode {
		case .wifi:
			ESP32WifiOTASheet(binFileURL: binFileURL, onUpdateComplete: { dismiss() })
		case .ble, .none:
			ESP32BLEOTASheet(binFileURL: binFileURL, onUpdateComplete: { dismiss() })
		}
	}

	private enum SupportedOTAMode {
		case none
		case wifi
		case ble
	}

	private var OTAMode: SupportedOTAMode {
		guard let connection = accessoryManager.activeConnection?.connection else {
			return .none
		}

		switch connection {
		case is TCPConnection:
			return .wifi
		case is BLEConnection:
			return .ble
		#if targetEnvironment(macCatalyst)
		case is SerialConnection:
			return .wifi
		#endif
		default:
			return .none
		}
	}
}

#Preview {
	ESP32OTAIntroSheet(binFileURL: URL(fileURLWithPath: "/tmp/firmware-esp32-s3-2.5.18.bin"))
		.environmentObject(AccessoryManager.shared)
}
