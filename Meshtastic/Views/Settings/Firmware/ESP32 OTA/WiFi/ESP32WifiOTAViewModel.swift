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
	private let chunkSize = 1024
	
	private let connectionTimeout: TimeInterval = 60.0
	private let packetTimeout: TimeInterval = 10.0
	private let finalVerifyTimeout: TimeInterval = 30.0
	
	// MARK: - Public Interface
	
	func retry() {
		self.progress = 0
		self.statusMessage = "Idle"
		self.errorMessage = nil
		self.otaState = .idle
	}
	
	func startUpdate(host: String? = nil, firmwareUrl: URL, password: String? = nil) async {
		guard otaState == .idle || otaState == .error else { return }
		
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
			
			// 3. Success
			// Explicitly force progress to 1.0 to ensure Checkmark appears
			progress = 1.0
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
	
	// MARK: - TCP Protocol Logic
	
	private func connectAndUpload(endpoint: NWEndpoint, data: Data) async throws {
		let connection = NWConnection(to: endpoint, using: .tcp)
		let reader = AsyncLineReader(connection: connection)
		
		// 1. Establish TCP Connection
		connection.start(queue: .global())
		try await waitForConnectionReady(connection)
		
		// 2. Prepare Command
		let sha256Digest = SHA256.hash(data: data)
		let fileHash = sha256Digest.map { String(format: "%02hhx", $0) }.joined()
		let command = "OTA \(data.count) \(fileHash)\n"
		
		Logger.services.info("[ESP OTA] Sending Command: \(command)")
		
		// 3. Send Command
		try await connection.sendAsync(data: command.data(using: .utf8)!)
		
		// 4. Handshake (Wait for "OK" or "ERASING")
		var handshakeComplete = false
		while !handshakeComplete {
			let response: String
			do {
				// Timeout logic relies on the Reader unblocking immediately on cancel
				response = try await withTimeout(seconds: 30.0) {
					try await reader.readLine()
				}
			} catch {
				Logger.services.error("[ESP OTA] Handshake Timeout. Cancelling connection.")
				connection.cancel()
				throw error
			}
			
			let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
			
			if trimmed == "OK" {
				handshakeComplete = true
			} else if trimmed == "ERASING" {
				await updateUI { self.statusMessage = "Erasing partition..." }
			} else if trimmed.isEmpty {
				continue
			} else {
				connection.cancel()
				throw OTAError.unexpectedResponse(trimmed)
			}
		}
		
		// 5. Parallel Upload & Verification
		await updateUI {
			self.otaState = .transferring
			self.statusMessage = "Uploading firmware..."
		}
		
		let isUploading = OSAllocatedUnfairLock(initialState: true)
		
		try await withThrowingTaskGroup(of: Void.self) { group in
			
			// TASK A: Writer (Sends Data)
			group.addTask {
				var offset = 0
				let totalSize = data.count
				
				while offset < totalSize {
					try Task.checkCancellation()
					
					let endIndex = min(offset + self.chunkSize, totalSize)
					let chunk = data[offset..<endIndex]
					
					try await connection.sendAsync(data: chunk)
					
					offset += chunk.count
					
					// Update UI periodically to avoid flooding main thread
					if offset % (self.chunkSize * 10) == 0 {
						let percent = Double(offset) / Double(totalSize)
						await self.updateUI { self.progress = percent }
					}
				}
				
				// MARK: - FIX: Force 100% on upload completion
				// Because of the modulo operator above, the loop often ends at 99.xxx%.
				// We force it to 1.0 here so the user sees "100%" while waiting for verification.
				await self.updateUI { self.progress = 1.0 }
				
				isUploading.withLock { $0 = false }
				Logger.services.info("[ESP OTA] Writer Task: All data sent.")
			}
			
			// TASK B: Reader (Processes ACKs and OK)
			group.addTask {
				var finished = false
				while !finished {
					try Task.checkCancellation()
					
					let currentPhaseIsUploading = isUploading.withLock { $0 }
					let timeoutDuration = currentPhaseIsUploading ? self.packetTimeout : self.finalVerifyTimeout
					
					if !currentPhaseIsUploading {
						 await self.updateUI { self.statusMessage = "Verifying..." }
					}

					let line: String
					do {
						 line = try await self.withTimeout(seconds: timeoutDuration) {
							try await reader.readLine()
						}
					} catch {
						Logger.services.error("[ESP OTA] Read Timeout. Cancelling connection.")
						connection.cancel()
						throw OTAError.timeout
					}
					
					let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
					
					if trimmed == "OK" {
						finished = true
					} else if trimmed == "ACK" {
						continue
					} else if trimmed.isEmpty {
						continue
					} else {
						connection.cancel()
						throw OTAError.unexpectedResponse(trimmed)
					}
				}
			}
			
			try await group.waitForAll()
		}
		
		connection.cancel()
	}
	
	// MARK: - Helpers
	
	private func waitForManualHostReboot(endpoint: NWEndpoint) async throws {
		let deadline = Date().addingTimeInterval(connectionTimeout)
		while Date() < deadline {
			if await probeTcpConnection(endpoint: endpoint) { return }
			try await Task.sleep(for: .seconds(1))
		}
		throw OTAError.timeout
	}
	
	private func probeTcpConnection(endpoint: NWEndpoint) async -> Bool {
		let connection = NWConnection(to: endpoint, using: .tcp)
		return await withCheckedContinuation { continuation in
			var hasResumed = false
			connection.stateUpdateHandler = { state in
				if hasResumed { return }
				switch state {
				case .ready:
					hasResumed = true
					connection.cancel()
					continuation.resume(returning: true)
				case .failed(_), .waiting(_):
					hasResumed = true
					connection.cancel()
					continuation.resume(returning: false)
				default: break
				}
			}
			connection.start(queue: .global())
		}
	}
	
	private func discoverDevice() async throws -> NWEndpoint {
		let parameters = NWParameters.udp
		parameters.allowLocalEndpointReuse = true
		let listener = try NWListener(using: parameters, on: port)
		
		return try await withCheckedThrowingContinuation { continuation in
			let hasResumed = OSAllocatedUnfairLock(initialState: false)
			listener.newConnectionHandler = { newConnection in
				newConnection.start(queue: .global())
				newConnection.receiveMessage { data, context, isComplete, error in
					if let data = data, let message = String(data: data, encoding: .utf8) {
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
	
	private func updateUI(_ block: @MainActor @Sendable () -> Void) async {
		await MainActor.run { block() }
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
	
	nonisolated private func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
		return try await withThrowingTaskGroup(of: T.self) { group in
			group.addTask { return try await operation() }
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
				throw OTAError.timeout
			}
			let result = try await group.next()!
			group.cancelAll()
			return result
		}
	}
}

// MARK: - Async Buffered Reader (Corrected for Deadlocks)
actor AsyncLineReader {
	private let connection: NWConnection
	private var buffer = Data()
	
	init(connection: NWConnection) {
		self.connection = connection
	}
	
	func readLine() async throws -> String {
		while true {
			try Task.checkCancellation()
			if let range = buffer.range(of: Data([0x0A])) { // \n
				let lineData = buffer.subdata(in: 0..<range.lowerBound)
				buffer.removeSubrange(0..<range.upperBound)
				return String(data: lineData, encoding: .utf8) ?? ""
			}
			let incoming = try await receiveNextChunk()
			buffer.append(incoming)
		}
	}
	
	private func receiveNextChunk() async throws -> Data {
		// We use a Lock to hold the continuation so the cancellation handler
		// can force-resume it if the network stack hangs.
		let lock = OSAllocatedUnfairLock<CheckedContinuation<Data, Error>?>(initialState: nil)
		
		return try await withTaskCancellationHandler {
			return try await withCheckedThrowingContinuation { continuation in
				lock.withLock { $0 = continuation }
				
				// MARK: - FIX for Deadlock
				// If `onCancel` ran before we set the lock (race condition), `Task.isCancelled`
				// will be true here. We must abort immediately.
				if Task.isCancelled {
					lock.withLock { state in
						guard let cont = state else { return }
						state = nil
						cont.resume(throwing: CancellationError())
					}
					return
				}
				
				connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
					lock.withLock { state in
						guard let cont = state else { return } // Already cancelled/resumed
						state = nil
						
						if let error = error {
							cont.resume(throwing: error)
						} else if let data = data {
							cont.resume(returning: data)
						} else {
							cont.resume(throwing: OTAError.connectionFailed)
						}
					}
				}
			}
		} onCancel: {
			connection.cancel()
			
			// Force resume the continuation to unblock 'await'
			lock.withLock { state in
				guard let cont = state else { return }
				state = nil
				cont.resume(throwing: CancellationError())
			}
		}
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
		case .timeout: return "Device stopped responding."
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
