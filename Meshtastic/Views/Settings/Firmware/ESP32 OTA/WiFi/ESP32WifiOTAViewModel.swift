import Foundation
import Network
import CryptoKit
import Combine
import OSLog
import os

@MainActor
class ESP32WifiOTAViewModel: ObservableObject {
	
	// MARK: - Published State
	@Published var statusMessage: String = "Idle"
	@Published var progress: Double = 0.0
	@Published var errorMessage: String?
	@Published var otaState: LocalOTAStatusCode = .idle
	
	// MARK: - Constants
	private let port: NWEndpoint.Port = 3232
	private let chunkSize = 4096 // 4KB chunks for efficient TCP transfer
	
	// How long to wait for the device to reboot and accept TCP connections (Manual Host)
	// or broadcast UDP packets (Auto Discovery)
	private let connectionTimeout: TimeInterval = 60.0
	
	// MARK: - Public Interface
	
	func startUpdate(host: String? = nil, firmwareUrl: URL, password: String? = nil) async {
		guard otaState == .idle else { return }
		
		progress = 0.0
		errorMessage = nil
		statusMessage = "Starting..."
		otaState = .waitingForConnection
		
		do {
			let firmwareData = try Data(contentsOf: firmwareUrl)
			let targetEndpoint: NWEndpoint
			
			// 1. Discovery / Connection Phase
			if let manualHost = host, !manualHost.isEmpty {
				Logger.services.info("[ESP OTA] Using manual host: \(manualHost)")
				targetEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(manualHost), port: port)
				
				// Wait for the device to reboot and become responsive on TCP
				statusMessage = "Waiting for device..."
				try await waitForManualHostReboot(endpoint: targetEndpoint)
			} else {
				statusMessage = "Scanning for device..."
				Logger.services.info("[ESP OTA] Listening for UDP broadcast...")
				targetEndpoint = try await discoverDevice()
			}
			
			// 2. Upload Phase
			statusMessage = "Device ready. Negotiating..."
			Logger.services.info("[ESP OTA] Device Ready at \(String(describing: targetEndpoint)). Starting Protocol.")
			
			try await connectAndUpload(endpoint: targetEndpoint, data: firmwareData)
			
			statusMessage = "Success!"
			otaState = .completed
			Logger.services.info("[ESP OTA] Update Complete")
			
		} catch {
			Logger.services.error("[ESP OTA] Error: \(error.localizedDescription)")
			errorMessage = error.localizedDescription
			statusMessage = "Failed"
			otaState = .error
		}
	}
	
	// MARK: - Manual Host Logic (TCP Polling)
	
	/// Actively probes the target port until a connection is accepted or timeout occurs.
	private func waitForManualHostReboot(endpoint: NWEndpoint) async throws {
		let deadline = Date().addingTimeInterval(connectionTimeout)
		
		Logger.services.info("[ESP OTA] Probing TCP \(String(describing: endpoint)) for availability...")
		
		while Date() < deadline {
			if await probeTcpConnection(endpoint: endpoint) {
				Logger.services.info("[ESP OTA] TCP Probe successful. Device is up.")
				return
			}
			// Wait a bit before retrying
			try await Task.sleep(for: .seconds(1))
		}
		
		throw OTAError.timeout
	}
	
	/// Helper to attempt a single connection. Returns true if successful, false if refused/unreachable.
	private func probeTcpConnection(endpoint: NWEndpoint) async -> Bool {
		let connection = NWConnection(to: endpoint, using: .tcp)
		return await withCheckedContinuation { continuation in
			var hasResumed = false
			
			connection.stateUpdateHandler = { state in
				if hasResumed { return }
				
				switch state {
				case .ready:
					hasResumed = true
					connection.cancel() // Close the probe connection immediately
					continuation.resume(returning: true)
				case .failed(_):
					hasResumed = true
					connection.cancel()
					continuation.resume(returning: false)
				case .waiting(_):
					// .waiting usually implies the network interface is up but the host isn't responding (yet)
					// We treat this as a fail for this specific probe attempt to trigger a retry loop
					hasResumed = true
					connection.cancel()
					continuation.resume(returning: false)
				default:
					break
				}
			}
			
			connection.start(queue: .global())
		}
	}
	
	// MARK: - Auto Discovery Logic (UDP Listener)
	
	/// Listens for UDP broadcasts on port 3232 to find the ESP32.
	private func discoverDevice() async throws -> NWEndpoint {
		let parameters = NWParameters.udp
		parameters.allowLocalEndpointReuse = true
		
		let listener = try NWListener(using: parameters, on: port)
		
		return try await withCheckedThrowingContinuation { continuation in
			let hasResumed = OSAllocatedUnfairLock(initialState: false)
			
			// Handle incoming UDP packets
			listener.newConnectionHandler = { newConnection in
				newConnection.start(queue: .global())
				newConnection.receiveMessage { data, context, isComplete, error in
					if let data = data, let message = String(data: data, encoding: .utf8) {
						// C++ sends: "MeshtasticOTA_<MAC>"
						if message.hasPrefix("MeshtasticOTA") {
							hasResumed.withLock { resumed in
								if !resumed {
									resumed = true
									if let endpoint = newConnection.endpoint as? NWEndpoint {
										continuation.resume(returning: endpoint)
										listener.cancel()
									} else {
										continuation.resume(throwing: OTAError.discoveryFailed)
										listener.cancel()
									}
								}
							}
						}
					}
					newConnection.cancel()
				}
			}
			
			listener.start(queue: .global())
			
			// Timeout logic
			Task {
				try await Task.sleep(for: .seconds(connectionTimeout))
				hasResumed.withLock { resumed in
					if !resumed {
						resumed = true
						listener.cancel()
						continuation.resume(throwing: OTAError.timeout)
					}
				}
			}
		}
	}
	
	// MARK: - TCP Protocol Logic
	
	private func connectAndUpload(endpoint: NWEndpoint, data: Data) async throws {
		let connection = NWConnection(to: endpoint, using: .tcp)
		
		// 1. Establish TCP Connection
		connection.start(queue: .global())
		try await waitForConnectionReady(connection)
		
		// 2. Prepare Command: OTA <size> <hash>\n
		// \n is critical for the C++ OtaProcessor to trigger parsing
		let sha256Digest = SHA256.hash(data: data)
		let fileHash = sha256Digest.map { String(format: "%02hhx", $0) }.joined()
		let command = "OTA \(data.count) \(fileHash)\n"
		
		Logger.services.info("[ESP OTA] Sending Command: \(command)")
		
		// 3. Send Command
		try await connection.sendAsync(data: command.data(using: .utf8)!)
		
		// 4. Wait for initial "OK\n", handling "ERASING"
		var handshakeComplete = false
		while !handshakeComplete {
			let response = try await readLine(from: connection)
			let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
			
			if trimmed == "OK" {
				handshakeComplete = true
			} else if trimmed == "ERASING" {
				await updateUI {
					self.statusMessage = "Erasing partition..."
				}
				Logger.services.info("[ESP OTA] Device is erasing flash...")
			} else {
				throw OTAError.unexpectedResponse(response)
			}
		}
	
		// 5. Stream Firmware Data
		await updateUI {
			self.otaState = .transferring
			self.statusMessage = "Uploading firmware..."
		}
		
		try await performChunkedTransfer(connection: connection, data: data)
		
		// 6. Wait for final "OK\n" (Validation/Flash Complete)
		Logger.services.info("[ESP OTA] Upload done. Waiting for final verification...")
		await updateUI {
			self.statusMessage = "Verifying..."
			self.progress = 1.0
		}
		
		// We set a longer receive timeout here because Flash operations (hash check) can take a few seconds
		let finalResponse = try await readLine(from: connection)
		if finalResponse.trimmingCharacters(in: .whitespacesAndNewlines) != "OK" {
			throw OTAError.unexpectedResponse(finalResponse)
		}
		
		connection.cancel()
	}
	
	// MARK: - Network Helpers
	
	/// Reads from connection until a newline character is found.
	nonisolated private func readLine(from connection: NWConnection) async throws -> String {
		return try await withCheckedThrowingContinuation { continuation in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
				if let error = error {
					continuation.resume(throwing: error)
					return
				}
				if let data = data, let string = String(data: data, encoding: .utf8) {
					continuation.resume(returning: string)
				} else {
					continuation.resume(throwing: OTAError.encodingFailed)
				}
			}
		}
	}
	
	nonisolated private func waitForConnectionReady(_ connection: NWConnection) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			var didResume = false
			connection.stateUpdateHandler = { state in
				if didResume { return }
				switch state {
				case .ready:
					didResume = true
					continuation.resume()
				case .failed(let err):
					didResume = true
					continuation.resume(throwing: err)
				case .cancelled:
					didResume = true
					continuation.resume(throwing: CancellationError())
				default: break
				}
			}
		}
	}
	
	nonisolated private func performChunkedTransfer(connection: NWConnection, data: Data) async throws {
		var offset = 0
		let totalSize = data.count
		
		while offset < totalSize && !Task.isCancelled {
			let endIndex = min(offset + chunkSize, totalSize)
			let chunk = data[offset..<endIndex]
			
			// We do NOT wait for ACK here.
			// TCP handles flow control. C++ net_ota logic does not send ACKs for chunks.
			try await connection.sendAsync(data: chunk)
			
			offset += chunk.count
			let percent = Double(offset) / Double(totalSize)
			
			// Update UI periodically
			if offset % (chunkSize * 10) == 0 {
				await updateUI {
					self.progress = percent
				}
			}
		}
	}
	
	private func updateUI(_ block: @MainActor @Sendable () -> Void) async {
		await MainActor.run { block() }
	}
}


// MARK: - Extensions & Errors

enum OTAError: Error, LocalizedError {
	case encodingFailed
	case connectionFailed
	case unexpectedResponse(String)
	case discoveryFailed
	case timeout
	
	var errorDescription: String? {
		switch self {
		case .timeout: return "Timeout waiting for device."
		case .connectionFailed: return "Failed to establish connection."
		case .discoveryFailed: return "Could not discover ESP32."
		case .unexpectedResponse(let r): return "Error from device: \(r)"
		default: return "OTA Error"
		}
	}
}

extension NWConnection {
	func sendAsync(data: Data) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			send(content: data, completion: .contentProcessed { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}
}
