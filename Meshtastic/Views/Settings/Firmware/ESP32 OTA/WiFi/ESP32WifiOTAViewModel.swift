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
	
	func startUpdate(host: String, firmwareUrl: URL, password: String? = nil) async {
		guard self.otaState == .idle else { return }
		
		self.progress = 0.0
		self.errorMessage = nil
		self.statusMessage = "Connecting..."
		self.otaState = .waitingForConnection
		
		var listener: NWListener?
		
		defer {
			listener?.cancel()
			self.otaState = .idle
		}
		
		do {
			let firmwareData = try Data(contentsOf: firmwareUrl)
			
			let transferStream = AsyncThrowingStream<Void, Error> { continuation in
				self.transferContinuation = continuation
			}
			
			Logger.services.info("[ESP OTA] Starting local TCP Listener...")
			let (setupListener, localPort) = try await setupListener(sending: firmwareData)
			listener = setupListener
			Logger.services.info("[ESP OTA] Listening on port \(localPort)")
			
			self.statusMessage = "Waiting for device.  This can take a while..."
			
			Logger.services.info("[ESP OTA] Starting Handshake loop...")
			
			try await performHandshake(host: host,
									   localPort: localPort,
									   data: firmwareData,
									   password: password)
			
			self.otaState = .connected
			for try await _ in transferStream { break }
			
			self.statusMessage = "Success!"
			self.otaState = .completed
			Logger.services.info("[ESP OTA] Update Complete")
			
		} catch {
			Logger.services.error("[ESP OTA] Error: \(error.localizedDescription)")
			self.errorMessage = error.localizedDescription
			self.statusMessage = "Failed"
			self.otaState = .error
			self.transferContinuation?.finish(throwing: error)
			self.transferContinuation = nil
		}
	}
	
	// MARK: - Phase 2: Handshake Logic
	
	private actor HandshakeState {
		var currentPayload: Data
		init(initialPayload: Data) { self.currentPayload = initialPayload }
		func updatePayload(_ data: Data) { self.currentPayload = data }
		func getPayload() -> Data { return currentPayload }
	}
	
	private func performHandshake(host: String, localPort: UInt16, data: Data, password: String?) async throws {
		let initialPayload = try generateInvitationPayload(localPort: localPort, data: data, password: password, authNonce: nil)
		let state = HandshakeState(initialPayload: initialPayload)
		
		let nwHost = NWEndpoint.Host(host)
		let connection = NWConnection(host: nwHost, port: espPort, using: .udp)
		defer { connection.cancel() }
		
		connection.start(queue: .global())
		try await waitForConnectionReady(connection)
		
		Logger.services.info("[ESP OTA] UDP Connection Ready. Starting broadcast/listen loop.")
		
		var okReceived = false
		try await withThrowingTaskGroup(of: Void.self) { group in
			// Task A: Broadcaster
			group.addTask {
				while !Task.isCancelled, !okReceived {
					let payload = await state.getPayload()
					connection.send(content: payload, completion: .contentProcessed { _ in })
					Logger.services.debug("[ESP OTA] Sent invitation packet")
					try await Task.sleep(nanoseconds: UInt64(self.retryDelay * 1_000_000_000))
				}
			}
			
			// Task B: Listener
			group.addTask {
				while !Task.isCancelled {
					let response = try await self.receiveNextMessage(connection: connection)
					
					if response == "OK" {
						Logger.services.info("[ESP OTA] Handshake OK received!")
						okReceived = true
						return
					}
					
					// THIS IS UNTESTED
					if response.hasPrefix("AUTH") {
						Logger.services.info("[ESP OTA] Auth challenge received: \(response)")
						let components = response.components(separatedBy: " ")
						if components.count > 1 {
							let nonce = components[1]
							let newPayload = try self.generateInvitationPayload(localPort: localPort,
																				data: data,
																				password: password,
																				authNonce: nonce)
							await state.updatePayload(newPayload)
						}
					}
					
					if response == "ERASE" {
						Logger.services.info("[ESP OTA] Device is erasing the flash partition.")
						Task { @MainActor in
							self.otaState = .preparing
							self.statusMessage = "Preparing flash partition..."
						}
					}
				}
			}
			
			// Task C: Timeout
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(self.handshakeTotalTimeout * 1_000_000_000))
				throw OTAError.timeout
			}
			
			try await group.next()
			group.cancelAll()
		}
	}
	
	// MARK: - UDP Helpers (Nonisolated)
	
	nonisolated private func receiveNextMessage(connection: NWConnection) async throws -> String {
		return try await withCheckedThrowingContinuation { continuation in
			connection.receiveMessage { content, _, _, error in
				if let error = error {
					continuation.resume(throwing: error)
				} else if let data = content, let str = String(data: data, encoding: .utf8) {
					continuation.resume(returning: str.trimmingCharacters(in: .whitespacesAndNewlines))
				} else {
					continuation.resume(returning: "")
				}
			}
		}
	}
	
	nonisolated private func generateInvitationPayload(localPort: UInt16, data: Data, password: String?, authNonce: String?) throws -> Data {
		let fileMD5 = Insecure.MD5.hash(data: data).map { String(format: "%02hhx", $0) }.joined()
		Logger.services.info("Firmware MD5 is \(fileMD5)")
		let fileSize = data.count
		var message = "0 \(localPort) \(fileSize) \(fileMD5)"
		
		if let nonce = authNonce, let pass = password {
			let authInput = pass + nonce
			if let authData = authInput.data(using: .utf8) {
				let authHash = Insecure.MD5.hash(data: authData).map { String(format: "%02hhx", $0) }.joined()
				message += " " + authHash
			}
		}
		
		guard let payload = message.data(using: .utf8) else { throw OTAError.encodingFailed }
		return payload
	}
	
	/// Uses OSAllocatedUnfairLock to safely ensure resume is called exactly once
	nonisolated private func waitForConnectionReady(_ connection: NWConnection) async throws {
		return try await withCheckedThrowingContinuation { continuation in
			let stateLock = OSAllocatedUnfairLock(initialState: false) // The Idiomatic Swift 6 Lock
			
			connection.stateUpdateHandler = { state in
				// We lock, check if we already resumed, set to true, and perform logic
				stateLock.withLock { hasResumed in
					if hasResumed { return }
					
					switch state {
					case .ready:
						hasResumed = true
						continuation.resume()
					case .failed(let err):
						hasResumed = true
						continuation.resume(throwing: err)
					case .cancelled:
						hasResumed = true
						continuation.resume(throwing: CancellationError())
					default:
						break
					}
				}
			}
		}
	}
	
	// MARK: - Phase 1 & 4 (Listener & Transfer)
	
	private func setupListener(sending firmware: Data) async throws -> (NWListener, UInt16) {
		let parameters = NWParameters(tls: nil)
		parameters.includePeerToPeer = true
		parameters.prohibitedInterfaceTypes = [.cellular]
		
		let listener = try NWListener(using: parameters, on: .init(integerLiteral: 0))
		
		return try await withCheckedThrowingContinuation { continuation in
			let stateLock = OSAllocatedUnfairLock(initialState: false)
			
			listener.newConnectionHandler = { newConnection in
				Logger.services.info("[ESP OTA] Accepted connection from \(String(describing: newConnection.endpoint))")
				Task { @MainActor in
					self.handleIncomingConnection(connection: newConnection, data: firmware)
					newConnection.start(queue: .global())
				}
			}
			
			listener.stateUpdateHandler = { state in
				stateLock.withLock { hasResumed in
					if hasResumed { return }
					
					switch state {
					case .ready:
						if let port = listener.port {
							hasResumed = true
							continuation.resume(returning: (listener, port.rawValue))
						}
					case .failed(let error):
						hasResumed = true
						continuation.resume(throwing: error)
					default:
						break
					}
				}
			}
			listener.start(queue: .global())
		}
	}
	
	private func handleIncomingConnection(connection: NWConnection, data: Data) {
		connection.stateUpdateHandler = { state in
			switch state {
			case .ready:
				Task { @MainActor in
					self.otaState = .transferring
					do {
						try await self.performChunkedTransfer(connection: connection, data: data)
						await MainActor.run {
							self.transferContinuation?.yield()
							self.transferContinuation?.finish()
							self.transferContinuation = nil
						}
					} catch {
						await MainActor.run {
							self.transferContinuation?.finish(throwing: error)
							self.transferContinuation = nil
						}
					}
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
	
	nonisolated private func performChunkedTransfer(connection: NWConnection, data: Data) async throws {
		var offset = 0
		let totalSize = data.count
		
		while offset < totalSize {
			let endIndex = min(offset + chunkSize, totalSize)
			let chunk = data[offset..<endIndex]
			try await connection.sendAsync(data: chunk)
			
			offset += chunk.count
			let percent = Double(offset) / Double(totalSize)
			
			if offset % (chunkSize * 10) == 0 {
				await MainActor.run {
					self.progress = percent
					self.statusMessage = "Please stay on this screen while update completes..."
				}
			}
		}
		
		await MainActor.run {
			self.progress = 1.0
			self.statusMessage = "Done..."
		}
		
		try await Task.sleep(nanoseconds: 3_000_000_000)
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
		return try await withCheckedThrowingContinuation { continuation in
			self.send(content: data, completion: .contentProcessed { error in
				if let error = error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}
}
