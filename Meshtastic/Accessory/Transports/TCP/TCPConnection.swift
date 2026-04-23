//
//  TCPConnection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/19/25.
//

import Foundation
import Network
import OSLog
import MeshtasticProtobufs

actor TCPConnection: Connection {
	let type = TransportType.tcp
	
	private var connection: NWConnection?
	private let queue = DispatchQueue(label: "tcp.connection")
	private var readerTask: Task<Void, Never>?
	private let nwHost: NWEndpoint.Host
	private let nwPort: NWEndpoint.Port
	
	private var connectionStreamContinuation: AsyncStream<ConnectionEvent>.Continuation?
	
	var isConnected: Bool {
		connection?.state == .ready
	}

	init(host: String, port: Int) async throws {
		self.nwHost = NWEndpoint.Host(host)
		self.nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
	}
	
	var host: NWEndpoint.Host {
		return nwHost
	}

	private func waitForMagicBytes() async throws -> Bool {
		let startOfFrame: [UInt8] = [0x94, 0xc3]
		var waitingOnByte = 0
		while true {
			let data = try await receiveData(min: 1, max: 1)
			if data.count != 1 {
				// End of stream
				return false
			}

			if data[0] == startOfFrame[waitingOnByte] {
				waitingOnByte += 1
			} else {
				waitingOnByte = 0
			}

			if waitingOnByte > 1 {
				return true
			}
		}
	}

	private func readInteger() async throws -> UInt16? {
		let data = try await receiveData(min: 2, max: 2)
		if data.count == 2 {
			let value = data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
			return value
		}
		return nil
	}

	private func startReader() {
		// TODO: @MainActor here because packets come into AccessoryManager out of order otherwise.  Need to figure out the concurrency
		readerTask = Task { @MainActor in
			while await isConnected {
				do {
					if try await waitForMagicBytes() == false {
						Logger.transport.debug("🌐 [TCP] startReader: EOF while waiting for magic bytes")
						continue
					}
					// Logger.transport.debug("[TCP] startReader: Found magic byte, waiting for length")

					if let length = try? await readInteger() {
						let payload = try await receiveData(min: Int(length), max: Int(length))
						if let fromRadio = try? FromRadio(serializedBytes: payload) {
							await connectionStreamContinuation?.yield(.data(fromRadio))
						} else {
							try await self.disconnect(withError: AccessoryError.disconnected("Network connection dropped"), shouldReconnect: true)
						}
					} else {
						Logger.transport.debug("🌐 [TCP] startReader: EOF while waiting for length")
					}
				} catch {
					Logger.transport.error("🌐 [TCP] startReader: Error reading from TCP: \(error, privacy: .public)")
					try? await self.disconnect(withError: error, shouldReconnect: true)
					break
				}
			}
			// Logger.services.error("End of TCP reading task: isConnected:\(self.isConnected)")
		}
	}

	private func receiveData(min: Int, max: Int) async throws -> Data {
		let capturedConnection = connection
		return try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { cont in
				connection?.receive(minimumIncompleteLength: min, maximumLength: max) { content, _, isComplete, error in
					if let error = error {
						cont.resume(throwing: error)
						return
					}
					if isComplete {
						// cont.resume(returning: Data())
						cont.resume(throwing: AccessoryError.disconnected("Error while receiving data"))
						return
					}
					if let content {
						cont.resume(returning: content)
					} else {
						cont.resume(returning: Data())
					}
				}
			}
		} onCancel: {
			// ✨ onCancel cannot directly resume the continuation (it doesn’t know if it’s already been resumed).
			// A safe pattern is to cancel the underlying NWConnection. That forces the receive completion
			// handler to fire with an error, where you can safely resume the continuation.
			capturedConnection?.cancel()
		}
	}

	func send(_ data: ToRadio) async throws {
		let serialized = try data.serializedData()
		var buffer = Data()
		buffer.append(0x94)
		buffer.append(0xc3)
		var len = UInt16(serialized.count).bigEndian
		withUnsafeBytes(of: &len) { buffer.append(contentsOf: $0) }
		buffer.append(serialized)

		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			connection?.send(content: buffer, completion: .contentProcessed { error in
				if let error = error {
					cont.resume(throwing: error)
				} else {
					cont.resume()
				}
			})
		}
	}
	
	func disconnect(withError error: Error? = nil, shouldReconnect: Bool) throws {
		Logger.transport.debug("🌐 [TCP] Disconnecting from TCP connection")
		readerTask?.cancel()
		readerTask = nil
		
		connection?.cancel()
		connection = nil
		
		if let error {
			// Inform the AccessoryManager of the error and intent to reconnect
			if shouldReconnect {
				connectionStreamContinuation?.yield(.error(error))
			} else {
				connectionStreamContinuation?.yield(.errorWithoutReconnect(error))
			}
		} else {
			connectionStreamContinuation?.yield(.disconnected(shouldReconnect: shouldReconnect))
		}
		
		connectionStreamContinuation?.finish()
		connectionStreamContinuation = nil
	}

	func drainPendingPackets() async throws {
		// For TCP, since reader is always running, no need to drain separately
	}

	func startDrainPendingPackets() throws {
		// For TCP, reader is already started
	}

	private func getPacketStream() -> AsyncStream<ConnectionEvent> {
		AsyncStream<ConnectionEvent> { continuation in
			self.connectionStreamContinuation = continuation
			continuation.onTermination = { _ in
				Task { try await self.disconnect(withError: AccessoryError.eventStreamCancelled, shouldReconnect: true) }
			}
		}
	}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		let newConnection = NWConnection(host: nwHost, port: nwPort, using: .tcp)
		self.connection = newConnection
			
		try await withTaskCancellationHandler {
				try await withCheckedThrowingContinuation { cont in
					newConnection.stateUpdateHandler = { state in
						switch state {
						case .ready:
							cont.resume()
						case .failed(let error):
							cont.resume(throwing: error)
						case .cancelled:
							cont.resume(throwing: CancellationError())
						default:
							break
						}
					}
					newConnection.start(queue: queue)
				}
			} onCancel: {
				newConnection.cancel()
			}
		
		// We've gotten here past the connection and since we haven't thrown, the
		// connection is in the ready state.
		
		// Update the state connection handler for in-progress monitoring of state
		// changes while connected.
		newConnection.stateUpdateHandler = { state in
				switch state {
				case .failed(let error):
					Logger.transport.error("🌐 [TCP] Connection failed after ready: \(error, privacy: .public)")
					Task {
						try? await self.disconnect(withError: error, shouldReconnect: true)
					}
				case .cancelled:
					Logger.transport.debug("🌐 [TCP] Connection cancelled")
				default:
					break
				}
			}
		
		startReader()
		return getPacketStream()
		
	}

	func appDidEnterBackground() {
		
	}
	
	func appDidBecomeActive() {
		
	}
}
