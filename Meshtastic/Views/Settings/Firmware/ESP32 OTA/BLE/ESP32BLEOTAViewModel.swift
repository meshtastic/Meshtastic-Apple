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

enum BLEOTAFailure: Error, LocalizedError {
	case timeout
	case unexpectedResponse(String)
	case disconnected
	
	var errorDescription: String? {
		switch self {
		case .timeout: return "The operation timed out."
		case .unexpectedResponse(let s): return "Device sent unexpected response: \(s)"
		case .disconnected: return "Device disconnected unexpectedly."
		}
	}
}

@MainActor
final class ESP32BLEOTAViewModel: ObservableObject {
	@Published var name = ""
	@Published var transferProgress: Double = 0
	@Published var otaStatus: LocalOTAStatusCode = .idle
	@Published var statusMessage: String = ""
	
	private let ble = AsyncCentral()
	
	// MARK: - User Actions
	
	func retry() {
		self.transferProgress = 0
		self.statusMessage = ""
		self.otaStatus = .idle
	}
	
	func startOTA(binURL: URL, desiredPeripheral: UUID?) async {
		// Prevent screen sleep during update
		UIApplication.shared.isIdleTimerDisabled = true
		
		do {
			// --- 1. Connection Phase ---
			self.statusMessage = "Connecting..."
			self.otaStatus = .waitingForConnection
			
			// Scan has its own internal timeout logic in AsyncCentral
			try await ble.waitUntilPoweredOn()
			let peripheral = try await ble.scan(for: meshtasticOTAServiceId, timeout: 15.0)
			
			name = peripheral.name ?? "unknown"
			
			// Connect with timeout (10s)
			try await withTimeout(seconds: 10) {
				try await self.ble.connect(peripheral)
			}
			
			otaStatus = .connected
			self.statusMessage = "Discovering Services..."
			
			// Discover Services with timeout (10s)
			let services = try await withTimeout(seconds: 10) {
				try await self.ble.discoverServices([meshtasticOTAServiceId], on: peripheral)
			}
			guard let service = services.first(where: { $0.uuid == meshtasticOTAServiceId }) else { throw BLEError.serviceMissing }
			
			// Discover Characteristics with timeout (10s)
			let chars = try await withTimeout(seconds: 10) {
				try await self.ble.discoverCharacteristics([statusCharacteristicId, otaCharacteristicId],
														   in: service,
														   on: peripheral)
			}
			
			guard
				let statusChar = chars.first(where: { $0.uuid == statusCharacteristicId }),
				let otaChar = chars.first(where: { $0.uuid == otaCharacteristicId })
			else { throw BLEError.characteristicMissing }
			
			// --- 2. Setup Notification Stream ---
			// Timeout for setting notify (usually fast, but good to be safe)
			try await withTimeout(seconds: 5) {
				try await self.ble.setNotify(true, for: statusChar, on: peripheral)
			}
			
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
			
			// Send command
			try await ble.writeValue(Data(command.utf8), for: otaChar, type: .withResponse, on: peripheral)
			
			// Wait for "OK" response from ESP32, handling "ERASING" intermediate state
			var handshakeComplete = false
			
			// Handshake loop
			while !handshakeComplete {
				// We allow a generous timeout (30s) here because "ERASING" flash can take time on the ESP32
				// before it sends the next message.
				guard let handshakeData = try await withTimeout(seconds: 30, operation: {
					await iterator.next()
				}) else {
					throw BLEOTAFailure.disconnected
				}
				
				guard let handshakeStr = String(data: handshakeData, encoding: .utf8) else {
					throw BLEOTAFailure.unexpectedResponse("Encoding Error")
				}
				
				let trimmed = handshakeStr.trimmingCharacters(in: .whitespacesAndNewlines)
				
				if trimmed == "OK" {
					handshakeComplete = true
				} else if trimmed == "ERASING" {
					// Update UI to let user know the device is busy erasing partition
					self.statusMessage = "Erasing partition..."
					Logger.services.info("Device is erasing flash...")
					// We loop again, resetting the 30s timeout for the next message
				} else {
					// Any other response is an error
					throw BLEOTAFailure.unexpectedResponse(trimmed)
				}
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
				// Wait for ACK (or OK if last packet).
				// We use a 5 second timeout per chunk. If the device stalls, we fail.
				guard let respData = try await withTimeout(seconds: 5.0, operation: {
					await iterator.next()
				}) else {
					throw BLEOTAFailure.disconnected
				}
				
				guard let respStr = String(data: respData, encoding: .utf8) else {
					throw BLEOTAFailure.unexpectedResponse("Encoding Error")
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
						throw BLEOTAFailure.unexpectedResponse("Premature OK received at offset \(nextOffset)")
					}
					
				} else {
					// Likely ERR or garbage
					throw BLEOTAFailure.unexpectedResponse(trimmed)
				}
			}
			
			// Double check completion state
			if self.otaStatus != .completed {
				throw BLEOTAFailure.unexpectedResponse("Stream ended without OK")
			}
			ble.disconnect(peripheral)
		} catch {
			self.otaStatus = .error
			self.statusMessage = error.localizedDescription
			Logger.services.error("OTA Failed: \(error.localizedDescription)")
		}
		
		UIApplication.shared.isIdleTimerDisabled = false
	}
	
	// MARK: - Helpers
	
	/// Executes an async operation with a strict timeout.
	/// - Parameters:
	///   - seconds: The timeout duration.
	///   - operation: The async closure to execute.
	/// - Returns: The result of the operation.
	/// - Throws: `BLEOTAFailure.timeout` if time expires, or rethrows errors from the operation.
	private func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
		return try await withThrowingTaskGroup(of: T.self) { group in
			// Task 1: The actual operation
			group.addTask {
				return try await operation()
			}
			
			// Task 2: The timer
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
				throw BLEOTAFailure.timeout
			}
			
			// Wait for the first one to complete
			guard let result = try await group.next() else { throw BLEOTAFailure.timeout }
			
			// Cancel the other task (e.g. if operation finishes, cancel timer)
			group.cancelAll()
			
			return result
		}
	}
}
