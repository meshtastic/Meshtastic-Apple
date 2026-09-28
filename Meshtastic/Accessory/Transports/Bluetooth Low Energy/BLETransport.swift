//
//  BLETransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
@preconcurrency import SwiftData
@preconcurrency import CoreBluetooth
import SwiftUI
import OSLog

actor BLETransport: Transport {

	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
	private let kCentralRestoreID = "com.meshtastic.central"

	let type: TransportType = .ble
	private var centralManager: CBCentralManager!
	/// Dedicated serial queue for CBCentralManager delegate callbacks.
	/// Using a serial queue (instead of `.global()`) guarantees that delegate
	/// callbacks arrive in the order CoreBluetooth fires them, so the
	/// `Task { await … }` hops to the actor preserve that ordering.
	private let centralQueue = DispatchQueue(label: "com.meshtastic.ble.central", qos: .utility)
	private var discoveredPeripherals: [UUID: (peripheral: CBPeripheral, lastSeen: Date)] = [:]
	private var discoveredDeviceContinuation: AsyncStream<DiscoveryEvent>.Continuation?
	private let delegate: BLEDelegate
	// Feature 021: one entry per peripheral, so several radios can connect and stay connected at
	// once. Every CoreBluetooth callback is routed by the peripheral's identifier.
	private var connectingPeripherals: [UUID: CBPeripheral] = [:]
	private var activeConnections: [UUID: BLEConnection] = [:]
	private var connectContinuations: [UUID: CheckedContinuation<BLEConnection, Error>] = [:]
	/// The focused restore waiting for its peripheral's pending connect to finish. Only that
	/// peripheral's didConnect / didFailToConnect resumes it: restored radios alongside can have
	/// CoreBluetooth connects pending too (feature 021, T155).
	private var restoredConnect: (peripheralId: UUID, continuation: CheckedContinuation<Void, Error>)?
	/// Feature 021 (T062): peripherals iOS restored along with the focused one. The
	/// remembered-radio reconnect claims each through `connect(to:)`; any left unclaimed are
	/// released so a radio isn't held by a link nobody uses.
	private var restoredStandby: [UUID: CBPeripheral] = [:]
	private var setupCompleteGate: AsyncGate
	private var restoreInProgress: Bool = false
	var status: TransportStatus = .uninitialized {
		didSet {
			guard status != oldValue else { return }
			statusContinuation?.yield(status)
		}
	}
	/// Broadcasts every `status` change so `AccessoryManager` can mirror it onto a `@Published`
	/// property for the UI (see `statusUpdates()`, #2175). Actor-isolated state otherwise has no
	/// way to reach a SwiftUI view: `status` was already being corrected on `.poweredOff`
	/// (#2161/#2163), but nothing outside this actor could observe it.
	private var statusContinuation: AsyncStream<TransportStatus>.Continuation?
	/// Identifies which `statusUpdates()` call installed the current `statusContinuation`, so its
	/// `onTermination` only clears the continuation if a later subscriber hasn't already replaced
	/// it (`AsyncStream.Continuation` isn't `Equatable`, so identity can't be compared directly).
	private var statusSubscriptionGeneration = 0

	/// The exact message `status` settles on when CoreBluetooth reports `.poweredOff`. Kept as a
	/// shared constant so callers matching on it (`AccessoryManager.isBluetoothPoweredOff`) don't
	/// duplicate the string.
	static let poweredOffStatusMessage = "Bluetooth is powered off"

	private var cleanupTask: Task<Void, Never>?
	/// The radios whose connect has the scan paused (feature 021, T154): with several radios, one
	/// finishing or failing mustn't resume the scan while another is still in its pairing window.
	private var scanPausedForConnections: Set<UUID> = []
	private var scanningPausedForConnection: Bool { !scanPausedForConnections.isEmpty }
	private let discoverySetupHandler: (@Sendable () async -> Void)?
	
	// Transport properties
	let supportsManualConnection: Bool = false
	let requiresPeriodicHeartbeat = false
			
	/// - Parameter createCentralManagerImmediately: Pass `false` to skip creating the real
	///   `CBCentralManager` here, leaving it to `discoverDevices()` exactly as a `.notDetermined`
	///   authorization already does. Tests that drive `handleCentralState` directly need this: a
	///   real manager reports the host's actual Bluetooth state on its own schedule, and that
	///   incidental value lands in `status` at an unpredictable point mid-test.
	init(
		createCentralManagerImmediately: Bool = true,
		centralManager: CBCentralManager? = nil,
		discoverySetupHandler: (@Sendable () async -> Void)? = nil
	) {
		self.centralManager = centralManager
		self.discoverySetupHandler = discoverySetupHandler
		self.discoveredPeripherals = [:]
		self.discoveredDeviceContinuation = nil
		self.delegate = BLEDelegate()
		self.setupCompleteGate = AsyncGate()
		// Only create CBCentralManager immediately if Bluetooth authorization is already
		// determined. This avoids showing the system permission prompt before the
		// onboarding Bluetooth screen has a chance to present it in context.
		if centralManager == nil,
		   createCentralManagerImmediately,
		   CBCentralManager.authorization != .notDetermined {
			self.centralManager = CBCentralManager(
				delegate: delegate,
				queue: centralQueue,
				options: Self.centralManagerOptions(restoreIdentifier: kCentralRestoreID)
			)
		}
		self.delegate.setTransport(self)
	}

	private func setDiscoveredDeviceContinuation(_ cont: AsyncStream<DiscoveryEvent>.Continuation?) {
		self.discoveredDeviceContinuation = cont
	}

	private func createCentralManager() {
		centralManager = CBCentralManager(delegate: delegate,
										  queue: centralQueue,
										  options: Self.centralManagerOptions(restoreIdentifier: kCentralRestoreID)
		)
	}

	/// The options CBCentralManager is created with, factored out so the contents are testable
	/// without standing up a real CoreBluetooth stack (static + value-out, same pattern as
	/// `Connect.liveNode`).
	///
	/// `CBCentralManagerOptionShowPowerAlertKey` is explicitly `false`. BLE is one of several
	/// transports — discovery starts unconditionally on all of them at launch
	/// (`AccessoryManager.startDiscovery()`) regardless of which transport the user actually
	/// connects with — so leaving the (default-`true`) system "Bluetooth is turned off" alert
	/// enabled meant a TCP/WiFi-only user saw it on every launch. Presenting that alert also
	/// blips `scenePhase` (inactive/background then active), and `appDidBecomeActive()` restarts
	/// BLE discovery whenever there's no active connection yet — which re-triggers the alert,
	/// producing the dismiss/reappear loop reported in #2139. Suppressing the system alert here
	/// doesn't change BLE functionality: `BLETransport` already reacts to `.poweredOff` in
	/// `handleCentralState` and surfaces it as transport status, and the explicit onboarding
	/// "enable Bluetooth" flow (`BluetoothAuthorizationHelper`) uses its own default-options
	/// manager, so that user-initiated prompt still appears where it belongs.
	static func centralManagerOptions(restoreIdentifier: String) -> [String: Any] {
		[
			CBCentralManagerOptionRestoreIdentifierKey: restoreIdentifier,
			CBCentralManagerOptionShowPowerAlertKey: false
		]
	}

	/// Broadcasts `status` (starting with the current value) so `AccessoryManager` can mirror it
	/// onto a `@Published` property for the UI. Only one subscriber is expected — `AccessoryManager`
	/// is the sole owner — so a second call replaces the first's continuation.
	func statusUpdates() -> AsyncStream<TransportStatus> {
		statusSubscriptionGeneration += 1
		let generation = statusSubscriptionGeneration
		return AsyncStream { continuation in
			continuation.yield(status)
			self.statusContinuation = continuation
			continuation.onTermination = { [weak self] _ in
				Task { await self?.clearStatusContinuation(generation: generation) }
			}
		}
	}

	/// Only clears `statusContinuation` if no later `statusUpdates()` call has already replaced it
	/// — otherwise a slow-to-terminate old subscriber could null out a newer, still-live one.
	private func clearStatusContinuation(generation: Int) {
		guard generation == statusSubscriptionGeneration else { return }
		statusContinuation = nil
	}

	func discoverDevices() -> AsyncStream<DiscoveryEvent> {
		AsyncStream { cont in
			Task {
				await self.setDiscoveredDeviceContinuation(cont)

				// Create the CBCentralManager now if it was deferred (authorization was .notDetermined at init).
				if await self.centralManager == nil {
					await self.createCentralManager()
				}
				// This gate is opened when the CBCentralManager is in poweredOn state.
				// Its probably open already, but just to be sure in case we get here too quickly.
				try await self.setupCompleteGate.wait()
				await self.discoverySetupHandler?()
				
				if await !self.restoreInProgress && !self.scanningPausedForConnection {
					centralManager.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
					
					let peripherals = await self.discoveredPeripherals.values.map({$0.peripheral})
					for alreadyDiscoveredPeripheral in peripherals {
						let device = Device(id: alreadyDiscoveredPeripheral.identifier,
											name: alreadyDiscoveredPeripheral.name ?? "Unknown",
											transportType: .ble,
											identifier: alreadyDiscoveredPeripheral.identifier.uuidString)
						cont.yield(.deviceFound(device))
					}
				}
				await setupCleanupTask()
			}
			cont.onTermination = { _ in
				Logger.transport.error("🛜 [BLE] Discovery event stream has been canecelled.")
				Task {
					await self.stopScanning()
				}
			}
		}
	}
	
	private func setupCleanupTask() {
		if let task = self.cleanupTask {
			task.cancel()
		}
		self.cleanupTask = Task {
			while !Task.isCancelled {
				var keysToRemove: [UUID] = []
				for (deviceId, discoveryEntry) in self.discoveredPeripherals
				where Date().timeIntervalSince(discoveryEntry.lastSeen) > 30 {
						keysToRemove.append(deviceId)
				}
				for deviceId in keysToRemove {
					self.discoveredDeviceContinuation?.yield(.deviceLost(deviceId))
					self.discoveredPeripherals.removeValue(forKey: deviceId)
				}
		
				try? await Task.sleep(for: .seconds(15)) // Cleanup every 15 seconds
			}
			Logger.transport.debug("🛜 [BLE] Discovery clean up task has been canecelled.")
		}
	}

	private func stopScanning() {
		Logger.transport.debug("🛜 [BLE] Stop Scanning: BLE Discovery has been stopped.")
		scanPausedForConnections.removeAll()
		guard centralManager != nil else {
			discoveredPeripherals.removeAll()
			discoveredDeviceContinuation = nil
			cleanupTask?.cancel()
			cleanupTask = nil
			return
		}
		centralManager.stopScan()
		discoveredPeripherals.removeAll()
		discoveredDeviceContinuation = nil
		if centralManager.state == .poweredOn {
			status = .ready
		} else {
			status = .uninitialized
		}
		cleanupTask?.cancel()
		cleanupTask = nil
	}

	func handleCentralState(_ state: CBManagerState, central: CBCentralManager) {
		Logger.transport.error("🛜 [BLE] State has transitioned to: \(cbManagerStateDescription(state), privacy: .public)")
		switch state {
		case .poweredOn:
			if !activeConnections.isEmpty {
				Logger.transport.info("🛜 [BLE] CBManager has poweredOn with \(self.activeConnections.count) already active connection(s)")
			}
			status = .discovering
			
			// Open the gate, so anyone who was waiitng for poweredOn can continue
			Task { await self.setupCompleteGate.open() }
			
			if self.discoveredDeviceContinuation != nil,
			   !restoreInProgress,
			   !scanningPausedForConnection {
				// We have someone already subscribed to our discovery event stream.
				// Likely a powerOff event occcurred and need to now restore scanning.
				central.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
			}

		case .poweredOff:
			// Leave status settled on .error rather than immediately overwriting it — this used
			// to be clobbered by a trailing `status = .ready` a few lines below, so BLE-off was
			// never actually observable via `status` (issue #2161). `.ready` elsewhere in this
			// file (see `stopScanning()`) means "poweredOn and available", which powered-off is
			// the opposite of, so `.error` here also matches this file's own convention for
			// every other non-powered-on state (.unauthorized, .unsupported, .resetting, etc.).
			status = .error(Self.poweredOffStatusMessage)
			let pending = connectContinuations
			connectContinuations.removeAll()
			connectingPeripherals.removeAll()
			for continuation in pending.values {
				continuation.resume(throwing: AccessoryError.disconnected("Bluetooth powered off"))
			}
			for connection in activeConnections.values {
				Task {
					Logger.transport.error("🛜 [BLE] Bluetooth has powered off during active connection. Cleaning up.")
					try await connection.disconnect(withError: AccessoryError.disconnected("Bluetooth powered off"), shouldReconnect: true)
					await self.connectionDidDisconnect(fromPeripheral: connection.peripheral)
				}
			}

			// Close the gate to make people wait
			Task { await setupCompleteGate.reset() }

		case .unauthorized:
			status = .error("Bluetooth access is unauthorized")
			Task { await self.setupCompleteGate.throwAll(AccessoryError.connectionFailed("Bluetooth is unauthorized")) }

		case .unsupported:
			status = .error("Bluetooth is unsupported on this device")
			Task { await self.setupCompleteGate.throwAll(AccessoryError.connectionFailed("Bluetooth is unsupported"))}

		case .resetting:
			status = .error("Bluetooth is resetting")
			// Perhaps don't finish, wait for next state

		case .unknown:
			status = .error("Bluetooth state is unknown")
			// Perhaps wait
		@unknown default:
			status = .error("Unknown Bluetooth state")
			Task { await self.setupCompleteGate.throwAll(AccessoryError.connectionFailed("Unknown Bluetooth State"))}
		}
	}

	func didDiscover(peripheral: CBPeripheral, rssi: NSNumber) {
		guard !restoreInProgress else { return }
		
		let id = peripheral.identifier
		let isNew = discoveredPeripherals[id] == nil
		if isNew {
			discoveredPeripherals[id] = (peripheral, Date())
		}
		let device = Device(id: id,
							name: peripheral.name ?? "Unknown",
							transportType: .ble,
							identifier: id.uuidString,
							rssi: rssi.intValue)
		if isNew {
			Logger.transport.debug("🛜 [BLE] Did Discover new device: \(peripheral.name ?? "Unknown", privacy: .public) (\(peripheral.identifier, privacy: .public))")
			discoveredDeviceContinuation?.yield(.deviceFound(device))
		} else {
			let rssiVal = rssi.intValue
			let deviceId = id
			discoveredPeripherals[id]?.lastSeen = Date()
			discoveredDeviceContinuation?.yield(.deviceReportedRssi(deviceId, rssiVal))
		}
	}

	func cancelConnectContinuation(for peripheral: CBPeripheral) {
		let id = peripheral.identifier
		guard let continuation = connectContinuations.removeValue(forKey: id) else { return }
		connectingPeripherals.removeValue(forKey: id)
		continuation.resume(throwing: CancellationError())
	}

	/// Feature 021 (T063): gives up a connect CoreBluetooth still has pending, after a
	/// bounded reconnect attempt to an out-of-range radio timed out. Cancelling the task only
	/// resumes the waiter; without this, CoreBluetooth would complete the link later with nobody
	/// owning it. Leaves the peripheral alone if a newer attempt or a live connection has it.
	func abandonPendingConnect(to deviceId: UUID) {
		guard activeConnections[deviceId] == nil, connectContinuations[deviceId] == nil else { return }
		connectingPeripherals.removeValue(forKey: deviceId)
		guard let peripheral = discoveredPeripherals[deviceId]?.peripheral
				?? centralManager?.retrievePeripherals(withIdentifiers: [deviceId]).first else { return }
		Logger.transport.debug("🛜 [BLE] Abandoning the pending connect to \(deviceId.uuidString, privacy: .public)")
		centralManager?.cancelPeripheralConnection(peripheral)
		resumeScanningAfterFailedConnection(for: deviceId)
	}

	/// True while this peripheral is connecting or connected (feature 021: other peripherals can be).
	private func isBusy(_ id: UUID) -> Bool {
		activeConnections[id] != nil || connectContinuations[id] != nil
	}

	/// Stops duplicate-advertisement scanning before CoreBluetooth starts a connection. Keeping the
	/// discovery stream and cache alive preserves the selected peripheral while the pairing sheet is
	/// active. A failed attempt restarts the scan so normal discovery and retries can continue.
	func pauseScanningForConnection(to deviceId: UUID) {
		scanPausedForConnections.insert(deviceId)
		guard centralManager?.isScanning == true else { return }
		centralManager.stopScan()
	}

	/// The pause exists to keep duplicate-advertisement traffic away from the pairing
	/// window, which runs through the notify subscription — after the link itself comes
	/// up. Once the handshake is fully established, resume so the Available Radios list
	/// stays live for device switching while connected.
	func resumeScanningAfterConnectionEstablished(for deviceId: UUID) {
		resumeScanningIfPaused(for: deviceId)
	}

	private func resumeScanningAfterFailedConnection(for deviceId: UUID?) {
		resumeScanningIfPaused(for: deviceId)
	}

	/// Ends `deviceId`'s pause (every pause when nil) and scans again once no connect holds one.
	private func resumeScanningIfPaused(for deviceId: UUID?) {
		guard scanningPausedForConnection else { return }
		if let deviceId {
			scanPausedForConnections.remove(deviceId)
		} else {
			scanPausedForConnections.removeAll()
		}
		guard !scanningPausedForConnection,
			  discoveredDeviceContinuation != nil,
			  centralManager?.state == .poweredOn,
			  !restoreInProgress else { return }
		centralManager.scanForPeripherals(
			withServices: [meshtasticServiceCBUUID],
			options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
		)
	}

	/// Resolves a peripheral from the live discovery cache or CoreBluetooth's registry. The latter
	/// keeps connect(to:) valid if discovery teardown cleared the cache before the connect request.
	private func resolvePeripheral(for device: Device) -> CBPeripheral? {
		guard let identifier = UUID(uuidString: device.identifier) else {
			Logger.transport.error("🛜 [BLE] Device identifier is not a UUID: \(device.identifier, privacy: .public)")
			return nil
		}
		if let cachedPeripheral = discoveredPeripherals[identifier]?.peripheral {
			return cachedPeripheral
		}
		return centralManager?.retrievePeripherals(withIdentifiers: [identifier]).first
	}

	func connect(to device: Device) async throws -> any Connection {
		if let id = UUID(uuidString: device.identifier), isBusy(id) {
			throw AccessoryError.connectionFailed("BLE transport is busy: already connecting or connected")
		}

		let pauseId = UUID(uuidString: device.identifier) ?? device.id
		pauseScanningForConnection(to: pauseId)
		guard let peripheral = resolvePeripheral(for: device) else {
			resumeScanningAfterFailedConnection(for: pauseId)
			throw AccessoryError.connectionFailed("Peripheral not found")
		}
		let id = peripheral.identifier
		// A radio iOS restored still connected: take over its link rather than connecting again.
		// One restored while connecting goes through the normal connect, which CoreBluetooth
		// completes with the pending attempt.
		if let restored = restoredStandby.removeValue(forKey: id), restored.state == .connected, centralManager != nil {
			Logger.transport.info("🛜 [BLE] Taking over the restored link to \(restored.name ?? "Unknown", privacy: .public)")
			let connection = BLEConnection(peripheral: restored, central: centralManager, transport: self)
			activeConnections[id] = connection
			return connection
		}

		do {
			let returnConnection = try await withTaskCancellationHandler {
				let newConnection: BLEConnection = try await withCheckedThrowingContinuation { cont in
					if self.isBusy(id) {
						cont.resume(throwing: AccessoryError.connectionFailed("BLE transport is busy: already connecting or connected"))
						return
					}
					self.connectContinuations[id] = cont
					self.connectingPeripherals[id] = peripheral
					guard centralManager != nil else {
						self.connectContinuations.removeValue(forKey: id)
						self.connectingPeripherals.removeValue(forKey: id)
						cont.resume(throwing: AccessoryError.connectionFailed("Bluetooth not initialized"))
						return
					}
					centralManager.connect(peripheral)
				}
				self.activeConnections[id] = newConnection
				return newConnection
			} onCancel: {
				Task {
					await self.cancelConnectContinuation(for: peripheral)
				}
			}
			Logger.transport.debug("🛜 [BLE] Connect complete.")
			return returnConnection
		} catch {
			connectionDidDisconnect(fromPeripheral: peripheral)
			throw error
		}
	}

	func handlePeripheralDisconnect(peripheral: CBPeripheral) {
		let id = peripheral.identifier
		if let continuation = connectContinuations.removeValue(forKey: id) {
			// Disconnect arrived while still waiting for didConnect — resume the
			// pending continuation so the caller doesn't hang.
			Logger.transport.debug("🛜 [BLETransport] Clean disconnect during connection phase. Resuming continuation with error.")
			connectingPeripherals.removeValue(forKey: id)
			continuation.resume(throwing: AccessoryError.connectionFailed("Peripheral disconnected before connection completed"))
			discoveredPeripherals.removeValue(forKey: id)
			discoveredDeviceContinuation?.yield(.deviceLost(id))
		} else if let connection = activeConnections[id] {
			discoveredPeripherals.removeValue(forKey: id)
			discoveredDeviceContinuation?.yield(.deviceLost(id))
			Task {
				try await connection.disconnect(withError: AccessoryError.disconnected("BLE connection lost"), shouldReconnect: true)
			}
		}
	}
	
	func handlePeripheralDisconnectError(peripheral: CBPeripheral, error: Error) {
		var shouldReconnect = false
		switch error {
		case let cbError as CBError:
			switch cbError.code {
			case .connectionTimeout: // 6
				// Happens when the node goes out of range or the shutdown or reset buttons are presses
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLETransport] Disconnected with CBError code: \(cbError.code.rawValue, privacy: .public) - \(cbError.localizedDescription, privacy: .public)")
				shouldReconnect = true
			case .peripheralDisconnected: // 7
				// Happens when the node reboots or shuts down intentionally via the firmware or app
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLETransport] Disconnected with CBError code: \(cbError.code.rawValue, privacy: .public) - \(cbError.localizedDescription, privacy: .public)")
				shouldReconnect = true
			default:
				// Fallback for other CBError codes
				Logger.transport.error("🛜 [BLETransport] Disconnected with CBError code: \(cbError.code.rawValue, privacy: .public) - \(cbError.localizedDescription, privacy: .public)")
			}
		case let otherError:
			Logger.transport.error("🛜 [BLETransport] Disconnected with non-CBError: \(otherError.localizedDescription, privacy: .public)")
		}
		
		let id = peripheral.identifier
		if let continuation = connectContinuations.removeValue(forKey: id) {
			Logger.transport.debug("🛜 [BLETransport] Error while connecting. Resuming connection continuation with error.")
			connectingPeripherals.removeValue(forKey: id)
			continuation.resume(throwing: error)
		} else if let activeConnection = activeConnections[id] {
			// Inform the active connection that there was an error and it should disconnect
			Logger.transport.debug("🛜 [BLETransport] Error on active connection. Disconnecting.")
			Task {
				try? await activeConnection.disconnect(withError: error, shouldReconnect: shouldReconnect)
				await self.connectionDidDisconnect(fromPeripheral: peripheral)
			}
		} else {
			Logger.transport.error("🚨 [BLETransport] unhandled error.  May be in an inconsistent state.")
		}
	}

	func handleDidConnect(peripheral: CBPeripheral, central: CBCentralManager) {
		if let restoredConnect, restoredConnect.peripheralId == peripheral.identifier {
			self.restoredConnect = nil
			restoredConnect.continuation.resume()
			return
		}
		if handOverRestore(to: peripheral, central: central) {
			return
		}
		Logger.transport.debug("🛜 [BLE] Handle Did Connect Connected to peripheral \(peripheral.name ?? "Unknown", privacy: .public)")
		let id = peripheral.identifier
		guard let cont = connectContinuations.removeValue(forKey: id) else {
			return
		}
		connectingPeripherals.removeValue(forKey: id)
		let connection = BLEConnection(peripheral: peripheral, central: central, transport: self)
		cont.resume(returning: connection)
	}

	func handleDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
		if let restoredConnect, restoredConnect.peripheralId == peripheral.identifier {
			self.restoredConnect = nil
			restoredConnect.continuation.resume(throwing: AccessoryError.connectionFailed("Connection failed during restoration"))
			return
		}
		
		let id = peripheral.identifier
		guard let cont = connectContinuations.removeValue(forKey: id) else {
			return
		}
		connectingPeripherals.removeValue(forKey: id)
		cont.resume(throwing: error ?? AccessoryError.connectionFailed("Connection failed"))
	}
	
	func handleWillRestoreState(dict: [String: Any], central: CBCentralManager) async {
		/// GVH - To test this you need to simulate the app getting killed in the background by the OS you can do this by stopping  the debugger while the app is connected to a device in the background
		/// You will see Message from debugger: killed after you see this message, power off and back on your meshtastic device, bring the app back to the foreground and
		/// look in the logs for the messages below.
		Logger.transport.error("🛜 [BLE] Will Restore State was called. Attempting to restore connection.")
		
		/// Find the peripherals that were connected before. Feature 021 (T062): the preferred radio,
		/// or else the first, is restored as the focused radio; the others wait in
		/// `restoredStandby` for the remembered-radio reconnect that follows the focused connect.
		guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
			  let peripheral = Self.focusedPeripheral(among: peripherals, preferredId: PreferredRadio.peripheralId) else {
			Logger.transport.error("🛜 [BLE] No peripherals found in restore state dictionary.")
			return
		}
		let alongside = peripherals.filter { $0.identifier != peripheral.identifier }
		holdRestoredPeripherals(alongside)
		// Remembered so they're claimed after the focused restore, the preferred radio too when
		// another is the focused restore; that one takes the focus back once it's here (T190).
		let preferredId = UUID(uuidString: PreferredRadio.peripheralId)
		let displaced = alongside.contains { $0.identifier == preferredId } ? preferredId : nil
		await AccessoryManager.shared.noteRestoredAlongside(peripheralIds: alongside.map(\.identifier), displacedPreferred: displaced)
		let device = await restoredDevice(for: peripheral)
		restoreAsFocused(peripheral, central: central, device: device)
	}

	/// The `Device` for a peripheral iOS restored: its node number and names from the store.
	func restoredDevice(for peripheral: CBPeripheral) async -> Device {
		// TODO: maybe serialize the whole device into UserDefaults on connect?
		let id = peripheral.identifier
		let nodeNum = await Self.restoredNodeNum(peripheralId: id)
		var device = Device(id: id, name: peripheral.name ?? "Unknown", transportType: .ble, identifier: id.uuidString, num: nodeNum, wasRestored: true)

		// Get the device name
		if let nodeNum {
			let nodeNumVal = Int64(nodeNum)
			let names: (String?, String?) = await MainActor.run {
				do {
					let descriptor = FetchDescriptor<NodeInfoEntity>(
						predicate: #Predicate { $0.num == nodeNumVal }
					)
					let context = PersistenceController.shared.context
					let fetchedNodes = try context.fetch(descriptor)
					if let first = fetchedNodes.first {
						return (first.user?.longName, first.user?.shortName)
					}
				} catch {
					// No-op
				}
				return (nil, nil)
			}
			if let longName = names.0 {
				device.longName = longName
			}
			if let shortName = names.1 {
				device.shortName = shortName
			}
		}
		return device
	}

	/// A focused restore still waiting was given up because a standby radio connected first
	/// (T178); that radio is the focused restore now.
	struct RestoreHandedOver: Error {}

	/// Restores `peripheral` as the focused radio: taken over if iOS kept it connected, or its
	/// pending connect completed and then a full handshake.
	func restoreAsFocused(_ peripheral: CBPeripheral, central: CBCentralManager, device: Device) {
		// Prevent device discovery during the restore process
		restoreInProgress = true
		let id = peripheral.identifier
		discoveredPeripherals[id] = (peripheral: peripheral, lastSeen: Date())
	
		Logger.transport.error("🛜 [BLE] Found peripheral to restore: \(peripheral.name ?? "Unknown", privacy: .public) ID: \(peripheral.identifier, privacy: .public) State: \(cbPeripheralStateDescription(peripheral.state), privacy: .public).")
		/// Create a new BLEConnection object and set it as the active connection if the state is connected
		
		// Begin a background task to handle the process.
		Task {
			switch peripheral.state {
			case .connecting:
				let restoredConnection = BLEConnection(peripheral: peripheral, central: central, transport: self)
				self.activeConnections[id] = restoredConnection
				Task {
					do {
						// Make sure we're in poweredOn before continuing
						try await self.setupCompleteGate.wait()
						
						Logger.transport.error("🛜 [BLE] Restoring peripheral in connecting state.  Waiting for didConnect from delegate.")
						
						// Complete the connect with centralManager.connect and wait for the didConnect.
						try await self.waitForRestoredConnect(of: peripheral)
						
						Logger.transport.error("🛜 [BLE] Restoring peripheral in connecting state.  ✅ didConnect Received!")
						await self.completeFocusedRestore(device: device, connection: restoredConnection, fullHandshake: true)
					} catch is RestoreHandedOver {
						// Another restored radio connected first and is the focused restore now; this
						// one waits with the others (T178). `restoreInProgress` is that restore's.
						Logger.transport.info("🛜 [BLE] \(device.name, privacy: .public) is still connecting; another restored radio takes the focus")
					} catch {
						// We had a connection failure during restoration.
						Logger.transport.error("🛜 [BLE] Error restoring peripheral in connecting state. \(error, privacy: .public)")
						self.restoreInProgress = false
					}
				}

			case .connected:
				let restoredConnection = BLEConnection(peripheral: peripheral, central: central, transport: self)
				self.activeConnections[id] = restoredConnection
				Logger.transport.error("🛜 [BLE] Peripheral Connection found and state is connected setting this connection as the activeConnection.")
				// iOS kept the link, so the radio has no new config to send.
				await self.completeFocusedRestore(device: device, connection: restoredConnection, fullHandshake: false)
				Logger.transport.error("🛜 [BLE] Connection state successfully restored in the background.")
			default:
				// Since we're not going to attempt to reconnect in then allow normal device discovery
				Logger.transport.error("🛜 [BLE] Unhandled state restoration for state: \(cbPeripheralStateDescription(peripheral.state), privacy: .public).")
				self.restoreInProgress = false
			}
		}
	}

	/// Runs the focused radio's connect over a restored link, then lets discovery run again.
	private func completeFocusedRestore(device: Device, connection: BLEConnection, fullHandshake: Bool) async {
		let connectTask = Task { @MainActor in
			try await AccessoryManager.shared.connect(to: device, withConnection: connection, wantConfig: fullHandshake, wantDatabase: fullHandshake, versionCheck: fullHandshake)
		}
		do {
			try await connectTask.value
		} catch {
			Logger.transport.error("🛜 [BLE] Error connecting during state restoration: \(error, privacy: .public)")
		}
		restoreInProgress = false
	}

	/// Test seam for `handleDidConnect`'s hand-over (T178): what happens to the standby radio
	/// that connected first. Nil runs the focused restore.
	private(set) var restoreTakeover: (@Sendable (CBPeripheral, CBCentralManager) async -> Void)?

	func setRestoreTakeover(_ takeover: (@Sendable (CBPeripheral, CBCentralManager) async -> Void)?) {
		restoreTakeover = takeover
	}

	/// A standby radio's didConnect while the focused restore still waits: that radio, which is
	/// the one in range, becomes the focused restore, and the waiting one joins the standby radios
	/// so the remembered-radio reconnect claims it when it connects (T178). Returns false when
	/// this isn't that case.
	private func handOverRestore(to peripheral: CBPeripheral, central: CBCentralManager) -> Bool {
		guard let pending = restoredConnect, pending.peripheralId != peripheral.identifier,
			  let standby = restoredStandby.removeValue(forKey: peripheral.identifier) else { return false }
		restoredConnect = nil
		activeConnections.removeValue(forKey: pending.peripheralId)
		if let waiting = discoveredPeripherals[pending.peripheralId]?.peripheral {
			restoredStandby[pending.peripheralId] = waiting
		}
		pending.continuation.resume(throwing: RestoreHandedOver())
		let displacedId = pending.peripheralId
		Task {
			// The radio it displaced is remembered and claimed after this restore; if it's the
			// preferred radio, it takes the focus back once it's here (T190).
			let displacedPreferred = displacedId.uuidString == PreferredRadio.peripheralId ? displacedId : nil
			await AccessoryManager.shared.noteRestoredAlongside(peripheralIds: [displacedId], displacedPreferred: displacedPreferred)
			if let restoreTakeover = self.restoreTakeover {
				await restoreTakeover(standby, central)
				return
			}
			let device = await self.restoredDevice(for: standby)
			self.restoreInProgress = true
			let connection = BLEConnection(peripheral: standby, central: central, transport: self)
			self.activeConnections[standby.identifier] = connection
			// Its full handshake makes it the preferred radio (connect Step 5). The radio it took
			// over from stays preferred, so later launches connect it first, as before iOS closed
			// the app, even if it doesn't come back this session (T201).
			let keptPreferred = await MainActor.run { (PreferredRadio.peripheralId, PreferredRadio.nodeNum) }
			await self.completeFocusedRestore(device: device, connection: connection, fullHandshake: true)
			if displacedPreferred != nil {
				await MainActor.run {
					PreferredRadio.peripheralId = keptPreferred.0
					PreferredRadio.nodeNum = keptPreferred.1
				}
			}
		}
		return true
	}

	/// Completes the pending connect of `peripheral`, restored while connecting, and waits for its
	/// own didConnect.
	func waitForRestoredConnect(of peripheral: CBPeripheral) async throws {
		try await withCheckedThrowingContinuation { cont in
			restoredConnect = (peripheral.identifier, cont)
			centralManager.connect(peripheral)
		}
	}

	/// Keeps restored radios other than the focused one for the remembered-radio reconnect to
	/// claim (`connect(to:)`), and releases whatever is left after `gracePeriod`.
	func holdRestoredPeripherals(_ peripherals: [CBPeripheral], gracePeriod: Duration = restoredStandbyGracePeriod) {
		guard !peripherals.isEmpty else { return }
		for peripheral in peripherals {
			Logger.transport.info("🛜 [BLE] Restored \(peripheral.name ?? "Unknown", privacy: .public) (\(cbPeripheralStateDescription(peripheral.state), privacy: .public)) to reconnect alongside the focused radio")
			restoredStandby[peripheral.identifier] = peripheral
			discoveredPeripherals[peripheral.identifier] = (peripheral: peripheral, lastSeen: Date())
		}
		Task {
			try? await Task.sleep(for: gracePeriod)
			self.releaseUnclaimedRestoredPeripherals()
		}
	}

	/// How long restored radios wait to be claimed. Covers the focused radio's restore, including
	/// a full handshake when it was restored while connecting.
	static let restoredStandbyGracePeriod: Duration = .seconds(180)

	/// The peripheral restored as the focused radio. A radio iOS restored still connected comes
	/// first, the preferred one among them: one still connecting may never come back (it was left
	/// at home), and waiting for it would drop the connected one that woke the app (T155). Then
	/// the preferred one, otherwise the first.
	static func focusedPeripheral<P: RestoredPeripheral>(among peripherals: [P], preferredId: String) -> P? {
		let connected = peripherals.filter { $0.state == .connected }
		return connected.first { $0.identifier.uuidString == preferredId }
			?? connected.first
			?? peripherals.first { $0.identifier.uuidString == preferredId }
			?? peripherals.first
	}

	/// The node number of the radio on `peripheralId`, from its `MyInfoEntity`. Before this
	/// feature every restore assumed the preferred radio; with several radios that's only true
	/// for one of them.
	@MainActor
	static func restoredNodeNum(peripheralId: UUID) -> Int64? {
		let idString = peripheralId.uuidString
		var descriptor = FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.peripheralId == idString })
		descriptor.fetchLimit = 1
		if let myNodeNum = (try? PersistenceController.shared.context.fetch(descriptor))?.first?.myNodeNum, myNodeNum != 0 {
			return myNodeNum
		}
		guard idString == PreferredRadio.peripheralId, PreferredRadio.nodeNum != 0 else { return nil }
		return PreferredRadio.nodeNum
	}

	/// Drops the CoreBluetooth link of every restored radio nobody claimed (not remembered, or
	/// the focused restore failed), so the radio is free for a later connect or another phone.
	func releaseUnclaimedRestoredPeripherals() {
		let unclaimed = restoredStandby
		restoredStandby.removeAll()
		for (id, peripheral) in unclaimed where activeConnections[id] == nil && connectContinuations[id] == nil {
			Logger.transport.info("🛜 [BLE] Releasing the unclaimed restored link to \(peripheral.name ?? "Unknown", privacy: .public)")
			centralManager?.cancelPeripheralConnection(peripheral)
		}
	}
	
	nonisolated func device(forManualConnection: String) -> Device? {
		return nil
	}
	
	func manuallyConnect(toDevice: Device) async throws {
		Logger.transport.error("🛜 [BLE] This transport does not support manual connections")
	}

	// BLETransport handles portions of the connection process, so it needs to be informed that we've closed up shop.
	func connectionDidDisconnect(fromPeripheral peripheral: CBPeripheral?) {
		// Make sure we remove this device from the discovered list so that we send a
		// new discovery event in when it is next seen.
		// Only this peripheral's bookkeeping goes; other radios stay connected (feature 021).
		if let peripheral {
			let id = peripheral.identifier
			discoveredPeripherals.removeValue(forKey: id)
			discoveredDeviceContinuation?.yield(.deviceLost(id))
			activeConnections.removeValue(forKey: id)
			connectingPeripherals.removeValue(forKey: id)
		}
		restoreInProgress = false
		resumeScanningAfterFailedConnection(for: peripheral?.identifier)
	}
}

class BLEDelegate: NSObject, CBCentralManagerDelegate {
	private weak var transport: BLETransport?

	override init() {
		super.init()
	}

	func setTransport(_ transport: BLETransport) {
		self.transport = transport
	}

	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		Task { await transport?.handleCentralState(central.state, central: central) }
	}

	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		Task { await transport?.didDiscover(peripheral: peripheral, rssi: RSSI) }
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		Task { await transport?.handleDidConnect(peripheral: peripheral, central: central) }
	}

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		Task { await transport?.handleDidFailToConnect(peripheral: peripheral, error: error) }
	}

	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		if let error = error as? NSError {
			Logger.transport.error("🛜 [BLETransport] Error while disconnecting peripheral: \(peripheral.name ?? "", privacy: .public): \(error, privacy: .public)")
			Task { await transport?.handlePeripheralDisconnectError(peripheral: peripheral, error: error) }
		} else {
			Logger.transport.error("🛜 [BLETransport] Did succesfully disconnect peripheral: \(peripheral.name ?? "")")
			Task { await transport?.handlePeripheralDisconnect(peripheral: peripheral) }
		}
	}
	
	func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
		Task { await self.transport?.handleWillRestoreState(dict: dict, central: central) }
	}
}

/// Returns a human-readable description for a CBManagerState value.
private func cbManagerStateDescription(_ state: CBManagerState) -> String {
	switch state {
	case .unknown: return "unknown"
	case .resetting: return "resetting"
	case .unsupported: return "unsupported"
	case .unauthorized: return "unauthorized"
	case .poweredOff: return "poweredOff"
	case .poweredOn: return "poweredOn"
	@unknown default: return "unhandled state"
	}
}

/// Returns a human-readable description for a CBPeripheralState value.
func cbPeripheralStateDescription(_ state: CBPeripheralState) -> String {
	switch state {
	case .disconnected:
		return "disconnected"
	case .connecting:
		return "connecting"
	case .connected:
		return "connected"
	case .disconnecting:
		return "disconnecting"
	@unknown default:
		return "unhandled state"
	}
}

/// What `BLETransport.focusedPeripheral(among:preferredId:)` needs from a restored peripheral.
protocol RestoredPeripheral {
	var identifier: UUID { get }
	var state: CBPeripheralState { get }
}

extension CBPeripheral: RestoredPeripheral {}
