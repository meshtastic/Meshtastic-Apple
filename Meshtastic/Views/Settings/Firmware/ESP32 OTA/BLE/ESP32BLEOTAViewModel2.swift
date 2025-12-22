//
//  ESP32BLEOTAViewModel2.swift
//  Meshtastic
//
//  Created by jake on 12/21/25.
//

import Foundation
import CoreBluetooth
import OSLog
import UIKit

private let meshtasticOTAServiceId = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
private let statusCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130003") // ESP32 pTxCharacteristic ESP send (notifying)
private let otaCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130005") // ESP32 pOtaCharacteristic  ESP write


@MainActor
final class ESP32BLEOTAViewModel2: ObservableObject {
	@Published var name = ""
	@Published var transferProgress: Double = 0
	@Published var otaStatus: LocalOTAStatusCode = .idle
	@Published var statusMessage: String = ""
	
	private let ble = AsyncCentral()

	func startOTA(binURL: URL) {
		Task {
			do {
				try await ble.waitUntilPoweredOn()
				let peripheral = try await ble.scan(for: meshtasticOTAServiceId)
				name = peripheral.name ?? "unknown"
				try await ble.connect(peripheral)
				otaStatus = .connected

				let services = try await ble.discoverServices([meshtasticOTAServiceId], on: peripheral)
				guard let service = services.first(where: { $0.uuid == meshtasticOTAServiceId }) else { throw BLEError.serviceMissing }

				let chars = try await ble.discoverCharacteristics([statusCharacteristicId, otaCharacteristicId],
																  in: service,
																  on: peripheral)
				guard
					let statusChar = chars.first(where: { $0.uuid == statusCharacteristicId }),
					let otaChar = chars.first(where: { $0.uuid == otaCharacteristicId })
				else { throw BLEError.characteristicMissing }

				try await ble.setNotify(true, for: statusChar, on: peripheral)

				// Setup the ackStream before we send the invitation
				let ackStream = ble.notifications(for: statusChar)
				
				// Disable the idle timer till we're done
				UIApplication.shared.isIdleTimerDisabled = true
				
				// Start transfer
				let data = try Data(contentsOf: binURL)
				let sizeMsg = "OTA_SIZE:\(data.count)"
				try await ble.writeValue(Data(sizeMsg.utf8), for: otaChar, type: .withoutResponse, on: peripheral)

				var buffer = data

				for await notifyData in ackStream {
					if let value = notifyData.first, let code = DeviceBLEOTAStatusCode(rawValue: value) {
						switch code {
						case .WAITING_FOR_SIZE:
							// This probably doesn't happen because we already sent an OTA_SIZE meesage above
							Logger.services.info("[ESP BLE OTA] Device is waiting for size")
							self.statusMessage = "About to start..."
							
						case .ERASING_FLASH:
							self.otaStatus = .preparing
							Logger.services.info("[ESP BLE OTA] Device is erasing the flash")
							self.statusMessage = "Preparing flash partition..."
							
						case .READY_FOR_CHUNK, .CHUNK_ACK:
							self.otaStatus = .transferring
							self.statusMessage = "Transfer in progress..."

							let chunk = buffer.prefix(peripheral.maximumWriteValueLength(for: .withoutResponse) - 3)
							guard !chunk.isEmpty else { break }
							try await ble.writeValue(chunk, for: otaChar, type: .withoutResponse, on: peripheral)
							buffer.removeFirst(chunk.count)
							transferProgress = 100 * (1 - Double(buffer.count) / Double(data.count))

						case .OTA_COMPLETE:
							self.otaStatus = .completed
							self.statusMessage = "OTA Complete!"
							UIApplication.shared.isIdleTimerDisabled = false
							
						case .ERROR:
							self.otaStatus = .error
							self.statusMessage = "Device Reported an Error!"
							UIApplication.shared.isIdleTimerDisabled = false
						}
					}
				}
			} catch {
				// handle error, update UI
				self.otaStatus = .error
				UIApplication.shared.isIdleTimerDisabled = false
				Logger.services.error("OTA failed: \(error.localizedDescription)")
			}
		}
	}
}
