//
//  AccessoryManager.swift
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import SwiftUI
import MeshtasticProtobufs
import CoreBluetooth
import OSLog
import CocoaMQTT
import Combine

enum AccessoryError: Error, LocalizedError {
	case discoveryFailed(String)
	case connectionFailed(String)
	case versionMismatch(String)
	case ioFailed(String)
	case appError(String)
	case timeout
	case disconnected(String)
	case tooManyRetries
	case eventStreamCancelled
	case coreBluetoothError(CBError)
	case coreBluetoothATTError(CBATTError)
	
	var errorDescription: String? {
		switch self {
		case .discoveryFailed(let message):
			return "Discovery failed. \(message)"
		case .connectionFailed(let message):
			return "Connection failed. \(message)"
		case .versionMismatch(let message):
			return "Version mismatch: \(message)"
		case .ioFailed(let message):
			return "Communication failure: \(message)"
		case .appError(let message):
			return "Application error: \(message)"
		case .timeout:
			return "Connection Timeout"
		case .disconnected(let message):
			return "Disconnected: \(message)"
		case .tooManyRetries:
			return "Too Many Retries"
		case .eventStreamCancelled:
			return "Event stream cancelled"
		case .coreBluetoothError(let cbError):
			// Map specific CBError values to a more user-friendly message
			switch cbError.code {
			case .connectionTimeout: // 6
				return "The Bluetooth connection to the radio unexpectedly disconnected, it will automatically reconnect to the preferred radio when it comes back in range or is powered back on.".localized
			case .peripheralDisconnected: // 7
				return "The Bluetooth connection to the radio was disconnected, it will automatically reconnect to the preferred radio when it is powered back on or finishes rebooting.".localized
			case .peerRemovedPairingInformation: // 14
				return "The radio has deleted its stored pairing information, but your device has not. To resolve this, you must forget the radio under Settings > Bluetooth to clear the old, now invalid, pairing information.".localized
			default:
				// Fallback for other CBError codes
				return "A Bluetooth error occurred: \(cbError.localizedDescription)"
			}
		case .coreBluetoothATTError(let attError):
			// Map specific CBATTError values to a more user-friendly message
			switch attError.code {
			case .insufficientAuthentication: // 5
				return "Bluetooth \(attError.localizedDescription) Please try connecting again and check the BLE PIN carefully.".localized
			case .insufficientEncryption: // 15
				return "Bluetooth \(attError.localizedDescription) Please try connecting again and check the BLE PIN carefully.".localized
			default:
				// Fallback for other CBError codes
				return "A Bluetooth Attribute Protocol error occurred: \(attError.localizedDescription)"
			}
		}
	}
}

enum AccessoryManagerState: Equatable {
	case uninitialized
	case idle
	case discovering
	case connecting
	case retrying(attempt: Int)
	case retrievingDatabase(nodeCount: Int)
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
		case .retrievingDatabase(let nodeCount):
			return "Retreiving nodes \(nodeCount)"
		}
	}
}

@MainActor
class AccessoryManager: ObservableObject, MqttClientProxyManagerDelegate {
	// Singleton Access.  Conditionally compiled
#if targetEnvironment(macCatalyst)
	static let shared = AccessoryManager(transports: [BLETransport(), TCPTransport(), SerialTransport()])
#else
	static let shared = AccessoryManager(transports: [BLETransport(), TCPTransport()])
#endif
	
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
	public var wantRangeTestPackets = false
	var wantStoreAndForwardPackets = false
	var shouldAutomaticallyConnectToPreferredPeripheral = true
	
	// Conncetion process
	var connectionSteps: SequentialSteps?
	
	// Public due to file separation
	var discoveryTask: Task<Void, Never>?
	var connectionEventTask: Task <Void, Error>?
	var locationTask: Task<Void, Error>?
	var connectionStepper: SequentialSteps?
	
	// Flash subjects
	@Published var packetsSent: Int = 0
	@Published var packetsReceived: Int = 0
	
	// Continuations
	var wantConfigContinuation: CheckedContinuation<Void, Error>?
	var firstDatabaseNodeInfoContinuation: CheckedContinuation<Void, Error>?
	var wantDatabaseGate: AsyncGate = AsyncGate()

	// Misc
	@Published var expectedNodeDBSize: Int?
	
	var heartbeatTimer: ResettableTimer?
	var heartbeatResponseTimer: ResettableTimer?
	
	init(transports: [any Transport] = [BLETransport(), TCPTransport()]) {
		self.transports = transports
		self.state = .uninitialized
		self.mqttManager.delegate = self
	}

	func transportForType(_ type: TransportType) -> Transport? {
		return transports.first(where: {$0.type == type })
	}
	
	func connectToPreferredDevice() {
		if !self.isConnected && !self.isConnecting,
		   let preferredDevice = self.devices.first(where: { $0.id.uuidString == UserDefaults.preferredPeripheralId }) {
			Task { try await self.connect(to: preferredDevice) }
		}
	}

	func sendWantConfig() async throws {
		if let inProgressWantConfigContinuation = wantConfigContinuation {
			Logger.transport.info("[Accessory] Existing continuation for wantConfig(Config). Cancelling.")
			inProgressWantConfigContinuation.resume(throwing: CancellationError())
			wantConfigContinuation = nil
		}
		guard let connection = activeConnection?.connection else {
			Logger.transport.error("Unable to send wantConfig (config): No device connected")
			return
		}

		_ = clearStaleNodes(nodeExpireDays: Int(UserDefaults.purgeStaleNodeDays), context: self.context)
		
		try await withTaskCancellationHandler {
			var toRadio: ToRadio = ToRadio()
			toRadio.wantConfigID = UInt32(NONCE_ONLY_CONFIG)
			try await self.send(toRadio)
			try await connection.startDrainPendingPackets()
			try await withCheckedThrowingContinuation { cont in
				self.wantConfigContinuation = cont
			}
			self.wantConfigContinuation = nil
			Logger.transport.info("✅ [Accessory] NONCE_ONLY_CONFIG Done")
		} onCancel: {
			Task { @MainActor in
				wantConfigContinuation?.resume(throwing: CancellationError())
				wantConfigContinuation = nil
			}
		}
	}

	func sendWantDatabase() async throws {
		if let firstDatabaseNodeInfoContinuation = firstDatabaseNodeInfoContinuation {
			Logger.transport.info("[Accessory] Existing continuation for firstDatabaseNodeInfo. Cancelling.")
			firstDatabaseNodeInfoContinuation.resume(throwing: CancellationError())
			self.firstDatabaseNodeInfoContinuation = nil
		}
		
		guard let connection = activeConnection?.connection else {
			Logger.transport.error("Unable to send wantConfig (Database): No device connected")
			return
		}
		
		try await withTaskCancellationHandler {
			var toRadio: ToRadio = ToRadio()
			toRadio.wantConfigID = UInt32(NONCE_ONLY_DB)
			try await self.send(toRadio)
			try await connection.startDrainPendingPackets()
			try await withCheckedThrowingContinuation { cont in
				firstDatabaseNodeInfoContinuation = cont
			}
			firstDatabaseNodeInfoContinuation = nil
			Logger.transport.info("✅ [Accessory] NONCE_ONLY_DB first NodeInfo received.")
		} onCancel: {
			Task { @MainActor in
				firstDatabaseNodeInfoContinuation?.resume(throwing: CancellationError())
				firstDatabaseNodeInfoContinuation = nil
			}
		}
	}
	
	func waitForWantDatabaseResponse() async throws {
		try await wantDatabaseGate.wait()
	}

	// Fully tears down a connection and sets up the AccessoryManager for the next.
	// If you are calling this in response to an error, then you should have
	// exposed the error to the UI or handled the error prior to calling this.
	func closeConnection() async throws {
		Logger.transport.debug("[AccessoryManager] received disconnect request")

		if let activeConnection {
			updateDevice(deviceId: activeConnection.device.id, key: \.connectionState, value: .disconnected)
			self.activeConnection = nil
		}
		
		connectionEventTask?.cancel()
		connectionEventTask = nil
		
		locationTask?.cancel()
		locationTask = nil
		
		await heartbeatTimer?.cancel(withReason: "Closing connection")
		await heartbeatResponseTimer?.cancel(withReason: "Closing connection")
		heartbeatTimer = nil
		heartbeatResponseTimer = nil
		
		// Clean up continuations
		wantConfigContinuation?.resume(throwing: CancellationError())
		wantConfigContinuation = nil
		firstDatabaseNodeInfoContinuation?.resume(throwing: CancellationError())
		firstDatabaseNodeInfoContinuation = nil
		
		await wantDatabaseGate.cancelAll()
		await wantDatabaseGate.reset()
		
		// Turn off the disconnect buttons
		allowDisconnect = false
		self.startDiscovery()
	}
	
	// Should only be called by UI-facing callers.
	func disconnect() async throws {
		// Cancel ongoing connection task if it exists
		await self.connectionStepper?.cancel()

		// Close out the connection
		if let activeConnection = activeConnection {
			try await activeConnection.connection.disconnect(withError: nil, shouldReconnect: false)
		}
	}

	// Update device attributes on MainActor for presentation in the UI
	func updateDevice<T>(deviceId: UUID? = nil, key: WritableKeyPath<Device, T>, value: T) where T: Equatable {
		guard let deviceId = deviceId ?? self.activeConnection?.device.id else {
			Logger.transport.error("updateDevice<T> with nil deviceId")
			return
		}
		
		// Update the active device if the UUID's match
		if let activeConnection, activeConnection.device.id == deviceId {
			var device = activeConnection.device
			if device[keyPath: key] != value {
				// Update the @Published stuff for the UI
				self.objectWillChange.send()

				device[keyPath: key] = value
				self.activeConnection = (device: device, connection: activeConnection.connection)
				self.activeDeviceNum = device.num
			}
		}
		
		// Update the device in the devices array if it exists
		if let index = devices.firstIndex(where: { $0.id == deviceId }) {
			var device = devices[index]
			device[keyPath: key] = value
			if device[keyPath: key] != value {
				// Update the @Published stuff for the UI
				self.objectWillChange.send()
				
				if let index = devices.firstIndex(where: { $0.id == deviceId }) {
					devices[index] = device
				}
			}
		} else {
			// Durring active connections, this discover list will be empty, so this is expected.
			// Logger.transport.error("Device with ID \(deviceId) not found in devices list.")
		}

	}

	// Update state on MainActor for presentation in the UI
	func updateState(_ newState: AccessoryManagerState) {
#if DEBUG
		Logger.transport.info("🔗 Updating state from \(self.state.description, privacy: .public) to \(newState.description, privacy: .public)")
#endif
		switch newState {
		case .uninitialized, .idle, .discovering:
			self.isConnected = false
			self.isConnecting = false
		case .connecting, .communicating, .retrying:
			self.isConnected = false
			self.isConnecting = true
		case .subscribed, .retrievingDatabase:
			self.isConnected = true
			self.isConnecting = false
		}
		self.state = newState
	}

	func send(_ data: ToRadio, debugDescription: String? = nil) async throws {
		packetsSent += 1
		
		guard let active = activeConnection,
			  await active.connection.isConnected else {
			throw AccessoryError.connectionFailed("Not connected to any device")
		}
		try await active.connection.send(data)
		if let debugDescription {
			Logger.transport.info("📻 \(debugDescription, privacy: .public)")
		}
	}

	func didReceive(_ event: ConnectionEvent) {
		packetsReceived += 1
		
		switch event {
		case .data(let fromRadio):
			// Logger.transport.info("✅ [Accessory] didReceive: \(fromRadio.payloadVariant.debugDescription)")
			self.processFromRadio(fromRadio)
			Task {
				await self.heartbeatResponseTimer?.cancel(withReason: "Data packet received")
				await self.heartbeatTimer?.reset(delay: .seconds(15.0))
			}

		case .logMessage(let message):
			self.didReceiveLog(message: message)
			Task {
				await self.heartbeatResponseTimer?.cancel(withReason: "Log message packet received")
				await self.heartbeatTimer?.reset(delay: .seconds(15.0))
			}
		
		case .rssiUpdate(let rssi):
			guard let deviceId = self.activeConnection?.device.id else {
				Logger.transport.error("Could not update RSSI, no active connection")
				return
			}
			updateDevice(deviceId: deviceId, key: \.rssi, value: rssi)
			
		case .error(let error), .errorWithoutReconnect(let error):
			Task {
				// Figure out if we'll reconnect
				if case .errorWithoutReconnect = event {
					shouldAutomaticallyConnectToPreferredPeripheral = false
				} else {
					shouldAutomaticallyConnectToPreferredPeripheral = true
				}
				
				Logger.transport.info("🚨 [Accessory] didReceive with failure: \(error.localizedDescription, privacy: .public) (willReconnect = \(self.shouldAutomaticallyConnectToPreferredPeripheral, privacy: .public))")

				lastConnectionError = error
				
				if let connectionStepper = self.connectionStepper {
					// If we're in the midst of a connection process, tell the stepper that something happened
					// This cancels retry connection attempts if we've been asked not to reconnect
					await connectionStepper.cancelCurrentlyExecutingStep(withError: error, cancelFullProcess: !shouldAutomaticallyConnectToPreferredPeripheral)
				} else {
					// Normal processing.  Expose the error and disconnect
					try? await self.closeConnection()
					
					// If we were actively reconnecting, then don't update the status because
					// we're in the midst of a reconnection flow
					if !(await self.connectionStepper?.isRunning ?? false) {
						updateState(.discovering)
					}
				}
			}
			
		case .disconnected:
			Task {
				// This is user-initatied, so don't reconnect
				shouldAutomaticallyConnectToPreferredPeripheral = false
				try? await self.closeConnection()
				updateState(.discovering)
			}
			Logger.transport.info("[Accessory] Connection reported user-initiated disconnect.")
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
			// All received packets get passed through updateAnyPacketFrom to update lastHeard, rxSnr, etc. (like firmware's NodeDB::updateFrom).
			if let connectedNodeNum = self.activeDeviceNum {
				updateAnyPacketFrom(packet: packet, activeDeviceNum: connectedNodeNum, context: context)
			} else {
				Logger.mesh.error("🕸️ Unable to determine connectedNodeNum for updateAnyPacketFrom. Skipping.")
			}

			// Dispatch based on packet contents.
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
					guard let connectedNodeNum = self.activeDeviceNum else {
						Logger.mesh.error("🕸️ Unable to determine connectedNodeNum for node info upsert.")
						return
					}
					if packet.from != connectedNodeNum {
						upsertNodeInfoPacket(packet: packet, context: context)
					} else {
						Logger.mesh.error("🕸️ Received a node info packet from ourselves over the mesh. Dropping.")
					}
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
				case .storeForwardPlusplusApp:
					Logger.mesh.info("🕸️ MESH PACKET received for SFPP App UNHANDLED UNHANDLED")
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
#if DEBUG
			Logger.mesh.info("🕸️ MESH PACKET received for deviceUIConfig UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
#endif
		case .fileInfo:
#if DEBUG
			Logger.mesh.info("🕸️ MESH PACKET received for fileInfo UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
#endif
		case .queueStatus:
#if DEBUG
			Logger.mesh.info("🕸️ MESH PACKET received for queueStatus \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
#else
			Logger.mesh.info("🕸️ MESH PACKET received for heartbeat response")
#endif
		case .logRecord(let record):
			didReceiveLog(message: record.stringRepresentation)
			
		case .configCompleteID(let configCompleteID):
			// Not sure if we want to do anythign here directly?  The continuation stuff lets you
			// do the next step right in the connection flow.

			// switch configCompleteID {
			// case UInt32(NONCE_ONLY_CONFIG):
			//	break;
			// case UInt32(NONCE_ONLY_DB):
			// case UInt32(NONCE_ONLY_DB):
			// 	break;
			// break:
			// Logger.mesh.error("✅ [Accessory] Unknown UNHANDLED confligCompleteID: \(configCompleteID)")
			// }

			Logger.transport.info("✅ [Accessory] Notifying completions that have completed for configCompleteID: \(configCompleteID)")
			switch configCompleteID {
			case UInt32(NONCE_ONLY_CONFIG):
				if let continuation = wantConfigContinuation {
					continuation.resume()
				}
				
			case UInt32(NONCE_ONLY_DB):
				// Open the gate for the wantDatabaseContinuation
				Task { await wantDatabaseGate.open() }
				
				// If we get the "done" for NONCE_ONLY_DB, but are still waiting for the first NodeInfo,
				// Then the database is probably empty, and can continue
				if let firstDatabaseNodeInfoContinuation {
					firstDatabaseNodeInfoContinuation.resume()
					self.firstDatabaseNodeInfoContinuation = nil
				}
				
				// Perform a single batch save after database retrieval completes
				// This significantly improves performance on reconnect
				do {
					try context.save()
					Logger.data.info("💾 [Database] Batch saved all node info after database retrieval")
				} catch {
					context.rollback()
					let nsError = error as NSError
					Logger.data.error("💥 [Database] Error saving batch node info: \(nsError, privacy: .public)")
				}
				
			default:
				Logger.transport.error("[Accessory] Unknown nonce completed: \(configCompleteID)")
			}
			
		case .rebooted:
			// If we had an existing connection, then we can probably get away with just a wantConfig?
			if state == .subscribed {
				Task { try? await sendWantConfig() }
			}
			
		default:
			Logger.mesh.error("Unknown FromRadio variant: \(decodedInfo.payloadVariant.debugDescription)")
		}

	}
}

extension AccessoryManager {
	var connectedVersion: String? {
		return activeConnection?.device.firmwareVersion
	}

	var connectedDeviceRole: DeviceRoles? {
		guard let connectedNodeNum = activeDeviceNum else { return nil }
		guard let connectedNode = getNodeInfo(id: connectedNodeNum, context: context) else { return nil }
		guard let connectedNodeUser = connectedNode.user else { return nil }
		return DeviceRoles(rawValue: Int(connectedNodeUser.role))
	}

	func checkIsVersionSupported(forVersion: String) -> Bool {
		let myVersion = connectedVersion ?? "0.0.0"
		let supportedVersion = UserDefaults.firmwareVersion == "0.0.0" ||
		forVersion.compare(myVersion, options: .numeric) == .orderedAscending ||
		forVersion.compare(myVersion, options: .numeric) == .orderedSame
		return supportedVersion
	}
}

extension AccessoryManager {
	func setupPeriodicHeartbeat() async {
		if heartbeatTimer != nil {
			Logger.transport.debug("💓 [Heartbeat] Cancelling existing heartbeat timer")
			await self.heartbeatTimer?.cancel(withReason: "Duplicate setup, cancelling previous timer")
			self.heartbeatTimer = nil
		}
		
		self.heartbeatTimer = ResettableTimer(isRepeating: true, debugName: Bundle.main.isDebug ? "Send Heartbeat" : nil) {
			Logger.transport.debug("💓 [Heartbeat] Sending periodic heartbeat")
			try? await self.sendHeartbeat()
		}
		
		// We can send heartbeats for older versions just fine, but only 2.7.4 and up will respond with
		// a definite queueStatus packet.
		if self.checkIsVersionSupported(forVersion: "2.7.4") {
			self.heartbeatResponseTimer = ResettableTimer(isRepeating: false, debugName: Bundle.main.isDebug ? "Heartbeat Timeout" : nil) { @MainActor in
				Logger.transport.error("💓 [Heartbeat] Connection Timeout: Did not receive a packet after heartbeat.")
				// If we're in the middle of a connection cancel it.
				await self.connectionStepper?.cancel()
				
				// Close out the connection
				if let activeConnection = self.activeConnection {
					try? await activeConnection.connection.disconnect(withError: AccessoryError.timeout, shouldReconnect: true)
				} else {
					self.lastConnectionError = AccessoryError.timeout
					try? await self.closeConnection()
				}
			}
		}
		await self.heartbeatTimer?.reset(delay: .seconds(15.0))
	}
}

enum PossiblyAlreadyDoneContinuation {
	case alreadyDone
	case notDone(CheckedContinuation<Void, Error>)
}

extension AccessoryManager {
	func appDidEnterBackground() {
		if self.state == .uninitialized { return }
		if let connection = self.activeConnection?.connection {
			Logger.transport.info("[AccessoryManager] informing active connection that we are entering the background")
			Task { await connection.appDidEnterBackground() }
		} else {
			Logger.transport.info("[AccessoryManager] suspending scanning while in the background")
			stopDiscovery()
		}
	}
	
	func appDidBecomeActive() {
		if self.state == .uninitialized { return }
		if let connection = self.activeConnection?.connection {
			Logger.transport.info("[AccessoryManager] informing previously active connection that we are active again")
			Task { await connection.appDidBecomeActive() }
		} else {
			if self.discoveryTask == nil {
				Logger.transport.info("[AccessoryManager] Previosuly in the background but not scanning, starting scanning again")
				self.startDiscovery()
			}
		}
	}
}
