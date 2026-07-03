//
//  AccessoryManager.swift
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import SwiftUI
import SwiftData
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
	case retrying(attempt: Int, maxAttempts: Int)
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
		case .retrying(let attempt, let maxAttempts):
			return "Retrying Connection (\(attempt) of \(maxAttempts))"
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
	let minimumVersion = "2.5.18"
	let securityVersion = "2.6.0"

	// Global Objects
	// Chicken/Egg problem.  Set in the App object immediately after
	// AppState and AccessoryManager are created
	var appState: AppState!
	lazy var context = PersistenceController.shared.context
	let mqttManager = MqttClientProxyManager.shared

	// MARK: - Database reset

	/// Call after a full data clear (clear app data / device reset / node switch). Reopens the
	/// SwiftData container fresh and repoints the MeshPackets actor and this manager's cached
	/// `context` at it, so no long-lived context keeps stale objects that would trap
	/// ("destroyed by ModelContext.reset") when a reconnect reuses freed SQLite rowids.
	func repointToFreshContainer() {
		PersistenceController.shared.recreateContainer()
		MeshPackets.recreateShared()
		context = PersistenceController.shared.context
	}

	/// `repointToFreshContainer()` plus a UI refresh: bumps `databaseResetID` so @Query-backed
	/// views rebind to the recreated container. Use at clear sites with no follow-up reconnect;
	/// the node-switch flow repoints first and refreshes the UI itself after its restore.
	///
	/// Pops every tab to its root and yields *before* recreating the container. Detail views such
	/// as `ChannelMessageList` bind a `@Bindable ChannelEntity` directly; if one is still mounted
	/// when the container is torn down, reading that now-invalid object traps with "This model
	/// instance was destroyed by calling ModelContext.reset". Popping + yielding lets SwiftUI
	/// unmount those views first. Mirrors the node-switch flow in `backupCurrentAndRestoreDatabase`
	/// (Views/Connect/Connect.swift).
	func resetDatabaseAfterClear() async {
		// `appState` (and its `router`) are wired up at launch and are required for the safety
		// guarantee here. Bail loudly rather than recreating the container without first popping the
		// detail views: a half-done reset (container torn down, views still mounted) would
		// reintroduce the exact ModelContext.reset crash this method exists to prevent. The data was
		// already cleared by the preceding `clearDatabase`, so skipping the container swap is the
		// safe degradation.
		guard let appState else {
			Logger.data.error("💾 [Database] resetDatabaseAfterClear skipped: appState is nil — cannot pop views before recreating the container")
			return
		}
		let router = appState.router
		router.popToRoot(tab: .messages)
		router.popToRoot(tab: .nodes)
		router.popToRoot(tab: .map)
		router.popToRoot(tab: .settings)
		await Task.yield()
		repointToFreshContainer()
		appState.databaseResetID = UUID()
	}

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
	@Published var isInBackground: Bool = false
	@Published var firmwareEdition: FirmwareEditions = .vanilla

	/// MESHTASTIC_LOCKDOWN-hardened firmware state machine. See
	/// Meshtastic/Helpers/LockdownCoordinator.swift and
	/// specs/007-lockdown-mode/. Set by MeshtasticApp at startup.
	var lockdownCoordinator: LockdownCoordinator?

	/// Region → legal-preset lookup advertised by the connected radio during the
	/// want_config handshake (FromRadio.region_presets, 2.8+). Empty when the
	/// firmware predates the feature or hasn't sent it yet — callers must treat an
	/// absent region (or an empty map) as "no constraint". Reset on disconnect.
	@Published var loRaRegionPresets: [Config.LoRaConfig.RegionCode: RegionPresetInfo] = [:]

	var activeConnection: (device: Device, connection: any Connection)?

	/// Reference to the active discovery scan engine, if any
	var discoveryScanEngine: DiscoveryScanEngine?

	/// Shared discovery scan engine that persists across navigation
	let discoveryEngine = DiscoveryScanEngine()

	let transports: [any Transport]

	// Config
	public var wantRangeTestPackets = false
	var wantStoreAndForwardPackets = false
	var shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
	var userRequestedConnectionCancellation = false

	// Conncetion process
	var connectionSteps: SequentialSteps?
	
	// Public due to file separation
	var otaInProgress: Bool = false
	var discoveryTask: Task<Void, Never>?
	var connectionEventTask: Task <Void, Error>?
	var locationTask: Task<Void, Error>?
	var connectionStepper: SequentialSteps?
	
	// Flash counters — NOT @Published to avoid triggering re-renders of all observing views.
	// RXTXIndicatorWidget observes these via onChange polling.
	var packetsSent: Int = 0
	var packetsReceived: Int = 0
	
	// Continuations
	var wantConfigContinuation: CheckedContinuation<Void, Error>?
	var firstDatabaseNodeInfoContinuation: CheckedContinuation<Void, Error>?
	var wantDatabaseGate: AsyncGate = AsyncGate()

	// Misc
	@Published var expectedNodeDBSize: Int?
	
	var heartbeatTimer: ResettableTimer?
	var heartbeatResponseTimer: ResettableTimer?
	/// How long a TCP/serial connection may sit idle (no data or log packets) before we send a
	/// keep-alive heartbeat. The timer is resettable, so an active link never sends one — heartbeats
	/// only fire after this much silence. BLE does not use this at all (Core Bluetooth manages the
	/// link); see `Transport.requiresPeriodicHeartbeat`.
	static let heartbeatInterval: TimeInterval = 15.0
	private var isClosingConnection = false

	init(transports: [any Transport] = [BLETransport(), TCPTransport()]) {
		self.transports = transports
		self.state = .uninitialized
		self.mqttManager.delegate = self

		// Listen for system memory warnings to proactively save pending changes
		if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
			NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
				guard let self else { return }
				try? self.context.save()
				Logger.data.warning("⚠️ [AccessoryManager] Memory warning — saved context")
			}
		}
	}

	func transportForType(_ type: TransportType) -> Transport? {
		return transports.first(where: {$0.type == type })
	}
	
	func connectToPreferredDevice(device: Device? = nil) {
		if !self.isConnected && !self.isConnecting,
		   let preferredDevice = device ?? self.devices.first(where: { $0.id.uuidString == UserDefaults.preferredPeripheralId }) {
			Task {
				try await self.connect(to: preferredDevice)
			}
		}
	}

	func sendWantConfig() async throws {
		if let inProgressWantConfigContinuation = wantConfigContinuation {
			Logger.transport.info("[Accessory] Existing continuation for wantConfig(Config). Cancelling.")
			wantConfigContinuation = nil
			inProgressWantConfigContinuation.resume(throwing: CancellationError())
		}
		guard let connection = activeConnection?.connection else {
			Logger.transport.error("Unable to send wantConfig (config): No device connected")
			return
		}

		_ = await MeshPackets.shared.clearStaleNodes(nodeExpireDays: Int(UserDefaults.purgeStaleNodeDays))
		
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
				if let continuation = wantConfigContinuation {
					wantConfigContinuation = nil
					continuation.resume(throwing: CancellationError())
				}
			}
		}
	}

	func sendWantDatabase() async throws {
		if let firstDatabaseNodeInfoContinuation = firstDatabaseNodeInfoContinuation {
			Logger.transport.info("[Accessory] Existing continuation for firstDatabaseNodeInfo. Cancelling.")
			self.firstDatabaseNodeInfoContinuation = nil
			firstDatabaseNodeInfoContinuation.resume(throwing: CancellationError())
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
				if let continuation = firstDatabaseNodeInfoContinuation {
					firstDatabaseNodeInfoContinuation = nil
					continuation.resume(throwing: CancellationError())
				}
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
		guard !isClosingConnection else {
			Logger.transport.debug("[AccessoryManager] closeConnection ignored while teardown is already in progress")
			return
		}
		isClosingConnection = true
		defer { isClosingConnection = false }

		Logger.transport.debug("[AccessoryManager] received disconnect request")

		if let activeConnection {
			updateDevice(deviceId: activeConnection.device.id, key: \.connectionState, value: .disconnected)
			self.activeConnection = nil
		}
		self.activeDeviceNum = nil

		// Lockdown: clear per-connection state. If a Lock Now was in flight, the
		// disconnect resolves the coordinator to `.lockNowAcknowledged`.
		lockdownCoordinator?.onDisconnect()
		
		connectionEventTask?.cancel()
		connectionEventTask = nil
		
		locationTask?.cancel()
		locationTask = nil
		
		await heartbeatTimer?.cancel(withReason: "Closing connection")
		await heartbeatResponseTimer?.cancel(withReason: "Closing connection")
		heartbeatTimer = nil
		heartbeatResponseTimer = nil
		
		// Clean up continuations — nil before resume to prevent double-resume races
		if let continuation = wantConfigContinuation {
			wantConfigContinuation = nil
			continuation.resume(throwing: CancellationError())
		}
		if let continuation = firstDatabaseNodeInfoContinuation {
			firstDatabaseNodeInfoContinuation = nil
			continuation.resume(throwing: CancellationError())
		}
		
		await wantDatabaseGate.cancelAll()
		await wantDatabaseGate.reset()

		// Stop the MQTT proxy so it doesn't forward broker packets over BLE during reconnect,
		// which would starve the wantConfig handshake. initializeMqtt() restarts it in Step 8.
		// Disconnect unconditionally — mqttProxyConnected can be stale during a teardown race.
		mqttManager.mqttClientProxy?.disconnect()

		// Save any pending changes and let SwiftData manage object lifecycle on disconnect.
		try? context.save()
		Logger.data.info("💾 [AccessoryManager] Saved context on disconnect")
		
		// Turn off the disconnect buttons
		allowDisconnect = false
		
		// Cancel any existing discovery task so startDiscovery() always creates a fresh one.
		// Without this, if discovery was still running from before the connection attempt,
		// startDiscovery() would silently no-op and the device would never reappear in the list.
		discoveryTask?.cancel()
		discoveryTask = nil
		
		self.startDiscovery()
	}
	
	// Should only be called by UI-facing callers.
	func disconnect() async throws {
		guard !isClosingConnection else { return }
		self.userRequestedConnectionCancellation = true
		// Cancel ongoing connection task if it exists
		await self.connectionStepper?.cancel()

		// Flush any debounced position/telemetry saves before disconnecting
		await MeshPackets.shared.flushDebouncedSaves()

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
				
			}
			// Make sure activeDeviceNum is up to date.
			if key == \.num, self.activeDeviceNum != device.num {
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
			self.firmwareEdition = .vanilla
			self.loRaRegionPresets = [:]
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

	func didReceive(_ event: ConnectionEvent) async {
		let shouldIgnoreTransientEvent = isClosingConnection || userRequestedConnectionCancellation || activeConnection == nil

		packetsReceived += 1

		switch event {
		case .data(let fromRadio):
			guard !shouldIgnoreTransientEvent else {
				Logger.transport.debug("[Accessory] Dropping data event during disconnect teardown")
				return
			}
			// Logger.transport.info("✅ [Accessory] didReceive: \(fromRadio.payloadVariant.debugDescription)")
			await self.processFromRadio(fromRadio)
			Task {
				await self.heartbeatResponseTimer?.cancel(withReason: "Data packet received")
				await self.heartbeatTimer?.reset(delay: .seconds(Self.heartbeatInterval))
			}

		case .logMessage(let message):
			guard !shouldIgnoreTransientEvent else {
				Logger.transport.debug("[Accessory] Dropping log event during disconnect teardown")
				return
			}
			self.didReceiveLog(message: message)
			Task {
				await self.heartbeatResponseTimer?.cancel(withReason: "Log message packet received")
				await self.heartbeatTimer?.reset(delay: .seconds(Self.heartbeatInterval))
			}
		
		case .rssiUpdate(let rssi):
			guard !shouldIgnoreTransientEvent else {
				Logger.transport.debug("[Accessory] Dropping RSSI update during disconnect teardown")
				return
			}
			guard let deviceId = self.activeConnection?.device.id else {
				Logger.transport.error("Could not update RSSI, no active connection")
				return
			}
			updateDevice(deviceId: deviceId, key: \.rssi, value: rssi)
			
		case .error(let error), .errorWithoutReconnect(let error):
			Task {
				// Figure out if we'll reconnect
				if case .errorWithoutReconnect = event {
					shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
				} else {
					shouldAutomaticallyConnectToPreferredPeripheralAfterError = true
				}
				
				Logger.transport.info("🚨 [Accessory] didReceive with failure: \(error.localizedDescription, privacy: .public) (willReconnect = \(self.shouldAutomaticallyConnectToPreferredPeripheralAfterError, privacy: .public))")

				lastConnectionError = error
				
				if let connectionStepper = self.connectionStepper {
					// If we're in the midst of a connection process, tell the stepper that something happened
					// This cancels retry connection attempts if we've been asked not to reconnect
					await connectionStepper.cancelCurrentlyExecutingStep(withError: error, cancelFullProcess: !shouldAutomaticallyConnectToPreferredPeripheralAfterError)
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
				shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
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

	private func processFromRadio(_ decodedInfo: FromRadio) async {
		// Logger.transport.info("📻 [processFromRadio] Processing: \(String(describing: decodedInfo.payloadVariant), privacy: .public)")
		switch decodedInfo.payloadVariant {
		case .mqttClientProxyMessage(let mqttClientProxyMessage):
			handleMqttClientProxyMessage(mqttClientProxyMessage)

		case .clientNotification(let clientNotification):
			handleClientNotification(clientNotification)

		case .myInfo(let myNodeInfo):
			await handleMyInfo(myNodeInfo)

		case .packet(let packet):
			// All received packets get passed through updateAnyPacketFrom to update lastHeard, rxSnr, etc. (like firmware's NodeDB::updateFrom).
			if let connectedNodeNum = self.activeDeviceNum {
				await MeshPackets.shared.updateAnyPacketFrom(packet: packet, activeDeviceNum: connectedNodeNum)
			} else {
				Logger.mesh.error("🕸️ Unable to determine connectedNodeNum for updateAnyPacketFrom. Skipping.")
			}

			// Dispatch based on packet contents.
			if case let .decoded(data) = packet.payloadVariant {
				// Forward packets to discovery scan engine if active
				if let engine = discoveryScanEngine, engine.isScanning {
					engine.handleMeshPacket(packet, portNum: data.portnum)
				}

				switch data.portnum {
				case .textMessageApp, .detectionSensorApp, .alertApp:
					await handleTextMessageAppPacket(packet)
					// Broadcast text message to TAK clients
					if let text = String(bytes: data.payload, encoding: .utf8) {
						Logger.tak.debug("Text message received, calling broadcast")
						let server = TAKServerManager.shared
						if server.ensureBridgeReadyForMeshToCot() {
							await server.bridge?.broadcastMeshTextMessageToTAK(text: text, from: packet.from, channel: packet.channel, to: packet.to)
						}
					}
				case .remoteHardwareApp:
					Logger.mesh.info("[Remote Hardware] packet received from \(packet.from.toHex(), privacy: .public)")
				case .positionApp:
					await MeshPackets.shared.upsertPositionPacket(packet: packet)
					WatchSessionManager.shared.sendNodesToWatch()
					// Broadcast position to TAK clients
					if let position = try? Position(serializedBytes: data.payload) {
						Logger.tak.debug("Position received, calling broadcast")
						let server = TAKServerManager.shared
						if server.ensureBridgeReadyForMeshToCot() {
							await server.bridge?.broadcastMeshPositionToTAK(position: position, from: packet.from)
						}
					}
				case .waypointApp:
					Logger.tak.info("WAYPOINT APP CASE REACHED")
					await MeshPackets.shared.waypointPacket(packet: packet)
					// Broadcast waypoint to TAK clients
					if let waypoint = try? Waypoint(serializedBytes: data.payload) {
						Logger.tak.info("WAYPOINT PARSED: \(waypoint.name)")
						let server = TAKServerManager.shared
						if server.ensureBridgeReadyForMeshToCot() {
							await server.bridge?.broadcastMeshWaypointToTAK(waypoint: waypoint, from: packet.from)
						} else {
							Logger.tak.info("Waypoint broadcast skipped: server not ready or no clients")
						}
					}
				case .nodeinfoApp:
					guard let connectedNodeNum = self.activeDeviceNum else {
						Logger.mesh.error("🕸️ Unable to determine connectedNodeNum for node info upsert.")
						return
					}
					if packet.from != connectedNodeNum {
						await MeshPackets.shared.upsertNodeInfoPacket(packet: packet)
					} else {
						Logger.mesh.error("🕸️ Received a node info packet from ourselves over the mesh. Dropping.")
					}
				case .routingApp:
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for routingPacket.")
						return
					}
					await MeshPackets.shared.routingPacket(packet: packet, connectedNodeNum: deviceNum)
				case .adminApp:
					await MeshPackets.shared.adminAppPacket(packet: packet)
				case .replyApp:
					Logger.mesh.info("[Reply] packet received from \(packet.from.toHex(), privacy: .public)")
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for replyApp.")
						return
					}
					await MeshPackets.shared.textMessageAppPacket(packet: packet, wantRangeTestPackets: wantRangeTestPackets, connectedNode: deviceNum, appState: appState)
				case .ipTunnelApp:
					Logger.mesh.info("[IP Tunnel] packet received from \(packet.from.toHex(), privacy: .public)")
				case .serialApp:
					Logger.mesh.info("[Serial] packet received from \(packet.from.toHex(), privacy: .public)")
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
						await MeshPackets.shared.textMessageAppPacket(
							packet: packet,
							wantRangeTestPackets: true,
							connectedNode: deviceNum,
							appState: appState
						)
					} else {
						Logger.mesh.info("[Range Test] packet received from \(packet.from.toHex(), privacy: .public)")
					}
				case .telemetryApp:
					guard let deviceNum = activeConnection?.device.num else {
						Logger.mesh.error("🕸️ No active connection. Unable to determine connectedNodeNum for telemetryApp.")
						return
					}
					await MeshPackets.shared.telemetryPacket(packet: packet, connectedNode: deviceNum)
				case .textMessageCompressedApp:
					Logger.mesh.info("[Text Message Compressed] packet received from \(packet.from.toHex(), privacy: .public)")
				case .zpsApp:
					Logger.mesh.info("[Zero Positioning System] packet received from \(packet.from.toHex(), privacy: .public)")
				case .privateApp:
					Logger.mesh.info("[Private] packet received from \(packet.from.toHex(), privacy: .public)")
				case .atakForwarder:
					handleATAKForwarderPacket(packet)
				case .simulatorApp:
					Logger.mesh.info("[Simulator] packet received from \(packet.from.toHex(), privacy: .public)")
				case .storeForwardPlusplusApp:
					Logger.mesh.info("[SFPP] packet received from \(packet.from.toHex(), privacy: .public)")
				case .audioApp:
					Logger.mesh.info("[Audio] packet received from \(packet.from.toHex(), privacy: .public)")
				case .nodeStatusApp:
					await MeshPackets.shared.upsertNodeStatusPacket(packet: packet)
				case .tracerouteApp:
					handleTraceRouteApp(packet)
				case .neighborinfoApp:
					if let neighborInfo = try? NeighborInfo(serializedBytes: decodedInfo.packet.decoded.payload) {
						if let engine = discoveryScanEngine, engine.isScanning {
							engine.handleNeighborInfo(neighborInfo, packet: decodedInfo.packet)
						} else {
							Logger.mesh.info("[Neighbor Info] packet received from \(packet.from.toHex(), privacy: .public) — \(neighborInfo.neighbors.count, privacy: .public) neighbors")
						}
					}
				case .paxcounterApp:
					await MeshPackets.shared.paxCounterPacket(packet: decodedInfo.packet)
				case .mapReportApp:
					Logger.mesh.info("[Map Report] packet received from \(packet.from.toHex(), privacy: .public)")
				case .meshBeaconApp:
					Logger.mesh.info("[Mesh Beacon] packet received from \(packet.from.toHex(), privacy: .public)")
				case .UNRECOGNIZED:
					Logger.mesh.info("[Unrecognized] packet received from \(packet.from.toHex(), privacy: .public)")
				case .max:
					Logger.services.info("MAX PORT NUM OF 511")
				case .atakPlugin:
					handleATAKPluginPacket(packet)
				case .atakPluginV2:
					handleATAKPluginV2Packet(packet)
				case .powerstressApp:
					Logger.mesh.info("[Power Stress] packet received from \(packet.from.toHex(), privacy: .public)")
				case .reticulumTunnelApp:
					Logger.mesh.info("[Reticulum Tunnel] packet received from \(packet.from.toHex(), privacy: .public)")
				case .keyVerificationApp:
					Logger.mesh.info("[Key Verification] packet received from \(packet.from.toHex(), privacy: .public)")
				case .cayenneApp:
					Logger.mesh.info("[Cayenne] packet received from \(packet.from.toHex(), privacy: .public)")
				case .groupalarmApp:
					Logger.mesh.info("[Group Alarm] packet received from \(packet.from.toHex(), privacy: .public)")
				case .lorawanBridge:
					Logger.mesh.info("[LoRaWAN Bridge] packet received from \(packet.from.toHex(), privacy: .public)")
				case .remoteShellApp:
					Logger.mesh.info("[Remote Shell] packet received from \(packet.from.toHex(), privacy: .public)")
				case .unknownApp:
					Logger.mesh.info("[Unknown] packet received from \(packet.from.toHex(), privacy: .public)")
				}
			}
			// Flush via the debouncer rather than saving immediately. This runs for
			// EVERY packet, so an immediate save here force-flushed the whole context
			// on every packet — defeating the position/telemetry debounce and firing a
			// main-context merge (and a full @Query re-sort) ~10×/sec under load. A
			// debounced flush coalesces these to ≤1 save / 2s (5s hard ceiling) and also
			// covers the updateAnyPacketFrom mutations for portnums with no dedicated handler.
			await MeshPackets.shared.scheduleDebouncedSave()

		case .nodeInfo(let nodeInfo):
			await handleNodeInfo(nodeInfo)

		case .channel(let channel):
			await handleChannel(channel)

		case .config(let config):
			await handleConfig(config)

		case .moduleConfig(let moduleConfig):
			await handleModuleConfig(moduleConfig)

		case .metadata(let metadata):
			await handleDeviceMetadata(metadata)

		case .regionPresets(let regionPresets):
			handleRegionPresets(regionPresets)

		case .deviceuiConfig:
#if DEBUG
			Logger.admin.info("🕸️ MESH PACKET received for deviceUIConfig UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
#endif
		case .fileInfo:
#if DEBUG
			Logger.admin.info("🕸️ MESH PACKET received for fileInfo UNHANDLED \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
#endif
		case .queueStatus:
#if DEBUG
			Logger.transport.info("🕸️ MESH PACKET received for queueStatus \((try? decodedInfo.packet.jsonString()) ?? "JSON Decode Failure", privacy: .public)")
#else
			Logger.transport.info("🕸️ MESH PACKET received for heartbeat response")
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
					wantConfigContinuation = nil
					continuation.resume()
				}
				
			case UInt32(NONCE_ONLY_DB):
				// Open the gate for the wantDatabaseContinuation
				Task { await wantDatabaseGate.open() }
				
				// If we get the "done" for NONCE_ONLY_DB, but are still waiting for the first NodeInfo,
				// Then the database is probably empty, and can continue
				if let firstDatabaseNodeInfoContinuation {
					self.firstDatabaseNodeInfoContinuation = nil
					firstDatabaseNodeInfoContinuation.resume()
				}
				
				// Perform a single batch save after database retrieval completes
				// This significantly improves performance on reconnect
				do {
					try context.save()
					Logger.data.info("💾 [Database] Batch saved all node info after database retrieval")

					// Push updated node data to the companion Watch app
					WatchSessionManager.shared.sendNodesToWatch()
				} catch {
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

		case .lockdownStatus(let status):
			// MESHTASTIC_LOCKDOWN-hardened firmware reports state after config_complete_id
			// (and again in response to each LockdownAuth admin command). Route to the
			// coordinator, which owns the per-connection state machine + passphrase cache.
			lockdownCoordinator?.handle(status)

		default:
			Logger.transport.error("Unknown FromRadio variant: \(decodedInfo.payloadVariant.debugDescription)")
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
		// Prefer the live `connectedVersion` (full string including build hash,
		// e.g. "2.8.0.3a0c08b"). Fall back to the persisted UserDefaults value
		// (stripped of trailing hash, e.g. "2.8.0") because
		// `activeConnection?.device.firmwareVersion` is briefly nil during
		// reconnects before `handleDeviceMetadata` repopulates it — using only
		// `connectedVersion` in that window collapses `myVersion` to "0.0.0"
		// and incorrectly returns false for every capability check.
		let storedVersion = UserDefaults.firmwareVersion
		let myVersion: String
		if let live = connectedVersion, !live.isEmpty {
			myVersion = live
		} else if storedVersion != "0.0.0" {
			myVersion = storedVersion
		} else {
			// No firmware info at all — be permissive (matches the prior
			// "first-launch" behavior; newer firmware is the common case).
			return true
		}

		let comparison = forVersion.compare(myVersion, options: .numeric)
		return comparison == .orderedAscending || comparison == .orderedSame
	}

	/// Whether the connected radio supports the v2 TAK port (ATAK_PLUGIN_V2 = 78)
	/// with TAKPacketV2 + zstd dictionary compression via TAKPacket-SDK.
	///
	/// Firmware **>= 2.8.0** supports v2 (full typed CoT payloads — PLI, GeoChat,
	/// DrawnShape, Marker, Route, Aircraft, Casevac, Emergency, Task — under
	/// the 237 B LoRa MTU). Firmware **<= 2.7.x** falls back to the legacy
	/// ATAK_PLUGIN port (72) with the original `TAKPacket` schema, which only
	/// supports PLI and GeoChat (no shapes, markers, routes, etc.).
	///
	/// Returns `true` when the firmware version is unknown (radio not yet
	/// handshook) since v2 is now the predominant firmware in the field.
	var supportsTAKv2: Bool {
		checkIsVersionSupported(forVersion: "2.8.0")
	}

	/// The Status Message module (`ModuleConfig.StatusMessageConfig` + the
	/// `NODE_STATUS_APP` broadcast) ships in firmware 2.8.0 (design#115). Gate the editor on
	/// it so we don't expose a broken/empty config screen on a *known* older firmware.
	/// `checkIsVersionSupported` is intentionally permissive when the version is unknown
	/// (first-launch / reconnect window) — matching every other capability gate here — so the
	/// editor still appears until the radio reports a confirmed sub-2.8.0 version.
	var supportsStatusMessage: Bool {
		checkIsVersionSupported(forVersion: "2.8.0")
	}
}

extension AccessoryManager {
	func setupPeriodicHeartbeat() async {
		if heartbeatTimer != nil {
			Logger.transport.debug("💓 [Heartbeat] Cancelling existing heartbeat timer")
			await self.heartbeatTimer?.cancel(withReason: "Duplicate setup, cancelling previous timer")
			self.heartbeatTimer = nil
		}
		
		// No debugName: this timer is reset on every received data/log packet, so a per-reset debug
		// line would flood the log on busy TCP/serial links. The meaningful "heartbeat sent" log
		// below still fires only when a heartbeat is actually sent (i.e. after an idle interval).
		self.heartbeatTimer = ResettableTimer(isRepeating: true) {
			Logger.transport.debug("💓 [Heartbeat] Sending periodic heartbeat")
			try? await self.sendHeartbeat()
		}
		
		// We can send heartbeats for older versions just fine, but only 2.7.4 and up will respond with
		// a definite queueStatus packet.
		if self.checkIsVersionSupported(forVersion: "2.7.4") {
			// No debugName: this timer is cancelled on every received data/log packet, so a per-cancel
			// debug line would flood the log on busy links. The timeout error below still fires if a
			// heartbeat truly goes unanswered.
			self.heartbeatResponseTimer = ResettableTimer(isRepeating: false) { @MainActor in
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
		await self.heartbeatTimer?.reset(delay: .seconds(Self.heartbeatInterval))
	}
}

enum PossiblyAlreadyDoneContinuation {
	case alreadyDone
	case notDone(CheckedContinuation<Void, Error>)
}

extension AccessoryManager {
	func appDidEnterBackground() {
		if self.state == .uninitialized { return }
		// Persist any debounced position/telemetry/nodeinfo changes before suspension,
		// since the debounce timer may not fire while backgrounded.
		Task { await MeshPackets.shared.flushDebouncedSaves() }
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
