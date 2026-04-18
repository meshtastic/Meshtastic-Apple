//
//  TAKConnection.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import Network
import OSLog

/// Actor managing a single TAK client TLS connection
/// Handles CoT XML streaming protocol (messages delimited by </event>)
/// Implements TAK Protocol negotiation and keepalive
actor TAKConnection {
	private let connection: NWConnection
	private var messageBuffer = Data()
	private var readerTask: Task<Void, Never>?
	private var keepaliveTask: Task<Void, Never>?
	private var continuation: AsyncStream<TAKConnectionEvent>.Continuation?

	// CoT XML message delimiters (from StreamingCotProtocol.java)
	private let startTag = "<event".data(using: .utf8)!
	private let endTag = "</event>".data(using: .utf8)!
	private let maxMessageSize = 8_388_608  // 8MB max per TAK Server spec

	// Protocol state
	private var protocolNegotiated = false
	private let serverUID = "Meshtastic-TAK-Server-\(UUID().uuidString.prefix(8))"

	// Keepalive interval (30 seconds)
	private let keepaliveInterval: UInt64 = 30_000_000_000  // nanoseconds

	// Client information
	private(set) var clientInfo: TAKClientInfo?
	private(set) var isConnected = false

	var endpoint: NWEndpoint {
		connection.endpoint
	}

	init(connection: NWConnection) {
		self.connection = connection
	}

	/// Start handling the connection and return an event stream
	func start() -> AsyncStream<TAKConnectionEvent> {
		AsyncStream { continuation in
			self.continuation = continuation

			continuation.onTermination = { [weak self] _ in
				Task { [weak self] in
					await self?.disconnect()
				}
			}

			// Set up state handler
			connection.stateUpdateHandler = { [weak self] state in
				guard let self else { return }
				Task {
					await self.handleStateChange(state)
				}
			}

			// Start the connection
			connection.start(queue: DispatchQueue(label: "tak.connection.\(UUID().uuidString)"))
		}
	}

	/// Handle connection state changes
	private func handleStateChange(_ state: NWConnection.State) {
		switch state {
		case .ready:
			isConnected = true
			Logger.tak.info("TAK client connected: \(self.connection.endpoint.debugDescription)")

			// Extract client certificate info if available
			extractClientInfo()

			// Notify connected
			let info = clientInfo ?? TAKClientInfo(endpoint: connection.endpoint, connectedAt: Date())
			continuation?.yield(.connected(info))

			// Send protocol support advertisement
			Task {
				await sendProtocolSupport()
			}

			// Start reading data
			startReading()

			// Start keepalive task
			startKeepalive()

		case .failed(let error):
			Logger.tak.error("TAK connection failed: \(error.localizedDescription)")
			isConnected = false
			continuation?.yield(.error(error))
			continuation?.yield(.disconnected)
			continuation?.finish()

		case .cancelled:
			Logger.tak.info("TAK connection cancelled")
			isConnected = false
			continuation?.yield(.disconnected)
			continuation?.finish()

		case .waiting(let error):
			Logger.tak.warning("TAK connection waiting: \(error.localizedDescription)")

		case .preparing:
			Logger.tak.debug("TAK connection preparing")

		case .setup:
			Logger.tak.debug("TAK connection setup")

		@unknown default:
			break
		}
	}

	/// Extract client information from the TLS session
	private func extractClientInfo() {
		// Client callsign/uid will be updated when first CoT message is received
		// For now just create basic client info with endpoint
		clientInfo = TAKClientInfo(
			endpoint: connection.endpoint,
			callsign: nil,
			uid: nil,
			connectedAt: Date()
		)
		Logger.tak.info("TAK client connected from: \(self.connection.endpoint.debugDescription)")
	}

	/// Start the reader task to continuously read from the connection
	private func startReading() {
		readerTask = Task {
			while !Task.isCancelled && isConnected {
				do {
					let data = try await receiveData()
					if !data.isEmpty {
						processReceivedData(data)
					}
				} catch {
					if !Task.isCancelled {
						Logger.tak.error("TAK read error: \(error.localizedDescription)")
						continuation?.yield(.error(error))
						continuation?.yield(.disconnected)
					}
					break
				}
			}
		}
	}

	/// Receive data from the connection
	private func receiveData() async throws -> Data {
		try await withCheckedThrowingContinuation { cont in
			connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
				if let error {
					cont.resume(throwing: error)
					return
				}
				if isComplete {
					cont.resume(throwing: TAKConnectionError.connectionClosed)
					return
				}
				if let content {
					cont.resume(returning: content)
				} else {
					cont.resume(returning: Data())
				}
			}
		}
	}

	/// Process received data using streaming CoT protocol
	/// Based on StreamingCotProtocol.java parsing logic from TAK Server
	private func processReceivedData(_ newData: Data) {
		messageBuffer.append(newData)

		// Search for complete CoT messages (delimited by </event>)
		while let endRange = messageBuffer.range(of: endTag) {
			// Find the start tag before this end tag
			guard let startRange = messageBuffer.range(of: startTag) else {
				// No start tag found, discard data up to end tag
				Logger.tak.warning("CoT end tag without start tag, discarding")
				messageBuffer.removeSubrange(..<endRange.upperBound)
				continue
			}

			// Ensure start is before end
			guard startRange.lowerBound < endRange.lowerBound else {
				// Malformed, discard up to end tag
				messageBuffer.removeSubrange(..<endRange.upperBound)
				continue
			}

			// Extract the complete message
			let messageData = messageBuffer.subdata(in: startRange.lowerBound..<endRange.upperBound)

			// Remove processed data from buffer
			messageBuffer.removeSubrange(..<endRange.upperBound)

			// Parse if within size limits
			if messageData.count <= maxMessageSize {
				parseAndYieldMessage(messageData)
			} else {
				Logger.tak.warning("CoT message too large: \(messageData.count) bytes, discarding")
			}
		}

		// Clear buffer if it exceeds max size (malformed data protection)
		if messageBuffer.count > maxMessageSize {
			Logger.tak.warning("Message buffer exceeded limit (\(self.messageBuffer.count) bytes), clearing")
			messageBuffer.removeAll()
		}
	}

	/// Parse XML data and yield the message event
	private func parseAndYieldMessage(_ data: Data) {
		// Log raw XML for debugging
		if let xmlString = String(data: data, encoding: .utf8) {
			Logger.tak.debug("=== Received CoT XML (\(data.count) bytes) ===")
			Logger.tak.debug("\(xmlString)")
			Logger.tak.debug("=== End Raw XML ===")
		}

		do {
			let cotMessage = try CoTMessage.parseData(data)

			// Handle TAK Protocol control messages
			if cotMessage.type.hasPrefix("t-x-takp") {
				Logger.tak.debug("Handling TAK Protocol control message: \(cotMessage.type)")
				Task {
					await handleProtocolControl(cotMessage)
				}
				return  // Don't forward control messages to app
			}

			// Handle ping/pong messages (don't forward, just acknowledge)
			if cotMessage.type == "t-x-c-t" || cotMessage.uid == "ping" {
				Logger.tak.debug("Received ping from client")
				return
			}

			// Update client info if we got contact details
			if let contact = cotMessage.contact {
				if clientInfo?.callsign == nil {
					clientInfo?.callsign = contact.callsign
				}
				if clientInfo?.uid == nil {
					clientInfo?.uid = cotMessage.uid
				}
				// Update the connected event with new info
				if let info = clientInfo {
					continuation?.yield(.clientInfoUpdated(info))
				}
			}

			Logger.tak.info("Received CoT message: type=\(cotMessage.type), uid=\(cotMessage.uid)")
			Logger.tak.debug("  contact: \(cotMessage.contact?.callsign ?? "nil")")
			Logger.tak.debug("  lat/lon: \(cotMessage.latitude), \(cotMessage.longitude)")
			continuation?.yield(.message(cotMessage))

		} catch {
			Logger.tak.warning("Failed to parse CoT message: \(error.localizedDescription)")
			// Log the raw XML for debugging
			if let xmlString = String(data: data, encoding: .utf8) {
				let snippet = String(xmlString.prefix(500))
				Logger.tak.debug("Failed Raw CoT XML: \(snippet)")
			}
		}
	}

	// MARK: - Protocol Negotiation

	/// Send TAK Protocol Support advertisement to client
	/// This tells the client what protocol versions we support (Version 0 = XML only)
	private func sendProtocolSupport() async {
		let now = ISO8601DateFormatter().string(from: Date())
		let stale = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))

		// TAK Protocol Support message - advertise version 0 (XML) only
		// Type t-x-takp-v indicates TAK Protocol version advertisement
		let xml = """
		<event version="2.0" uid="\(serverUID)" type="t-x-takp-v" time="\(now)" start="\(now)" stale="\(stale)" how="m-g">
			<point lat="0" lon="0" hae="0" ce="9999999" le="9999999"/>
			<detail>
				<TakControl>
					<TakProtocolSupport version="0"/>
				</TakControl>
			</detail>
		</event>
		"""

		do {
			try await sendRawXML(xml)
			Logger.tak.info("Sent TakProtocolSupport to client (version 0 - XML)")
		} catch {
			Logger.tak.error("Failed to send TakProtocolSupport: \(error.localizedDescription)")
		}
	}

	/// Handle TAK Protocol control messages (TakRequest, etc.)
	private func handleProtocolControl(_ cotMessage: CoTMessage) async {
		// Check for protocol request in the raw XML
		// Type t-x-takp-q is a protocol request from client
		if cotMessage.type == "t-x-takp-q" {
			await sendProtocolResponse(accepted: true)
		}
	}

	/// Send protocol response to client
	private func sendProtocolResponse(accepted: Bool) async {
		let now = ISO8601DateFormatter().string(from: Date())
		let stale = ISO8601DateFormatter().string(from: Date().addingTimeInterval(60))

		// Type t-x-takp-r is TAK Protocol response
		let xml = """
		<event version="2.0" uid="\(serverUID)" type="t-x-takp-r" time="\(now)" start="\(now)" stale="\(stale)" how="m-g">
			<point lat="0" lon="0" hae="0" ce="9999999" le="9999999"/>
			<detail>
				<TakControl>
					<TakResponse status="\(accepted ? "true" : "false")"/>
				</TakControl>
			</detail>
		</event>
		"""

		do {
			try await sendRawXML(xml)
			protocolNegotiated = true
			Logger.tak.info("Sent TakResponse (accepted: \(accepted))")
		} catch {
			Logger.tak.error("Failed to send TakResponse: \(error.localizedDescription)")
		}
	}

	// MARK: - Keepalive

	/// Start the keepalive task to send periodic pings
	private func startKeepalive() {
		keepaliveTask = Task {
			while !Task.isCancelled && isConnected {
				do {
					try await Task.sleep(nanoseconds: keepaliveInterval)
					if isConnected {
						await sendKeepalive()
					}
				} catch {
					break
				}
			}
		}
	}

	/// Send a keepalive/ping message to client
	private func sendKeepalive() async {
		let now = ISO8601DateFormatter().string(from: Date())
		let stale = ISO8601DateFormatter().string(from: Date().addingTimeInterval(120))

		// t-x-c-t is a ping/keepalive type, t-x-d-d is also used for takPong
		let xml = """
		<event version="2.0" uid="takPong" type="t-x-d-d" time="\(now)" start="\(now)" stale="\(stale)" how="m-g">
			<point lat="0" lon="0" hae="0" ce="9999999" le="9999999"/>
			<detail/>
		</event>
		"""

		do {
			try await sendRawXML(xml)
			Logger.tak.debug("Sent keepalive to client")
		} catch {
			Logger.tak.warning("Failed to send keepalive: \(error.localizedDescription)")
		}
	}

	// MARK: - Send Methods

	/// Send raw XML string to the client
	private func sendRawXML(_ xml: String) async throws {
		guard isConnected else {
			throw TAKConnectionError.notConnected
		}

		guard let data = xml.data(using: .utf8) else {
			throw TAKConnectionError.encodingFailed
		}

		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					cont.resume(throwing: error)
				} else {
					cont.resume()
				}
			})
		}
	}

	/// Send a CoT message to this client
	func send(_ cotMessage: CoTMessage) async throws {
		guard isConnected else {
			throw TAKConnectionError.notConnected
		}

		let xml = cotMessage.toXML()
		guard let data = xml.data(using: .utf8) else {
			throw TAKConnectionError.encodingFailed
		}

		try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
			connection.send(content: data, completion: .contentProcessed { error in
				if let error {
					cont.resume(throwing: error)
				} else {
					cont.resume()
				}
			})
		}

		Logger.tak.debug("Sent CoT message to client: type=\(cotMessage.type)")
	}

	/// Disconnect this client
	func disconnect() {
		guard isConnected else { return }

		Logger.tak.info("Disconnecting TAK client: \(self.connection.endpoint.debugDescription)")

		isConnected = false
		readerTask?.cancel()
		readerTask = nil
		keepaliveTask?.cancel()
		keepaliveTask = nil
		connection.cancel()
		messageBuffer.removeAll()

		continuation?.yield(.disconnected)
		continuation?.finish()
		continuation = nil
	}
}

// MARK: - Supporting Types

/// Information about a connected TAK client
struct TAKClientInfo: Identifiable, Sendable {
	let id = UUID()
	let endpoint: NWEndpoint
	var callsign: String?
	var uid: String?
	let connectedAt: Date

	init(endpoint: NWEndpoint, callsign: String? = nil, uid: String? = nil, connectedAt: Date = Date()) {
		self.endpoint = endpoint
		self.callsign = callsign
		self.uid = uid
		self.connectedAt = connectedAt
	}

	var displayName: String {
		callsign ?? uid ?? endpoint.debugDescription
	}
}

/// Events emitted by a TAK connection
enum TAKConnectionEvent: Sendable {
	case connected(TAKClientInfo)
	case clientInfoUpdated(TAKClientInfo)
	case message(CoTMessage)
	case disconnected
	case error(Error)
}

/// Errors specific to TAK connections
enum TAKConnectionError: LocalizedError {
	case connectionClosed
	case notConnected
	case encodingFailed
	case sendFailed(String)

	var errorDescription: String? {
		switch self {
		case .connectionClosed:
			return "Connection was closed"
		case .notConnected:
			return "Not connected"
		case .encodingFailed:
			return "Failed to encode CoT message"
		case .sendFailed(let reason):
			return "Failed to send: \(reason)"
		}
	}
}

