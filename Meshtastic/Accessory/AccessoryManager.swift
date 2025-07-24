//
//  AccessoryManager.swift
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import SwiftUI
import MeshtasticProtobufs
import OSLog
import CocoaMQTT
import CoreLocation

enum AccessoryError: Error {
	case discoveryFailed(String)
	case connectionFailed(String)
	case versionMismatch(String)
	case ioFailed(String)
	case appError(String)
	case timeout
	case disconnected

}

enum AccessoryManagerState: Equatable {
	case uninitialized
	case idle
	case discovering
	case connecting
	case retrying(attempt: Int)
	case retreivingDatabase(nodeCount: Int)
	case communicating
	case subscribed

	var description: String {
		switch self {
		case .uninitialized:
			return "Uninitialized"
		case .idle:
			return "Idle"
		case .discovering:
			return "Discovering"
		case .connecting:
			return "Connecting"
		case .retrying(let attempt):
			return "Retrying Connection (\(attempt))"
		case .communicating:
			return "Communicating"
		case .subscribed:
			return "Subscribed"
		case .retreivingDatabase(let nodeCount):
			return "Retreiving Database \(nodeCount)"
		}
	}
}

@MainActor
class AccessoryManager: ObservableObject, MqttClientProxyManagerDelegate {
	// Singleton Access
	static let shared = AccessoryManager()

	// Constants
	let NONCE_ONLY_CONFIG = 69420
	let NONCE_ONLY_DB = 69421
	let minimumVersion = "2.3.15"

	// Global Objects
	// Chicken/Egg problem.  Set in the App object immediately after
	// AppState and AccessoryManager are created
	var appState: AppState!
	let context = PersistenceController.shared.container.viewContext
	let mqttManager = MqttClientProxyManager.shared

	// Published Stuff
	@Published var mqttProxyConnected: Bool = false
	@Published var devices: [Device] = []
	@Published var state: AccessoryManagerState
	@Published var mqttError: String = ""
	@Published var activeDeviceNum: Int64?
	@Published var allowDisconnect = false
	@Published var lastConnectionError: Error?
	@Published var isConnected: Bool = false
	@Published var isConnecting: Bool = false

	var activeConnection: (device: Device, connection: any Connection)?

	let transports: [any Transport]

	// Config
	public var wantRangeTestPackets = true
	var wantStoreAndForwardPackets = false

	// Tasks
	// Private
	private var locationTask: Task<Void, Error>?
	private var connectionTask: Task<Void, Error>?
	private var packetTask: Task <Void, Error>?
	private var logTask: Task <Void, Error>?
	private var rssiTask: Task <Void, Error>?

	// Public due to file separation
	var rssiUpdateDuringDiscoveryTask: Task <Void, Error>?
	var discoveryTask: Task<Void, Never>?

	// Continuations
	private var wantConfigContinuations: [UInt32: CheckedContinuation<Void, Error>] = [:]

	init(transports: [any Transport] = [BLETransport(), TCPTransport(), SerialTransport()]) {
		self.transports = transports
		self.state = .uninitialized
		self.mqttManager.delegate = self
	}

	func connectToPreferredDevice() -> Bool {
		// not implemented
		Logger.services.error("connectToPreferredDevice not implemented")
		return false
	}

	func connect(to device: Device) async throws {
		guard connectionTask == nil else {
			throw AccessoryError.connectionFailed("Already connecting to a device")
		}

		// Prevent new connection if one is active
		if activeConnection != nil {
			throw AccessoryError.connectionFailed("Already connected to a device")
		}

		// Prepare to connect, 10 retries, 1 second in between each
		let maxRetries = 10
		let retryDelay: Duration = .seconds(3)

		// Start trying to connect
		lastConnectionError = nil

		self.connectionTask = Task {
			retryLoop: for attempt in 1...maxRetries {
				try Task.checkCancellation()

				if attempt > 1 {
					Logger.transport.info("[Connect] Retrying connection to \(device.name) (\(attempt)/\(maxRetries))")
					self.updateState(.retrying(attempt: attempt))
					try? await Task.sleep(for: retryDelay)
					self.allowDisconnect = true
				} else {
					self.updateState(.connecting)
					updateDevice(deviceId: device.id, key: \.connectionState, value: .connecting)
				}

				do {
					_ = try await Task(timeout: .seconds(15)) {
						try await self.connectionProcess(device: device, attempt: attempt)
					}.value

					return
				} catch {
					// Clean up from last attempt, but do not cancel the task or publish a new status
					try await self.closeConnection()

					switch error {
					case is CancellationError:
						Logger.transport.error("[Connect] Connection attempt cancelled")
						break retryLoop
					case AccessoryError.versionMismatch(_):
						Logger.transport.error("[Connect] Firmware version too old.  Not reconnecting")
						break retryLoop
					default:
						Logger.transport.error("[Connect] Failed to connect to \(device.name) \(error.localizedDescription)")
					}
				}
			}

			// Exhaused all retries
			try await self.disconnect()

		}
	}

	// Non-isolated because this function is meant to be run in a different thread.
	nonisolated func connectionProcess(device: Device, attempt: Int) async throws {
		// Find the transport that handles this device
		guard let transport = await transports.first(where: { $0.type == device.transportType }) else {
			await updateDevice(deviceId: device.id, key: \.connectionState, value: .disconnected)
			throw AccessoryError.connectionFailed("No transport for type")
		}

		// Start the connection task
		Logger.transport.debug("[Connect] Attempting to connect to device: \(device.name, privacy: .public) retry: \(attempt)")
		// Ask the transport to connect to the device and return a connection
		let connection = try await transport.connect(to: device)
		let (packetStream, logStream) = try await connection.connect()

		// If this is a wireless connection, have it report the RSSI to the AccessoryManager
		Task { @MainActor in
			updateState(.communicating)
			if let wirelessConnection = connection as? any WirelessConnection {
				self.rssiTask = Task {
					for await rssiValue in await wirelessConnection.getRSSIStream() {
						self.didUpdateRSSI(rssiValue, for: device.id)
					}
				}
			}
		}

		try Task.checkCancellation()

		// Connections emit FromRadio protobufs.  Process them in didReceive
		Task { @MainActor in
			self.packetTask = Task {
				for await packet in packetStream {
					self.didReceive(result: .success(packet))
				}
				self.didReceive(result: .failure(AccessoryError.connectionFailed("Connection closed")))
			}
		}

		try Task.checkCancellation()

		// Not all connections emit log messages.  Process them if they do.
		if let logStream {
			Task { @MainActor in
				self.packetTask = Task {
					for await logString in logStream {
						self.didReceiveLog(message: logString)
					}
				}
			}
		}

		try Task.checkCancellation()

		_ = await Task { @MainActor in
			self.activeConnection = (device: device, connection: connection)
		}.result

		// Send Heartbeat before wantConfig
		var heartbeatToRadio: ToRadio = ToRadio()
		heartbeatToRadio.payloadVariant = .heartbeat(Heartbeat())
		try? await connection.send(heartbeatToRadio)

		// try await Task.sleep(for: .seconds(15))

		try Task.checkCancellation()

		Logger.transport.debug("[Connect] sending wantConfig (config) for initial request")
		await self.sendWantConfig()

		try Task.checkCancellation()

		if UserDefaults.firstLaunch {
			UserDefaults.showDeviceOnboarding = true
		}

		try Task.checkCancellation()
		// Send Heartbeat before wantConfig
		try? await connection.send(heartbeatToRadio)

		try Task.checkCancellation()

		Logger.transport.debug("[Connect] Sending wantConfig (database) for initial request")
		Task { @MainActor in self.allowDisconnect = true }
		await updateState(.retreivingDatabase(nodeCount: 0))
		await self.sendWantDatabase()

		try Task.checkCancellation()

		Task { @MainActor in
			self.allowDisconnect = true
		}
		
		let connectedVersion = try await Task { @MainActor in
			Logger.transport.debug("[Connect] Performing version check")
			guard let firmwareVersion = self.activeConnection?.device.firmwareVersion else {
				Logger.transport.error("[Connect] Firmware version not available for device \(device.name, privacy: .public)")
				throw AccessoryError.connectionFailed("Firmware version not available")
			}

		let lastDotIndex = firmwareVersion.lastIndex(of: ".")
		if lastDotIndex == nil {
			throw AccessoryError.connectionFailed("🚨" + "Update Your Firmware".localized)
		}

		let version = firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: firmwareVersion))]
			return String(version.dropLast())
		}.value

		UserDefaults.firmwareVersion = connectedVersion

		let supportedVersion = await self.checkIsVersionSupported(forVersion: self.minimumVersion)
		if !supportedVersion {
			throw AccessoryError.connectionFailed("🚨" + "Update Your Firmware".localized)
		}

		if UserDefaults.preferredPeripheralId.count < 1 {
			UserDefaults.preferredPeripheralId = device.id.uuidString
		}
		
		// We have an active connection
		await self.updateDevice(deviceId: device.id, key: \.connectionState, value: .connected)
		await self.updateState(.subscribed)

		Logger.transport.debug("[Connect] Initialize MQTT and Location Provider")
		await self.initializeMqtt()
		await self.initializeLocationProvider()
	}

	func sendWantConfig() async {
		guard let connection = activeConnection?.connection else {
			Logger.transport.error("Unable to send wantConfig (config): No device connected")
			return
		}
		try? await sendNonceRequest(nonce: UInt32(NONCE_ONLY_CONFIG), connection: connection)
		Logger.transport.info("✅ [Accessory] NONCE_ONLY_CONFIG Done")
	}

	func sendWantDatabase() async {
		guard let connection = activeConnection?.connection else {
			Logger.transport.error("Unable to send wantConfig (database) : No device connected")
			return
		}

		try? await sendNonceRequest(nonce: UInt32(NONCE_ONLY_DB), connection: connection)
		Logger.transport.info("✅ [Accessory] NONCE_ONLY_DB Done")
	}

	private func sendNonceRequest(nonce: UInt32, connection: any Connection) async throws {
		// Create the protobuf with the wantConfigID nonce
		var toRadio: ToRadio = ToRadio()
		toRadio.wantConfigID = nonce

		// Send it to the radio
		try await self.send(data: toRadio)

		// Start draining packets in the background
		try await connection.startDrainPendingPackets()

		// Wait for the nonce request to be completed before continuing
		try await withCheckedThrowingContinuation { cont in
			wantConfigContinuations[nonce] = cont
		}
	}

	func closeConnection() async throws {
		Logger.transport.debug("[AccessoryManager] received disconnect request")

		// Clean up continuations
		for continuation in self.wantConfigContinuations.values {
			continuation.resume(throwing: AccessoryError.disconnected)
		}
		self.wantConfigContinuations.removeAll()
		
		// Close out the connection
		if let activeConnection = activeConnection {
			self.activeConnection = nil
			try await activeConnection.connection.disconnect()
			updateDevice(deviceId: activeConnection.device.id, key: \.connectionState, value: .disconnected)
		}
	}
	
	func disconnect() async throws {
		// Cancel ongoing connection task if it exists
		if let connectionTask {
			Logger.transport.debug("[AccessoryManager] Connection in progress.  Cancelling")
			connectionTask.cancel()
			self.connectionTask = nil
		}

		try await closeConnection()

		// Turn off the disconnect buttons
		allowDisconnect = false
		
		// Set state back to discovering
		updateState(.discovering)
	}

	// Update device attributes on MainActor for presentation in the UI
	func updateDevice<T>(deviceId: UUID? = nil, key: WritableKeyPath<Device, T>, value: T) {
		guard let deviceId = deviceId ?? self.activeConnection?.device.id else {
			Logger.transport.error("updateDevice<T> with nil deviceId")
			return
		}

		if let index = devices.firstIndex(where: { $0.id == deviceId }) {
			var device = devices[index]
			device[keyPath: key] = value

			if let activeConnection, activeConnection.device.id == device.id {
				self.activeConnection = (device: device, connection: activeConnection.connection)
			}

			// Update the @Published stuff for the UI

			self.objectWillChange.send()
			// Find the index again because we're in a different task now and maybe it changed.
			if let index = devices.firstIndex(where: { $0.id == deviceId }) {
				devices[index] = device
				activeDeviceNum = device.num
			}

		} else {
			Logger.transport.error("Device with ID \(deviceId) not found in devices list.")
		}

	}

	// Update state on MainActor for presentation in the UI
	func updateState(_ newState: AccessoryManagerState) {
		Logger.transport.info("Updating state from \(self.state.description) to \(newState.description)")
		switch newState {
		case .uninitialized, .idle, .discovering:
			self.isConnected = false
			self.isConnecting = false
		case .connecting, .communicating, .retrying, .retreivingDatabase:
			self.isConnected = false
			self.isConnecting = true
		case .subscribed:
			self.isConnected = true
			self.isConnecting = false
		}
		self.state = newState
	}

	func send(data: ToRadio, debugDescription: String? = nil) async throws {
		Logger.transport.info("✅ [Accessory] Sending \(data.debugDescription)")
		guard let active = activeConnection,
			  await active.connection.isConnected else {
			throw AccessoryError.connectionFailed("Not connected to any device")
		}
		try await active.connection.send(data)
		if let debugDescription {
			Logger.transport.info("📻 \(debugDescription, privacy: .public)")
		}
	}

	func didReceive(result: Result<FromRadio, Error>) {
		switch result {
		case .success(let fromRadio):
			Logger.transport.info("✅ [Accessory] didReceive: \(fromRadio.payloadVariant.debugDescription)")
			self.processFromRadio(fromRadio)

		case .failure(let error):
			// Handle error, perhaps log and disconnect
			Logger.transport.info("🚨 [Accessory] didReceive with failure: \(error.localizedDescription)")
			switch self.state {
			case .connecting, .retrying:
				break
			default:
				Task { try? await self.disconnect() }
			}
		}
	}

	func didReceiveLog(message: String) {
		var log = message
		/// Debug Log Level
		if log.starts(with: "DEBUG |") {
			do {
				let logString = log
				if let coordsMatch = try CommonRegex.COORDS_REGEX.firstMatch(in: logString) {
					log = "\(log.replacingOccurrences(of: "DEBUG |", with: "").trimmingCharacters(in: .whitespaces))"
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.debug("🛰️ \(log.prefix(upTo: coordsMatch.range.lowerBound), privacy: .public) \(coordsMatch.0.replacingOccurrences(of: "[,]", with: "", options: .regularExpression), privacy: .private(mask: .none)) \(log.suffix(from: coordsMatch.range.upperBound), privacy: .public)")
				} else {
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.debug("🕵🏻‍♂️ \(log.replacingOccurrences(of: "DEBUG |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
				}
			} catch {
				log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
				Logger.radio.debug("🕵🏻‍♂️ \(log.replacingOccurrences(of: "DEBUG |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
			}
		} else if log.starts(with: "INFO  |") {
			do {
				let logString = log
				if let coordsMatch = try CommonRegex.COORDS_REGEX.firstMatch(in: logString) {
					log = "\(log.replacingOccurrences(of: "INFO  |", with: "").trimmingCharacters(in: .whitespaces))"
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.info("🛰️ \(log.prefix(upTo: coordsMatch.range.lowerBound), privacy: .public) \(coordsMatch.0.replacingOccurrences(of: "[,]", with: "", options: .regularExpression), privacy: .private) \(log.suffix(from: coordsMatch.range.upperBound), privacy: .public)")
				} else {
					log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
					Logger.radio.info("📢 \(log.replacingOccurrences(of: "INFO  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
				}
			} catch {
				log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
				Logger.radio.info("📢 \(log.replacingOccurrences(of: "INFO  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
			}
		} else if log.starts(with: "WARN  |") {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.warning("⚠️ \(log.replacingOccurrences(of: "WARN  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
		} else if log.starts(with: "ERROR |") {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.error("💥 \(log.replacingOccurrences(of: "ERROR |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
		} else if log.starts(with: "CRIT  |") {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.critical("🧨 \(log.replacingOccurrences(of: "CRIT  |", with: "").trimmingCharacters(in: .whitespaces), privacy: .public)")
		} else {
			log = log.replacingOccurrences(of: "[,]", with: "", options: .regularExpression)
			Logger.radio.debug("📟 \(log, privacy: .public)")
		}
	}

	private func processFromRadio(_ decodedInfo: FromRadio) {
		switch decodedInfo.payloadVariant {
		case .mqttClientProxyMessage(let mqttClientProxyMessage):
			handleMqttClientProxyMessage(mqttClientProxyMessage)

		case .clientNotification(let clientNotification):
			handleClientNotification(clientNotification)

		case .myInfo(let myNodeInfo):
			handleMyInfo(myNodeInfo)

		case .packet(let packet):
			if case let .decoded(data) = packet.payloadVariant {
				switch data.portnum {
				case .textMessageApp, .detectionSensorApp, .alertApp:
					handleTextMessageAppPacket(packet)
				case .remoteHardwareApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Remote Hardware App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .positionApp:
					upsertPositionPacket(packet: packet, context: context)
				case .waypointApp:
					waypointPacket(packet: packet, context: context)
				case .nodeinfoApp:
					upsertNodeInfoPacket(packet: packet, context: context)
				case .routingApp:
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for routingPacket.")
						return
					}
					routingPacket(packet: packet, connectedNodeNum: deviceNum, context: context)
				case .adminApp:
					adminAppPacket(packet: packet, context: context)
				case .replyApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Reply App handling as a text message")
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for replyApp.")
						return
					}
					textMessageAppPacket(packet: packet, wantRangeTestPackets: wantRangeTestPackets, connectedNode: deviceNum, context: context, appState: appState)
				case .ipTunnelApp:
					Logger.mesh.info("🕸️ MESH PACKET received for IP Tunnel App UNHANDLED UNHANDLED")
				case .serialApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Serial App UNHANDLED UNHANDLED")
				case .storeForwardApp:
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for storeAndForward.")
						return
					}
					storeAndForwardPacket(packet: decodedInfo.packet, connectedNodeNum: deviceNum)
				case .rangeTestApp:
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for rangeTestApp.")
						return
					}
					if wantRangeTestPackets {
						textMessageAppPacket(
							packet: packet,
							wantRangeTestPackets: true,
							connectedNode: deviceNum,
							context: context,
							appState: appState
						)
					} else {
						Logger.mesh.info("🕸️ MESH PACKET received for Range Test App Range testing is disabled.")
					}
				case .telemetryApp:
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for telemetryApp.")
						return
					}
					telemetryPacket(packet: packet, connectedNode: deviceNum, context: context)
				case .textMessageCompressedApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Text Message Compressed App UNHANDLED")
				case .zpsApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Zero Positioning System App UNHANDLED")
				case .privateApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Private App UNHANDLED UNHANDLED")
				case .atakForwarder:
					Logger.mesh.info("🕸️ MESH PACKET received for ATAK Forwarder App UNHANDLED UNHANDLED")
				case .simulatorApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Simulator App UNHANDLED UNHANDLED")
				case .audioApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Audio App UNHANDLED UNHANDLED")
				case .tracerouteApp:
					handleTraceRouteApp(packet)
				case .neighborinfoApp:
					if let neighborInfo = try? NeighborInfo(serializedBytes: decodedInfo.packet.decoded.payload) {
						Logger.mesh.info("🕸️ MESH PACKET received for Neighbor Info App UNHANDLED \((try? neighborInfo.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
					}
				case .paxcounterApp:
					paxCounterPacket(packet: decodedInfo.packet, context: context)
				case .mapReportApp:
					Logger.mesh.info("🕸️ MESH PACKET received Map Report App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .UNRECOGNIZED:
					Logger.mesh.info("🕸️ MESH PACKET received UNRECOGNIZED App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .max:
					Logger.services.info("MAX PORT NUM OF 511")
				case .atakPlugin:
					Logger.mesh.info("🕸️ MESH PACKET received for ATAK Plugin App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .powerstressApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Power Stress App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .reticulumTunnelApp:
					Logger.mesh.info("🕸️ MESH PACKET received for Reticulum Tunnel App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .keyVerificationApp:
					Logger.mesh.warning("🕸️ MESH PACKET received for Key Verification App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .unknownApp:
					Logger.mesh.warning("🕸️ MESH PACKET received for unknown App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				case .cayenneApp:
					Logger.mesh.info("🕸️ MESH PACKET received Cayenne App UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
				}
			}

		case .nodeInfo(let nodeInfo):
			handleNodeInfo(nodeInfo)

		case .channel(let channel):
			handleChannel(channel)

		case .config(let config):
			handleConfig(config)

		case .moduleConfig(let moduleConfig):
			handleModuleConfig(moduleConfig)

		case .metadata(let metadata):
			handleDeviceMetadata(metadata)

		case .deviceuiConfig:
			Logger.mesh.warning("🕸️ MESH PACKET received for deviceUIConfig UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")

		case .fileInfo:
			Logger.mesh.warning("🕸️ MESH PACKET received for fileInfo UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")

		case .queueStatus:
			Logger.mesh.warning("🕸️ MESH PACKET received for queueStatus UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")

		case .configCompleteID(let configCompleteID):
			// Not sure if we want to do anythign here directly?  The continuation stuff lets you
			// do the next step right in the connection flow.

			// switch configCompleteID {
			// case UInt32(NONCE_ONLY_CONFIG):
			//	break;
			// case UInt32(NONCE_ONLY_DB):
			// 	break;
			// break:
			// Logger.mesh.error("✅ [Accessory] Unknown UNHANDLED confligCompleteID: \(configCompleteID)")
			// }

			Logger.transport.info("✅ [Accessory] Notifying completions that have completed for confligCompleteID: \(configCompleteID)")
			if let continuation = wantConfigContinuations[configCompleteID] {
				wantConfigContinuations.removeValue(forKey: configCompleteID)
				continuation.resume()
			}

		default:
			Logger.mesh.error("Unknown FromRadio variant: \(decodedInfo.payloadVariant.debugDescription)")
		}

	}
}

extension AccessoryManager {
	func didUpdateRSSI(_ rssi: Int, for deviceId: UUID) {
		updateDevice(deviceId: deviceId, key: \.rssi, value: rssi)
	}
}

extension AccessoryManager {
	func initializeLocationProvider() {
		self.locationTask = Task {
			repeat {
				try? await Task.sleep(for: .seconds(30)) // sleep for 30 seconds. This throws if task is cancelled

				guard let fromNodeNum = activeConnection?.device.num else {
					return
				}

				if UserDefaults.provideLocation {
					_ = try await sendPosition(channel: 0, destNum: fromNodeNum, wantResponse: false)
				}
			} while !Task.isCancelled
		}
	}

	public func sendPosition(channel: Int32, destNum: Int64, wantResponse: Bool) async throws {
		guard let fromNodeNum = activeConnection?.device.num else {
			throw AccessoryError.ioFailed("Not connected to any device")
		}

		guard let positionPacket = try await getPositionFromPhoneGPS(destNum: destNum, fixedPosition: false) else {
			Logger.services.error("Unable to get position data from device GPS to send to node")
			throw AccessoryError.appError("Unable to get position data from device GPS to send to node")
		}

		var meshPacket = MeshPacket()
		meshPacket.to = UInt32(destNum)
		meshPacket.channel = UInt32(channel)
		meshPacket.from	= UInt32(fromNodeNum)
		var dataMessage = DataMessage()
		if let serializedData: Data = try? positionPacket.serializedData() {
			dataMessage.payload = serializedData
			dataMessage.portnum = PortNum.positionApp
			dataMessage.wantResponse = wantResponse
			meshPacket.decoded = dataMessage
		} else {
			Logger.services.error("Failed to serialize position packet data")
			throw AccessoryError.ioFailed("sendPosition: Unable to serialize position packet data")
		}

		var toRadio: ToRadio!
		toRadio = ToRadio()
		toRadio.packet = meshPacket
		try await self.send(data: toRadio)
	}

	public func getPositionFromPhoneGPS(destNum: Int64, fixedPosition: Bool) async throws -> Position? {
		var positionPacket = Position()

		guard let lastLocation = LocationsHandler.shared.locationsArray.last else {
			return nil
		}

		if lastLocation == CLLocation(latitude: 0, longitude: 0) {
			return nil
		}

		positionPacket.latitudeI = Int32(lastLocation.coordinate.latitude * 1e7)
		positionPacket.longitudeI = Int32(lastLocation.coordinate.longitude * 1e7)
		let timestamp = lastLocation.timestamp
		positionPacket.time = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.timestamp = UInt32(timestamp.timeIntervalSince1970)
		positionPacket.altitude = Int32(lastLocation.altitude)
		positionPacket.satsInView = UInt32(LocationsHandler.satsInView)
		let currentSpeed = lastLocation.speed
		if currentSpeed > 0 && (!currentSpeed.isNaN || !currentSpeed.isInfinite) {
			positionPacket.groundSpeed = UInt32(currentSpeed)
		}
		let currentHeading = lastLocation.course
		if (currentHeading > 0  && currentHeading <= 360) && (!currentHeading.isNaN || !currentHeading.isInfinite) {
			positionPacket.groundTrack = UInt32(currentHeading)
		}
		/// Set location source for time
		if !fixedPosition {
			/// From GPS treat time as good
			positionPacket.locationSource = Position.LocSource.locExternal
		} else {
			/// From GPS, but time can be old and have drifted
			positionPacket.locationSource = Position.LocSource.locManual
		}
		return positionPacket
	}
}

extension AccessoryManager {
	var connectedVersion: String? {
		return activeConnection?.device.firmwareVersion
	}

	func checkIsVersionSupported(forVersion: String) -> Bool {
		let myVersion = connectedVersion ?? "0.0.0"
		let supportedVersion = UserDefaults.firmwareVersion == "0.0.0" ||
		forVersion.compare(myVersion, options: .numeric) == .orderedAscending ||
		forVersion.compare(myVersion, options: .numeric) == .orderedSame
		return supportedVersion
	}
}

extension Task where Failure == Error {
	init(timeout: Duration, operation: @escaping @Sendable () async throws -> Success) {
		self = Task {
			try await withThrowingTaskGroup(of: Success.self) { group -> Success in
				group.addTask(operation: operation)
				group.addTask {
					try await _Concurrency.Task.sleep(for: timeout)
					Logger.transport.error("AccessoryManager Task timed out after \(timeout)")
					throw AccessoryError.timeout
				}
				guard let success = try await group.next() else {
					throw AccessoryError.timeout
				}
				group.cancelAll()
				return success
			}
		}
	}
}
