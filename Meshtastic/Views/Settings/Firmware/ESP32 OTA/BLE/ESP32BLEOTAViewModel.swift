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
	
	/// What the radio said about the update it was asked to start. A refusal arrives while
	/// the app is still waiting for the device to show up in OTA mode, and it is a far better
	/// error than the timeout that would otherwise be reported.
	@Published private(set) var deviceRefusal: String?

	/// The last thing the radio said about this update, recognized or not. A message we
	/// cannot classify does not end the update, but if the update then fails anyway the
	/// radio's own words are a better error than the timeout.
	private var lastDeviceNotice: String?

	func retry() {
		self.transferProgress = 0
		self.statusMessage = ""
		self.deviceRefusal = nil
		self.lastDeviceNotice = nil
		self.otaStatus = .idle
	}

	func handleDeviceNotice(_ message: String) {
		guard otaStatus != .completed, otaStatus != .error else { return }
		lastDeviceNotice = message
		switch OTARefusal.classify(message) {
		case .refused(let explanation):
			statusMessage = explanation
			deviceRefusal = explanation
			otaStatus = .error
		case .progress(let text):
			statusMessage = text
		case nil:
			// Not a sentence we know. Show it, but leave the update running: it may be
			// unrelated, and firmware wording changes.
			statusMessage = message
		}
	}
	
	func startOTA(binURL: URL, desiredPeripheral: UUID?) async {
		// Prevent screen sleep during update; guaranteed cleanup on any exit
		UIApplication.shared.isIdleTimerDisabled = true
		defer {
			UIApplication.shared.isIdleTimerDisabled = false
		}
		
		deviceRefusal = nil
		lastDeviceNotice = nil

		do {
			// --- 1. Connection Phase ---
			self.statusMessage = "Connecting..."
			self.otaStatus = .waitingForConnection
			
			// Scan has its own internal timeout logic in AsyncCentral
			try await ble.waitUntilPoweredOn()
			let peripheral = try await ble.scan(for: meshtasticOTAServiceId, timeout: 15.0)
			
			name = peripheral.name ?? "unknown"
			// Every exit from here on leaves the device connected otherwise, including the
			// failures: the device sits in update mode holding a link to an app that has
			// given up on it.
			defer { ble.disconnect(peripheral) }
			
			try await ble.connect(peripheral, timeout: 10)
			
			otaStatus = .connected
			self.statusMessage = "Discovering Services..."
			
			let services = try await ble.discoverServices([meshtasticOTAServiceId], on: peripheral, timeout: 10)
			guard let service = services.first(where: { $0.uuid == meshtasticOTAServiceId }) else { throw BLEError.serviceMissing }
			
			let chars = try await ble.discoverCharacteristics([statusCharacteristicId, otaCharacteristicId],
															 in: service,
															 on: peripheral,
															 timeout: 10)
			
			guard
				let statusChar = chars.first(where: { $0.uuid == statusCharacteristicId }),
				let otaChar = chars.first(where: { $0.uuid == otaCharacteristicId })
			else { throw BLEError.characteristicMissing }
			
			// --- 2. Setup Notification Stream ---
			try await ble.setNotify(true, for: statusChar, on: peripheral, timeout: 5)
			
			let stream = ble.notifications(for: statusChar)
			var iterator = stream.makeAsyncIterator()
			
			// --- 3. Prepare Firmware & Command ---
			let (data, fileHash, fileSize) = try await Task.detached(priority: .userInitiated) {
				let fileData = try Data(contentsOf: binURL, options: .mappedIfSafe)
				let digest = SHA256.hash(data: fileData)
				let hashString = digest.map { String(format: "%02hhx", $0) }.joined()
				return (fileData, hashString, fileData.count)
			}.value
			
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
				// Closing the sheet cancels the task that owns this transfer. Stop writing
				// and drop the connection rather than flashing on into a screen that is gone.
				if Task.isCancelled {
					Logger.services.info("📡 [ESP32 BLE OTA] Transfer cancelled at \(offset) of \(fileSize) bytes")
					throw CancellationError()
				}

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
				
				switch try ESP32OTAProtocol.chunkDecision(response: respStr, nextOffset: nextOffset, fileSize: fileSize) {
				case .advance:
					// Normal chunk processed successfully
					offset = nextOffset
					
					// Update UI occasionally
					if offset % (chunkSize * 20) == 0 {
						self.transferProgress = Double(offset) / Double(fileSize)
					}
					
				case .complete:
					// "OK" indicates completion (hash verified, partition set).
					offset = nextOffset
					markUploadCompleted(logMessage: "OTA Success (OK received on last chunk)")
				}
			}
			
			if self.otaStatus != .completed, offset >= fileSize {
				guard let terminalData = try await withTimeout(seconds: ESP32OTAProtocol.terminalResponseTimeout, operation: {
					await iterator.next()
				}) else {
					throw BLEOTAFailure.disconnected
				}

				guard let terminalResponse = String(data: terminalData, encoding: .utf8) else {
					throw BLEOTAFailure.unexpectedResponse("Encoding Error")
				}

				try ESP32OTAProtocol.validateTerminalResponse(terminalResponse)
				markUploadCompleted(logMessage: "OTA Success (OK received after final ACK)")
			}

			// Double check completion state
			if self.otaStatus != .completed {
				throw BLEOTAFailure.unexpectedResponse("Stream ended without OK")
			}
		} catch {
			self.otaStatus = .error
			// The radio's own reason beats "the device never advertised in OTA mode", which is
			// only ever the symptom of it.
			self.statusMessage = deviceRefusal ?? lastDeviceNotice ?? error.localizedDescription
			Logger.services.error("OTA Failed: \(self.statusMessage, privacy: .public)")
		}
		
		UIApplication.shared.isIdleTimerDisabled = false
	}
	
	// MARK: - Helpers

	private func markUploadCompleted(logMessage: String) {
		self.transferProgress = 1.0
		self.otaStatus = .completed
		self.statusMessage = "Success! Rebooting..."
		Logger.services.info("\(logMessage)")
	}
	
	/// Executes an async operation with a strict timeout.
	///
	/// Only safe for operations that end when their task is cancelled — reading the
	/// notification stream, for instance. A Core Bluetooth call waiting on a checked
	/// continuation ignores cancellation, so racing it here would hang instead of
	/// timing out; those calls carry their own deadlines in `AsyncCentral`.
	/// - Parameters:
	///   - seconds: The timeout duration.
	///   - operation: The async closure to execute.
	/// - Returns: The result of the operation.
	/// - Throws: `BLEOTAFailure.timeout` if time expires, or rethrows errors from the operation.
	private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
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
