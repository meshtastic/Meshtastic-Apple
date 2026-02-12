//
//  TAKServerManager.swift
//  Meshtastic
//
//  Created by niccellular 12/26/25
//

import Foundation
import Network
import OSLog
import Combine
import SwiftUI

/// Manages the TAK Server lifecycle, TLS connections, and client management
/// Runs on MainActor for thread safety, following the AccessoryManager pattern
@MainActor
final class TAKServerManager: ObservableObject {

	static let shared = TAKServerManager()

	// MARK: - Published State

	@Published private(set) var isRunning = false
	@Published private(set) var connectedClients: [TAKClientInfo] = []
	@Published var lastError: String?

	// MARK: - Configuration (persisted via AppStorage)

	@AppStorage("takServerEnabled") var enabled = false {
		didSet {
			Task {
				if enabled && !isRunning {
					try? await start()
				} else if !enabled && isRunning {
					stop()
				}
			}
		}
	}

	/// Fixed port - always use TLS port 8089
	static let defaultTLSPort = 8089
	static let defaultTCPPort = 8087  // Legacy, not used

	/// Port is fixed to 8089 (mTLS)
	var port: Int { Self.defaultTLSPort }

	/// Always use TLS/mTLS
	var useTLS: Bool { true }

	// MARK: - Bridge

	/// Bridge for converting between CoT and Meshtastic formats
	var bridge: TAKMeshtasticBridge?

	// MARK: - Private Properties

	private var listener: NWListener?
	private var connections: [ObjectIdentifier: TAKConnection] = [:]
	private var connectionTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
	private let queue = DispatchQueue(label: "tak.server", qos: .userInitiated)

	private init() {}

	// MARK: - Initialization

	/// Initialize the TAK server on app startup
	/// Call this from app initialization to restore server state
	func initializeOnStartup() {
		guard enabled else {
			Logger.tak.debug("TAK Server not enabled, skipping startup")
			return
		}

		guard !isRunning else {
			Logger.tak.debug("TAK Server already running")
			return
		}

		Logger.tak.info("TAK Server enabled, starting on app launch")
		Task {
			do {
				try await start()
			} catch {
				Logger.tak.error("Failed to start TAK Server on startup: \(error.localizedDescription)")
			}
		}
	}

	// MARK: - Server Lifecycle

	/// Start the TAK server (TLS or TCP based on configuration)
	func start() async throws {
		guard !isRunning else {
			Logger.tak.info("TAK Server already running")
			return
		}

		let mode = useTLS ? "TLS" : "TCP"
		Logger.tak.info("Starting TAK Server on port \(self.port) (\(mode) mode)")

		let parameters: NWParameters

		if useTLS {
			// Validate we have a server certificate for TLS mode
			guard let identity = TAKCertificateManager.shared.getServerIdentity() else {
				let error = TAKServerError.noServerCertificate
				lastError = error.localizedDescription
				enabled = false
				throw error
			}

			// Create TLS options
			let tlsOptions = NWProtocolTLS.Options()

			// Set server identity (certificate + private key)
			guard let secIdentity = sec_identity_create(identity) else {
				let error = TAKServerError.tlsConfigurationFailed
				Logger.tak.error("Failed to create sec_identity from server identity")
				lastError = error.localizedDescription
				enabled = false
				throw error
			}
			sec_protocol_options_set_local_identity(
				tlsOptions.securityProtocolOptions,
				secIdentity
			)

			// Set minimum TLS version to 1.2 (TAK standard)
			sec_protocol_options_set_min_tls_protocol_version(
				tlsOptions.securityProtocolOptions,
				.TLSv12
			)

			// Configure mTLS - always require client certificate for TLS mode
			sec_protocol_options_set_peer_authentication_required(
				tlsOptions.securityProtocolOptions,
				true
			)

			// Set up client certificate validation
			let clientCAs = TAKCertificateManager.shared.getClientCACertificates()
			Logger.tak.info("Loaded \(clientCAs.count) CA certificate(s) for client validation")
			if !clientCAs.isEmpty {
				for (index, ca) in clientCAs.enumerated() {
					if let summary = SecCertificateCopySubjectSummary(ca) as String? {
						Logger.tak.info("CA[\(index)]: \(summary)")
					}
				}
				let trustRoots = clientCAs as CFArray
				sec_protocol_options_set_verify_block(
					tlsOptions.securityProtocolOptions,
					{ _, secTrust, completion in
						// Convert sec_trust_t to SecTrust
						let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()

						// Set policy for client certificate validation
						// Use SSL policy with server=false to validate client certificates
						// This properly accepts clientAuth ExtendedKeyUsage
						let clientPolicy = SecPolicyCreateSSL(false, nil)
						SecTrustSetPolicies(trust, clientPolicy)

						SecTrustSetAnchorCertificates(trust, trustRoots)
						SecTrustSetAnchorCertificatesOnly(trust, true)
						var error: CFError?
						let isValid = SecTrustEvaluateWithError(trust, &error)
						if let error = error {
							Logger.tak.error("Client cert validation error: \(error.localizedDescription)")
						}
						Logger.tak.info("Client certificate validation: \(isValid ? "passed" : "failed")")
						completion(isValid)
					},
					queue
				)
			} else {
				// No client CAs configured: keep mTLS enabled but reject all client certificates
				Logger.tak.warning("mTLS enabled but no CA certificates configured for client validation; all client connections will be rejected")
				sec_protocol_options_set_verify_block(
					tlsOptions.securityProtocolOptions,
					{ _, _, completion in
						Logger.tak.error("Rejecting client connection because no client CA certificates are configured")
						completion(false)
					},
					queue
				)
			}

			// TCP options
			let tcpOptions = NWProtocolTCP.Options()
			tcpOptions.enableKeepalive = true
			tcpOptions.keepaliveIdle = 60

			parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
		} else {
			// Plain TCP mode (no TLS)
			let tcpOptions = NWProtocolTCP.Options()
			tcpOptions.enableKeepalive = true
			tcpOptions.keepaliveIdle = 60

			parameters = NWParameters(tls: nil, tcp: tcpOptions)
		}

		parameters.allowLocalEndpointReuse = true

		// Bind to localhost only - only allow TAK clients on the same device
		parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
			host: NWEndpoint.Host("127.0.0.1"),
			port: NWEndpoint.Port(integerLiteral: UInt16(port))
		)

		// Create and configure listener
		do {
			listener = try NWListener(using: parameters)
		} catch {
			lastError = "Failed to create listener: \(error.localizedDescription)"
			Logger.tak.error("Failed to create TAK listener: \(error.localizedDescription)")
			enabled = false
			throw error
		}

		// Set up state handler
		listener?.stateUpdateHandler = { [weak self] state in
			Task { @MainActor in
				self?.handleListenerState(state)
			}
		}

		// Set up new connection handler
		listener?.newConnectionHandler = { [weak self] connection in
			Task { @MainActor in
				await self?.handleNewConnection(connection)
			}
		}

		// Start listening
		listener?.start(queue: queue)
	}

	/// Stop the TAK server
	func stop() {
		Logger.tak.info("Stopping TAK Server")

		listener?.cancel()
		listener = nil

		// Cancel all connection tasks
		for (_, task) in connectionTasks {
			task.cancel()
		}
		connectionTasks.removeAll()

		// Disconnect all clients
		for (_, connection) in connections {
			Task {
				await connection.disconnect()
			}
		}
		connections.removeAll()
		connectedClients.removeAll()

		isRunning = false
		lastError = nil

		Logger.tak.info("TAK Server stopped")
	}

	/// Restart the server (useful after configuration changes)
	func restart() async throws {
		stop()
		try await Task.sleep(nanoseconds: 500_000_000)  // 0.5s delay
		try await start()
	}

	// MARK: - State Handling

	private func handleListenerState(_ state: NWListener.State) {
		switch state {
		case .ready:
			isRunning = true
			lastError = nil
			Logger.tak.info("TAK Server listening on port \(self.port)")

		case .failed(let error):
			isRunning = false
			lastError = error.localizedDescription
			enabled = false
			Logger.tak.error("TAK Server failed: \(error.localizedDescription)")

		case .cancelled:
			isRunning = false
			Logger.tak.info("TAK Server cancelled")

		case .waiting(let error):
			Logger.tak.warning("TAK Server waiting: \(error.localizedDescription)")

		case .setup:
			Logger.tak.debug("TAK Server setup")

		@unknown default:
			break
		}
	}

	// MARK: - Connection Management

	private func handleNewConnection(_ nwConnection: NWConnection) async {
		let connectionId = ObjectIdentifier(nwConnection)
		let connection = TAKConnection(connection: nwConnection)

		connections[connectionId] = connection

		Logger.tak.info("New TAK client connecting: \(nwConnection.endpoint.debugDescription)")

		// Start handling the connection
		let eventStream = await connection.start()

		// Create task to handle connection events
		let task = Task {
			for await event in eventStream {
				await handleConnectionEvent(event, connectionId: connectionId)
			}
			// Connection ended
			await removeConnection(connectionId)
		}

		connectionTasks[connectionId] = task
	}

	private func handleConnectionEvent(_ event: TAKConnectionEvent, connectionId: ObjectIdentifier) async {
		switch event {
		case .connected(let clientInfo):
			connectedClients.append(clientInfo)
			Logger.tak.info("TAK client connected: \(clientInfo.displayName)")

		case .clientInfoUpdated(let clientInfo):
			// Update the client info in our list
			if let index = connectedClients.firstIndex(where: { $0.id == clientInfo.id }) {
				connectedClients[index] = clientInfo
			}

		case .message(let cotMessage):
			Logger.tak.info("Received CoT from TAK client: \(cotMessage.type)")
			// Forward to Meshtastic mesh via bridge
			await bridge?.sendToMesh(cotMessage)

		case .disconnected:
			await removeConnection(connectionId)

		case .error(let error):
			Logger.tak.error("TAK client error: \(error.localizedDescription)")
		}
	}

	private func removeConnection(_ connectionId: ObjectIdentifier) async {
		connectionTasks[connectionId]?.cancel()
		connectionTasks.removeValue(forKey: connectionId)

		if let connection = connections.removeValue(forKey: connectionId) {
			let endpoint = await connection.endpoint
			connectedClients.removeAll { $0.endpoint.debugDescription == endpoint.debugDescription }
			Logger.tak.info("TAK client disconnected")
		}
	}

	// MARK: - Message Distribution

	/// Broadcast a CoT message to all connected TAK clients
	func broadcast(_ cotMessage: CoTMessage) async {
		guard !connections.isEmpty else { return }

		Logger.tak.info("Broadcasting CoT to \(self.connections.count) TAK client(s): \(cotMessage.type)")

		for (connectionId, connection) in connections {
			do {
				try await connection.send(cotMessage)
			} catch {
				Logger.tak.error("Failed to send to TAK client: \(error.localizedDescription)")
				// Remove failed connection
				await removeConnection(connectionId)
			}
		}
	}

	/// Send a CoT message to a specific client
	func send(_ cotMessage: CoTMessage, to clientId: UUID) async throws {
		guard let clientInfo = connectedClients.first(where: { $0.id == clientId }) else {
			throw TAKServerError.clientNotFound
		}

		for (_, connection) in connections {
			let endpoint = await connection.endpoint
			if endpoint.debugDescription == clientInfo.endpoint.debugDescription {
				try await connection.send(cotMessage)
				return
			}
		}

		throw TAKServerError.clientNotFound
	}

	// MARK: - Status

	/// Get server status description
	var statusDescription: String {
		if isRunning {
			let mode = useTLS ? "TLS" : "TCP"
			return "Running on port \(port) (\(mode))"
		} else if let error = lastError {
			return "Error: \(error)"
		} else {
			return "Stopped"
		}
	}
}

// MARK: - Server Errors

enum TAKServerError: LocalizedError {
	case noServerCertificate
	case noClientCACertificate
	case tlsConfigurationFailed
	case listenerFailed(String)
	case clientNotFound
	case notRunning

	var errorDescription: String? {
		switch self {
		case .noServerCertificate:
			return "No server certificate configured. Import a .p12 file with the server certificate and private key."
		case .noClientCACertificate:
			return "No client CA certificate configured. Import the CA certificate (.pem) used to sign client certificates."
		case .tlsConfigurationFailed:
			return "Failed to configure TLS settings."
		case .listenerFailed(let reason):
			return "Failed to start listener: \(reason)"
		case .clientNotFound:
			return "Client not found"
		case .notRunning:
			return "TAK Server is not running"
		}
	}
}
