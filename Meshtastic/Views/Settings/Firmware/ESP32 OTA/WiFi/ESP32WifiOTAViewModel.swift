import Foundation
import Network
import CryptoKit
import Combine
import OSLog
import os // Required for OSAllocatedUnfairLock

@MainActor
class ESP32WifiOTAViewModel: ObservableObject {
	
	// MARK: - Published State
	@Published var statusMessage: String = "Idle"
	@Published var progress: Double = 0.0
	@Published var errorMessage: String?
	@Published var otaState: LocalOTAStatusCode = .idle
	
	// MARK: - Constants
	private let espPort: NWEndpoint.Port = 3232
	private let chunkSize = 1460
	private let retryDelay: TimeInterval = 2.0
	private let handshakeTotalTimeout: TimeInterval = 30.0
	
	private var transferContinuation: AsyncThrowingStream<Void, Error>.Continuation?
	
	// MARK: - Public Interface
	
	/// Starts the OTA update process with the given host, firmware URL, and optional password.
	func startUpdate(host: String, firmwareUrl: URL, password: String? = nil) async {
		guard otaState == .idle else { return }
		
		progress = 0.0
		errorMessage = nil
		statusMessage = "Connecting..."
		otaState = .waitingForConnection
		
		do {
			let firmwareData = try Data(contentsOf: firmwareUrl)
			
			let transferStream = AsyncThrowingStream<Void, Error> { continuation in
				self.transferContinuation = continuation
			}
			
			Logger.services.info("[ESP OTA] Starting local TCP Listener...")
			let (listener, localPort) = try await setupListener(sending: firmwareData)
			Logger.services.info("[ESP OTA] Listening on port \(localPort)")
			
			// Ensure listener is cancelled on exit (success or failure)
			defer { listener.cancel() }
			
			statusMessage = "Waiting for device. This can take a while..."
			
			Logger.services.info("[ESP OTA] Starting Handshake loop...")
			try await performHandshake(host: host, localPort: localPort, data: firmwareData, password: password)
			
			otaState = .connected
			for try await _ in transferStream { break }
			
			statusMessage = "Success!"
			otaState = .completed
			Logger.services.info("[ESP OTA] Update Complete")
			
		} catch {
			Logger.services.error("[ESP OTA] Error: \(error.localizedDescription)")
			errorMessage = error.localizedDescription
			statusMessage = "Failed"
			otaState = .error
			transferContinuation?.finish(throwing: error)
			transferContinuation = nil
		}
	}
	
	// MARK: - Handshake Logic
	
	private actor HandshakeState {
		var currentPayload: Data
		var okReceived: Bool = false
		
		init(initialPayload: Data) {
			self.currentPayload = initialPayload
		}
		
		func updatePayload(_ data: Data) {
			currentPayload = data
		}
		
		func getPayload() -> Data {
			currentPayload
		}
		
		func markOkReceived() {
			okReceived = true
		}
		
		func isOkReceived() -> Bool {
			okReceived
		}
	}
	
	/// Performs the UDP handshake with the ESP32 device.
	private func performHandshake(host: String, localPort: UInt16, data: Data, password: String?) async throws {
		let initialPayload = try generateInvitationPayload(localPort: localPort, data: data, password: password, authNonce: nil)
		let state = HandshakeState(initialPayload: initialPayload)
		
		let nwHost = NWEndpoint.Host(host)
		let connection = NWConnection(host: nwHost, port: espPort, using: .udp)
		defer { connection.cancel() }
		
		connection.start(queue: .global())
		try await waitForConnectionReady(connection)
		
		Logger.services.info("[ESP OTA] UDP Connection Ready. Starting broadcast/listen loop.")
		
		try await withThrowingTaskGroup(of: Void.self) { group in
			// Task A: Broadcaster
			group.addTask {
				var okReceived = await state.isOkReceived()
				while !Task.isCancelled && !okReceived {
					let payload = await state.getPayload()
					try await connection.sendAsync(data: payload)
					Logger.services.debug("[ESP OTA] Sent invitation packet")
					try await Task.sleep(for: .seconds(self.retryDelay))
					okReceived = await state.isOkReceived()
				}
			}
			
			// Task B: Listener (using async stream for messages)
			group.addTask {
				let messageStream = self.receiveMessageStream(from: connection)
				for try await response in messageStream {
					if Task.isCancelled { break }
					
					if response == "OK" {
						Logger.services.info("[ESP OTA] Handshake OK received!")
						await state.markOkReceived()
						return
					}
					
					if response.hasPrefix("AUTH") {
						Logger.services.info("[ESP OTA] Auth challenge received: \(response)")
						let components = response.components(separatedBy: " ")
						if components.count > 1 {
							let nonce = components[1]
							let newPayload = try self.generateInvitationPayload(localPort: localPort, data: data, password: password, authNonce: nonce)
							await state.updatePayload(newPayload)
						}
					}
					
					if response == "ERASE" {
						Logger.services.info("[ESP OTA] Device is erasing the flash partition.")
						await self.updateUI { // Safe MainActor update
							self.otaState = .preparing
							self.statusMessage = "Preparing flash partition..."
						}
					}
				}
			}
			
			// Task C: Timeout
			group.addTask {
				try await Task.sleep(for: .seconds(self.handshakeTotalTimeout))
				throw OTAError.timeout
			}
			
			try await group.next() // Wait for first completion (success or error)
			group.cancelAll() // Cancel remaining tasks
		}
	}
	
	// MARK: - UDP Helpers
	
	/// Creates an async stream of incoming UDP messages.
	nonisolated private func receiveMessageStream(from connection: NWConnection) -> AsyncThrowingStream<String, Error> {
		AsyncThrowingStream<String, Error> { continuation in
			func receiveNext() {
				connection.receiveMessage { content, _, _, error in
					if let error = error {
						continuation.finish(throwing: error)
						return
					}
					if let data = content, let str = String(data: data, encoding: .utf8) {
						continuation.yield(str.trimmingCharacters(in: .whitespacesAndNewlines))
					}
					if !Task.isCancelled {
						receiveNext() // Recurse to continue streaming
					} else {
						continuation.finish()
					}
				}
			}
			receiveNext()
			
			continuation.onTermination = { _ in
				connection.cancel()
			}
		}
	}
	
	nonisolated private func generateInvitationPayload(localPort: UInt16, data: Data, password: String?, authNonce: String?) throws -> Data {
		let sha256Digest = SHA256.hash(data: data)
		let fileHash = sha256Digest.map { String(format: "%02hhx", $0) }.joined()
		
		Logger.services.info("Firmware SHA-256 is \(fileHash)")
		let fileSize = data.count
		var message = "0 \(localPort) \(fileSize) \(fileHash)"
		
		if let nonce = authNonce, let pass = password {
			let authInput = pass + nonce
			if let authData = authInput.data(using: .utf8) {
				let authSha256 = SHA256.hash(data: authData)
				let authFirst16 = Data(authSha256.prefix(16))
				let authHash = authFirst16.map { String(format: "%02hhx", $0) }.joined()
				message += " " + authHash
			}
		}
		
		guard let payload = message.data(using: .utf8) else { throw OTAError.encodingFailed }
		return payload
	}
	
	/// Waits for the connection to become ready using a continuation with lock for safety.
	nonisolated private func waitForConnectionReady(_ connection: NWConnection) async throws {
		try await withCheckedThrowingContinuation { continuation in
			// Ensure we only resume the continuation once
			var didResume = false

			connection.stateUpdateHandler = { state in
				// Guard against multiple resumes due to multiple state updates
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
				default:
					break
				}
			}
		}
	}
	
	// MARK: - Listener & Transfer Logic
	
	/// Sets up the TCP listener and returns it along with the assigned port.
	private func setupListener(sending firmware: Data) async throws -> (NWListener, UInt16) {
		let parameters = NWParameters(tls: nil)
		parameters.includePeerToPeer = true
		parameters.prohibitedInterfaceTypes = [.cellular]
		
		let listener = try NWListener(using: parameters, on: .init(integerLiteral: 0))
		
		return try await withCheckedThrowingContinuation<(NWListener, UInt16)> { continuation in
			let stateLock = OSAllocatedUnfairLock<Bool>(initialState: false)
			
			// Set newConnectionHandler before starting (matches original to avoid timing issues)
			listener.newConnectionHandler = { newConnection in
				Logger.services.info("[ESP OTA] Accepted connection from \(String(describing: newConnection.endpoint))")
				Task { @MainActor in
					self.handleIncomingConnection(connection: newConnection, data: firmware)
					newConnection.start(queue: .global())  // Start here as in original
				}
			}
			
			listener.stateUpdateHandler = { state in
				stateLock.withLock { isHandled in
					if isHandled { return }
					isHandled = true
					
					switch state {
					case .ready:
						Logger.services.debug("[ESP OTA] Listener ready with port: \(String(describing: listener.port?.rawValue ?? 0))")
						if let port = listener.port {
							continuation.resume(returning: (listener, port.rawValue))
						} else {
							continuation.resume(throwing: OTAError.connectionFailed)
						}
					case .failed(let error):
						Logger.services.error("[ESP OTA] Listener failed: \(error)")
						continuation.resume(throwing: error)
					default:
						Logger.services.debug("[ESP OTA] Listener state: \(String(describing: state))")
						break
					}
				}
			}
			listener.start(queue: .global())
		}
	}
	
	/// Handles an incoming TCP connection for firmware transfer.
	private func handleIncomingConnection(connection: NWConnection, data: Data) {
		connection.stateUpdateHandler = { state in
			switch state {
			case .ready:
				Task { @MainActor in
					self.otaState = .transferring
					do {
						try await self.performChunkedTransfer(connection: connection, data: data)
						self.transferContinuation?.yield()
						self.transferContinuation?.finish()
					} catch {
						self.transferContinuation?.finish(throwing: error)
					}
					self.transferContinuation = nil
					connection.cancel()
				}
			case .failed(let error):
				Task { @MainActor in
					self.transferContinuation?.finish(throwing: error)
					self.transferContinuation = nil
				}
			default: break
			}
		}
	}
	
	/// Performs the chunked TCP transfer of firmware data.
	nonisolated private func performChunkedTransfer(connection: NWConnection, data: Data) async throws {
		var offset = 0
		let totalSize = data.count
		
		while offset < totalSize && !Task.isCancelled {
			let endIndex = min(offset + chunkSize, totalSize)
			let chunk = data[offset..<endIndex]
			try await connection.sendAsync(data: chunk)
			
			offset += chunk.count
			let percent = Double(offset) / Double(totalSize)
			
			// Batch progress updates every 10 chunks to avoid excessive MainActor hops
			if offset % (chunkSize * 10) == 0 {
				await updateUI {
					self.progress = percent
					self.statusMessage = "Please stay on this screen while update completes..."
				}
			}
		}
		
		await updateUI {
			self.progress = 1.0
			self.statusMessage = "Done..."
		}
		
		try await Task.sleep(for: .seconds(3))
	}
	
	// MARK: - UI Update Helper
	
	/// Safely updates UI properties on MainActor.
	private func updateUI(_ block: @MainActor @Sendable () -> Void) async {
		await MainActor.run { block() }
	}
}

// MARK: - Extensions

enum OTAError: Error, LocalizedError {
	case encodingFailed
	case connectionFailed
	case unexpectedResponse(String)
	case authFailed
	case timeout
	
	var errorDescription: String? {
		switch self {
		case .timeout: return "ESP32 failed to respond in time."
		case .connectionFailed: return "Failed to establish connection."
		case .unexpectedResponse(let r): return "Unexpected response: \(r)"
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

