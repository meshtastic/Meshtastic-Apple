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
import CryptoKit

private let meshtasticOTAServiceId = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
private let statusCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130003") // ESP32 Send (Notify) -> "OK", "ACK", "ERR..."
private let otaCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130005")    // ESP32 Receive (Write)

@MainActor
final class ESP32BLEOTAViewModel2: ObservableObject {
	@Published var name = ""
	@Published var transferProgress: Double = 0
	@Published var otaStatus: LocalOTAStatusCode = .idle
	@Published var statusMessage: String = ""
	
	private let ble = AsyncCentral()

	func startOTA(binURL: URL) {
		Task {
			// Prevent screen sleep during update
			UIApplication.shared.isIdleTimerDisabled = true
			
			do {
				// --- 1. Connection Phase ---
				self.statusMessage = "Connecting..."
				self.otaStatus = .waitingForConnection
				
				try await ble.waitUntilPoweredOn()
				let peripheral = try await ble.scan(for: meshtasticOTAServiceId)
				name = peripheral.name ?? "unknown"
				try await ble.connect(peripheral)
				
				otaStatus = .connected
				self.statusMessage = "Discovering Services..."

				let services = try await ble.discoverServices([meshtasticOTAServiceId], on: peripheral)
				guard let service = services.first(where: { $0.uuid == meshtasticOTAServiceId }) else { throw BLEError.serviceMissing }

				let chars = try await ble.discoverCharacteristics([statusCharacteristicId, otaCharacteristicId],
																  in: service,
																  on: peripheral)
				guard
					let statusChar = chars.first(where: { $0.uuid == statusCharacteristicId }),
					let otaChar = chars.first(where: { $0.uuid == otaCharacteristicId })
				else { throw BLEError.characteristicMissing }

				// --- 2. Setup Notification Stream ---
				try await ble.setNotify(true, for: statusChar, on: peripheral)
				let stream = ble.notifications(for: statusChar)
				var iterator = stream.makeAsyncIterator()
				
				// --- 3. Prepare Firmware & Command ---
				let data = try Data(contentsOf: binURL)
				let sha256Digest = SHA256.hash(data: data)
				let fileHash = sha256Digest.map { String(format: "%02hhx", $0) }.joined()
				let fileSize = data.count
				
				Logger.services.info("Firmware Size: \(fileSize), Hash: \(fileHash)")
				
				// Unified Protocol Command: "OTA <size> <hash>\n"
				let command = "OTA \(fileSize) \(fileHash)\n"
				
				// --- 4. Handshake ---
				self.statusMessage = "Negotiating..."
				
				// Send command with response to ensure delivery before waiting for logic response
				try await ble.writeValue(Data(command.utf8), for: otaChar, type: .withResponse, on: peripheral)
				
				// Wait for "OK" response from ESP32
				guard let handshakeData = await iterator.next(),
					  let handshakeStr = String(data: handshakeData, encoding: .utf8),
					  handshakeStr.trimmingCharacters(in: .whitespacesAndNewlines) == "OK" else {
					throw OTAError.unexpectedResponse("Handshake failed")
				}
				
				Logger.services.info("Handshake OK. Starting Stream.")
				
				// --- 5. Upload Stream ---
				self.otaStatus = .transferring
				self.statusMessage = "Uploading..."
				
				var offset = 0
				// Use MTU - 3 bytes overhead for chunk size.
				let chunkSize = peripheral.maximumWriteValueLength(for: .withoutResponse)
				
				while offset < fileSize {
					let endIndex = min(offset + chunkSize, fileSize)
					let chunk = data.subdata(in: offset..<endIndex)
					
					// Send chunk
					try await ble.writeValue(chunk, for: otaChar, type: .withoutResponse, on: peripheral)
					
					// Optimistically calculate new offset to determine if this was the last chunk
					let nextOffset = offset + chunk.count
					
					// [FLOW CONTROL]
					// Wait for ACK (or OK if last packet) before proceeding.
					// This ensures the ESP32 has written the chunk to flash.
					guard let respData = await iterator.next(),
						  let respStr = String(data: respData, encoding: .utf8) else {
						throw OTAError.unexpectedResponse("Connection lost waiting for ACK")
					}
					
					let trimmed = respStr.trimmingCharacters(in: .whitespacesAndNewlines)
					
					if trimmed == "ACK" {
						// Normal chunk processed successfully
						offset = nextOffset
						
						// Update UI occasionally
						if offset % (chunkSize * 20) == 0 {
							self.transferProgress = Double(offset) / Double(fileSize)
						}
						
					} else if trimmed == "OK" {
						// "OK" indicates completion (hash verified, partition set).
						// This should only happen on the very last chunk.
						if nextOffset >= fileSize {
							offset = nextOffset
							self.transferProgress = 1.0
							self.otaStatus = .completed
							self.statusMessage = "Success! Rebooting..."
							Logger.services.info("OTA Success (OK received on last chunk)")
							break // Exit loop
						} else {
							// OK received before we finished sending? Error.
							throw OTAError.unexpectedResponse("Premature OK received at offset \(nextOffset)")
						}
						
					} else {
						// Likely ERR or garbage
						throw OTAError.unexpectedResponse(trimmed)
					}
				}
				
				// Double check completion state
				if self.otaStatus != .completed {
					throw OTAError.unexpectedResponse("Stream ended without OK")
				}
				
			} catch {
				self.otaStatus = .error
				self.statusMessage = "Error: \(error.localizedDescription)"
				Logger.services.error("OTA Failed: \(error.localizedDescription)")
			}
			
			UIApplication.shared.isIdleTimerDisabled = false
		}
	}
}
