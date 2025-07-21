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
	case ioFailed(String)
	case appError(String)
	// Transport-specific sub-errors can be nested
}

enum AccessoryManagerState: Equatable {
	case uninitialized
	case idle
	case discovering
	case connecting
	case retrying(attempt: Int)
	case communicating
	case subscribed
}

class AccessoryManager: ObservableObject, PacketDelegate, MqttClientProxyManagerDelegate {
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

	var activeConnection: (device: Device, connection: any Connection)?

	private let transports: [any Transport]

	private var discoveryTask: Task<Void, Never>?
	private var locationTask: Task<Void, Error>?
	private var wantConfigContinuations: [UInt32: CheckedContinuation<Void, Error>] = [:]

	// Config
	public var wantRangeTestPackets = true
	var wantStoreAndForwardPackets = false

	var isConnected: Bool {
		self.activeConnection?.connection.isConnected ?? false
	}

	init(transports: [any Transport] = [BLETransport(), TCPTransport()]) {
		self.transports = transports
		self.state = .uninitialized
		self.mqttManager.delegate = self
	}

	func startDiscovery() {
		stopDiscovery()
		updateState(.discovering)
		for transport in transports {
			if var wirelessTransport = transport as? any WirelessTransport {
				wirelessTransport.rssiDelegate = self
			}
		}
		discoveryTask = Task {
			var allDevices: [Device] = []
			for await newDevice in self.discoverAllDevices() {
				// Update existing device or add new
				if let index = allDevices.firstIndex(where: { $0.id == newDevice.id }) {
					let existing = allDevices[index]
					let updatedDevice = Device(id: existing.id,
											   name: newDevice.name,
											   transportType: existing.transportType,
											   identifier: existing.identifier,
											   connectionState: existing.connectionState,
											   rssi: newDevice.rssi)
					allDevices[index] = updatedDevice
				} else {
					allDevices.append(newDevice)
				}

				// Update the list of discovered devices on the main thread for presentation
				// in the user interface
				Task { @MainActor in
					self.devices = allDevices.sorted { $0.name < $1.name }
				}
			}
		}
	}

	func stopDiscovery() {
		discoveryTask?.cancel()
		updateState(.idle)
		discoveryTask = nil
		for transport in transports {
			if var wirelessTransport = transport as? any WirelessTransport {
				wirelessTransport.rssiDelegate = nil
			}
		}
	}

	private func discoverAllDevices() -> AsyncStream<Device> {
		AsyncStream { continuation in
			let tasks = transports.map { transport in
				Task {
					for await device in transport.discoverDevices() {
						continuation.yield(device)
					}
				}
			}
			continuation.onTermination = { _ in tasks.forEach { $0.cancel() } }
		}
	}

	func connectToPreferredDevice() -> Bool {
		// not implemented
		Logger.services.error("connectToPreferredDevice not implemented")
		return false
	}

	func connect(to device: Device) async throws {
		// Prevent new connection if one is active
		if activeConnection != nil {
			throw AccessoryError.connectionFailed("Already connected to a device")
		}

		// Update device state to connecting
		Task { @MainActor in
			updateState(.connecting)
			updateDevice(deviceId: device.id, key: \.connectionState, value: .connecting)
		}

		// Find the transport that handles this device
		guard let transport = transports.first(where: { $0.type == device.transportType }) else {
			updateDevice(deviceId: device.id, key: \.connectionState, value: .disconnected)
			throw AccessoryError.connectionFailed("No transport for type")
		}

		// Prepare to connect, 10 retries, 1 second in between each
		let maxRetries = 10
		let retryDelay: Duration = .seconds(1)

		// Start trying to connect
		Task { @MainActor in lastConnectionError = nil }
		var shouldRetry = true
		for attempt in 1...maxRetries {
			if attempt > 1 {
				Logger.services.info("Retrying connection to \(device.name) (\(attempt)/\(maxRetries))")
				Task { @MainActor in
					updateState(.retrying(attempt: attempt))
				}
			} else {
				Task { @MainActor in
					updateState(.connecting)
				}
			}

			do {
				// Ask the transport to connect to the device and return a connection
				var connection = try await transport.connect(to: device)

				// If this is a wireless connection, have it report the RSSI to the AccessoryManager
				if var wirelessConnection = connection as? any WirelessConnection {
					wirelessConnection.rssiDelegate = self
				}

				// Tell the connection to report its packets to the AccessoryManager
				connection.packetDelegate = self

				updateState(.communicating)

				activeConnection = (device: device, connection: connection)

				// Send Heartbeat before wantConfig
				var heartbeatToRadio: ToRadio = ToRadio()
				heartbeatToRadio.payloadVariant = .heartbeat(Heartbeat())
				try? await connection.send(heartbeatToRadio)

				await sendWantConfig()

				if UserDefaults.firstLaunch {
					UserDefaults.showDeviceOnboarding = true
				}

				await sendWantDatabase()

				Task { @MainActor in self.allowDisconnect = true }

				guard let firmwareVersion = activeConnection?.device.firmwareVersion else {
					throw AccessoryError.connectionFailed("Firmware version not available")
				}

				let lastDotIndex = firmwareVersion.lastIndex(of: ".")
				if lastDotIndex == nil {
					shouldRetry = false
					throw AccessoryError.connectionFailed("🚨" + "Update Your Firmware".localized)
				}

				let version = firmwareVersion[...(lastDotIndex ?? String.Index(utf16Offset: 6, in: firmwareVersion))]
				let connectedVersion = String(version.dropLast())
				UserDefaults.firmwareVersion = connectedVersion

				let supportedVersion = checkIsVersionSupported(forVersion: minimumVersion)
				if !supportedVersion {
					shouldRetry = false
					throw AccessoryError.connectionFailed("🚨" + "Update Your Firmware".localized)
				}

				// We have an active connection
				updateDevice(deviceId: device.id, key: \.connectionState, value: .connected)
				updateState(.subscribed)

				await initializeMqtt()
				initializeLocationProvider()

				return
			} catch {
				Logger.services.error("🚨 Connection ERROR: \(error)")
				Task { @MainActor in lastConnectionError = error }
				if attempt < maxRetries && shouldRetry {
					try? await Task.sleep(for: retryDelay)
					try? await self.disconnect()
				}
			}
		}
		updateDevice(deviceId: device.id, key: \.connectionState, value: .disconnected)
		throw lastConnectionError ?? AccessoryError.connectionFailed("Connection failed after retries")
	}

	func sendWantConfig() async {
		guard let connection = activeConnection?.connection else {
			Logger.mesh.error("Unable to send wantConfig (config): No device connected")
			return
		}
		try? await sendNonceRequest(nonce: UInt32(NONCE_ONLY_CONFIG), connection: connection)
		Logger.services.info("✅ [Accessory] NONCE_ONLY_CONFIG Done")
	}

	func sendWantDatabase() async {
		guard let connection = activeConnection?.connection else {
			Logger.mesh.error("Unable to send wantConfig (database) : No device connected")
			return
		}

		try? await sendNonceRequest(nonce: UInt32(NONCE_ONLY_DB), connection: connection)
		Logger.services.info("✅ [Accessory] NONCE_ONLY_DB Done")
	}

	private func sendNonceRequest(nonce: UInt32, connection: any Connection) async throws {
		// Create the protobuf with the wantConfigID nonce
		var toRadio: ToRadio = ToRadio()
		toRadio.wantConfigID = nonce

		// Send it to the radio
		try await self.send(data: toRadio)

		// Start draining packets in the background
		try connection.startDrainPendingPackets()

		// Wait for the nonce request to be completed before continuing
		try await withCheckedThrowingContinuation { cont in
			wantConfigContinuations[nonce] = cont
		}
	}

	func didDisconnect() {
		allowDisconnect = false

		startDiscovery()
	}

	func disconnect() async throws {
		guard let active = activeConnection else {
			return // No connection to disconnect
		}
		activeConnection = nil
		try await active.connection.disconnect()
		updateDevice(deviceId: active.device.id, key: \.connectionState, value: .disconnected)
		updateState(.idle)

		Task { @MainActor in
			didDisconnect()
		}
	}

	// Update device attributes on MainActor for presentation in the UI
	func updateDevice<T>(deviceId: UUID? = nil, key: WritableKeyPath<Device, T>, value: T) {
		guard let deviceId = deviceId ?? self.activeConnection?.device.id else {
			Logger.services.error("updateDevice<T> with nil deviceId")
			return
		}
		if let index = devices.firstIndex(where: { $0.id == deviceId }) {
			var device = devices[index]
			device[keyPath: key] = value

			if let activeConnection, activeConnection.device.id == device.id {
				self.activeConnection = (device: device, connection: activeConnection.connection)
			}

			// Update the @Published stuff for the UI
			Task { @MainActor in
				devices[index] = device
				activeDeviceNum = device.num
			}
		} else {
			Logger.services.error("Device with ID \(deviceId) not found in devices list.")
		}
	}

	// Update state on MainActor for presentation in the UI
	private func updateState(_ newState: AccessoryManagerState) {
		Task { @MainActor in
			self.state = newState
		}
	}

	func send(data: ToRadio, debugDescription: String? = nil) async throws {
		Logger.services.info("✅ [Accessory] Sending \(data.debugDescription)")
		guard let active = activeConnection,
			  active.connection.isConnected else {
			throw AccessoryError.connectionFailed("Not connected to any device")
		}
		try await active.connection.send(data)
		if let debugDescription {
			Logger.mesh.info("📻 \(debugDescription, privacy: .public)")
		}
	}

	func didReceive(result: Result<FromRadio, Error>) {
		Logger.services.info("✅ [Accessory] Received packet")
		switch result {
		case .success(let fromRadio):
			self.processFromRadio(fromRadio)

		case .failure(let error):
			// Handle error, perhaps log and disconnect
			print("Error receiving packet: \(error)")
			// try? await self.disconnect()
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

			Logger.services.info("✅ [Accessory] Notifying completions that have completed for confligCompleteID: \(configCompleteID)")
			if let continuation = wantConfigContinuations[configCompleteID] {
				wantConfigContinuations.removeValue(forKey: configCompleteID)
				continuation.resume()
			}

		default:
			Logger.services.error("Unknown FromRadio variant: \(decodedInfo.payloadVariant.debugDescription)")
		}

	}
}

extension AccessoryManager: RSSIDelegate {
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
		return await withCheckedContinuation { cont in
			Task { @MainActor in
				var positionPacket = Position()

				guard let lastLocation = LocationsHandler.shared.locationsArray.last else {
					cont.resume(returning: nil)
					return
				}

				if lastLocation == CLLocation(latitude: 0, longitude: 0) {
					cont.resume(returning: nil)
					return
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
				cont.resume(returning: positionPacket)
			}
		}
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
