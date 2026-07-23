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
		// The framing loop does many tiny socket reads — `waitForMagicBytes()` reads a
		// single byte at a time — and the previous `@MainActor` isolation forced a
		// main-thread hop for every one of those reads and continuation resumptions. At
		// high packet rates that saturated the main runloop, starving Core Animation
		// (QuartzCore "cannot add handler … dropping") and on iOS stalling the TCP
		// receive drain enough for the OS to drop the connection (ECONNRESET).
		//
		// Reading on a detached task moves all of that work off the main actor. Packet
		// ordering into AccessoryManager is still preserved: this is the single producer
		// for `connectionStreamContinuation`, it yields frames serially in read order, and
		// AsyncStream delivers them FIFO to the lone consumer — so no @MainActor pinning is
		// needed to keep packets in order.
		readerTask = Task.detached { [self] in
			while await isConnected {
				do {
					if try await waitForMagicBytes() == false {
						Logger.transport.debug("🌐 [TCP] startReader: EOF while waiting for magic bytes")
						continue
					}
					// Logger.transport.debug("[TCP] startReader: Found magic byte, waiting for length")

					if let length = try? await readInteger() {
						let payload = try await receiveData(min: Int(length), max: Int(length))
						switch FromRadioDecoder.classify(payload) {
						case .decoded(let fromRadio):
							await self.yieldDataEvent(fromRadio)
						case .skipInvalidUTF8(let error):
							// A string field failed UTF-8 validation; skip this frame and keep reading
							// rather than tearing down an otherwise healthy connection over one
							// unparseable field. receiveData(min:max:) already consumed exactly `length`
							// bytes, so the stream stays magic-byte aligned for the next frame.
							Logger.transport.error("🌐 [TCP] Skipping FromRadio frame with invalid UTF-8 (\(payload.count) bytes): \(error, privacy: .public)")
						case .failed(let error):
							// Genuine framing/stream corruption — disconnect and allow reconnect recovery.
							Logger.transport.error("🌐 [TCP] FromRadio decode failed (framing/stream corruption): \(error, privacy: .public)")
							try await self.disconnect(withError: error, shouldReconnect: true)
						}
					} else {
						Logger.transport.debug("🌐 [TCP] startReader: EOF while waiting for length")
					}
				} catch {
					// An intentional teardown cancels this task (and the NWConnection), which surfaces
					// here as a receive error. Do NOT treat that as a reconnectable failure — the
					// explicit `disconnect(shouldReconnect:)` call that cancelled us already yielded the
					// correct event. Emitting `.error(shouldReconnect: true)` here races that intent and
					// can trigger an auto-reconnect right after a user-initiated disconnect (the timing
					// varies by OS — observed on iOS 18). Only a genuine, un-cancelled read error should
					// request a reconnect.
					if Task.isCancelled { break }
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

	/// Yields into a full stream buffer since connect (see `getPacketStream`). With
	/// `.bufferingNewest` each such yield evicts the oldest buffered frame, so this counts
	/// evictions to within ±1 (the yield that exactly fills the buffer also reports 0 remaining).
	private var saturatedYieldCount = 0

	/// Yields a decoded frame into the event stream, counting full-buffer yields so sustained
	/// backpressure is visible in the logs instead of silent. `.bufferingNewest` never reports
	/// `.dropped` — the NEW element is always enqueued and the OLDEST is evicted — so a full
	/// buffer surfaces as `.enqueued(remaining: 0)`.
	private func yieldDataEvent(_ fromRadio: FromRadio) {
		guard let continuation = connectionStreamContinuation else { return }
		if case .enqueued(let remaining) = continuation.yield(.data(fromRadio)), remaining == 0 {
			saturatedYieldCount += 1
			if saturatedYieldCount == 1 || saturatedYieldCount % 1_000 == 0 {
				Logger.transport.warning("🌊 [TCP] Event buffer full — oldest frames are being evicted (\(self.saturatedYieldCount) saturated yields this session); consumer is behind the radio's packet rate")
			}
		}
	}

	private func getPacketStream() -> AsyncStream<ConnectionEvent> {
		self.connectionStreamContinuation?.finish()
		self.connectionStreamContinuation = nil

		// Bounded buffer: the default unbounded policy let a fast producer (a TCP radio can
		// sustain >100 packets/s) queue every frame the main-actor consumer hadn't processed
		// yet — under a stress replay that backlog reached ~all packets of the session, holding
		// their protobufs live (multi-hundred-MB) while the app fell minutes behind real time.
		// Keeping the newest 4,096 events drops the OLDEST first under sustained overload —
		// stale mesh traffic, exactly what a saturated real radio would shed — while a node-DB
		// dump (one event per node) fits well inside the bound, and error/teardown events are
		// always the newest when they occur.
		return AsyncStream<ConnectionEvent>(bufferingPolicy: .bufferingNewest(4096)) { continuation in
			self.connectionStreamContinuation = continuation
			continuation.onTermination = { [weak self] termination in
				guard let self else { return }
				guard case .cancelled = termination else { return }
				Task {
					try await self.disconnect(withError: AccessoryError.eventStreamCancelled, shouldReconnect: true)
				}
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
