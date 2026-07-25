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
	private var connectingPeripheral: CBPeripheral?
	private var activeConnection: BLEConnection?
	private var connectContinuation: CheckedContinuation<BLEConnection, Error>?
	private var restoredConnectContinuation: CheckedContinuation<Void, Error>?
	private var setupCompleteGate: AsyncGate
	/// Suppresses device discovery while `handleWillRestoreState` reconnects. Read by all three
	/// scan entry points (`didDiscover`, the `discoverDevices()` setup task, and the `.poweredOn`
	/// re-scan), so it staying latched true means no BLE discovery at all until the process is
	/// killed. Written only through `beginRestore(for:)` / `endRestore(clearingConnection:)`.
	private(set) var restoreInProgress: Bool = false
	/// The peripheral `handleWillRestoreState` is currently restoring. Scopes the restore
	/// short-circuits in `handleDidConnect` / `handleDidFailToConnect` to that peripheral, the
	/// same way the normal connect path already checks `connectingPeripheral`.
	private var restoringPeripheralIdentifier: UUID?
	/// The connection the in-flight restore installed as `activeConnection`. `endRestore` clears
	/// `activeConnection` only while it is still this exact object, so a restore tearing down late
	/// can't drop a connection that a normal `connect(to:)` has since installed.
	private var restoringConnection: BLEConnection?
	/// Bumped by every `awaitRestoredConnect` call so a watchdog that already woke up can tell it
	/// belongs to a restore that has since been resolved or replaced, and stay out of the way.
	private var restoredConnectGeneration = 0

	/// How long a restored connect waits for `didConnect` before giving up. CoreBluetooth connect
	/// requests never expire on their own, so without this the wait is unbounded.
	static let restoredConnectTimeout: Duration = .seconds(30)
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
	/// The in-flight `discoverDevices()` setup work (central-manager creation, waiting for
	/// poweredOn, the initial `scanForPeripherals()` call). Tracked so `stopActiveDiscovery()`
	/// can cancel *and await* it, closing the race where that setup work resumes past a
	/// suspension point and starts scanning after a caller believes discovery is off (#2183
	/// review).
	private var discoverySetupTask: Task<Void, Never>?
	
	// Transport properties
	let supportsManualConnection: Bool = false
	let requiresPeriodicHeartbeat = false
			
	init() {
		self.discoveredPeripherals = [:]
		self.discoveredDeviceContinuation = nil
		self.delegate = BLEDelegate()
		self.setupCompleteGate = AsyncGate()
		// Only create CBCentralManager immediately if Bluetooth authorization is already
		// determined. This avoids showing the system permission prompt before the
		// onboarding Bluetooth screen has a chance to present it in context.
		if CBCentralManager.authorization != .notDetermined {
			centralManager = CBCentralManager(delegate: delegate,
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
	/// enabled meant a TCP/WiFi-only user saw it on every launch. Worse, presenting that alert
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
			// Stored so `stopActiveDiscovery()` can cancel *and await* this setup work, not just
			// request its cancellation. `Task.cancel()` is cooperative: without awaiting this
			// task's completion, `stopActiveDiscovery()` could return while this task is still
			// suspended on `setupCompleteGate.wait()` (e.g. central manager not yet poweredOn) and
			// go on to call `scanForPeripherals()` *after* the caller believes discovery is off —
			// reopening the exact scan-during-pairing race this method exists to close (#2183
			// review).
			let setupTask = Task {
				await self.setDiscoveredDeviceContinuation(cont)

				// Create the CBCentralManager now if it was deferred (authorization was .notDetermined at init).
				if await self.centralManager == nil {
					await self.createCentralManager()
				}
				// This gate is opened when the CBCentralManager is in poweredOn state.
				// Its probably open already, but just to be sure in case we get here too quickly.
				do {
					try await self.setupCompleteGate.wait()
				} catch {
					return
				}
				// Re-check after every suspension point above: a cancellation requested while this
				// task was still waiting on the gate must not fall through to actually scanning.
				guard !Task.isCancelled else { return }

				if await !self.restoreInProgress {
					guard !Task.isCancelled else { return }
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
				await self.clearDiscoverySetupTask()
			}
			self.discoverySetupTask = setupTask
			cont.onTermination = { _ in
				Logger.transport.error("🛜 [BLE] Discovery event stream has been canecelled.")
				Task {
					await self.stopScanning()
				}
			}
		}
	}

	/// Clears the tracked setup task once it finishes on its own (i.e. not via
	/// `stopActiveDiscovery()`'s cancel-and-await path), so a later `stopActiveDiscovery()` call
	/// doesn't await a stale, already-completed task reference.
	private func clearDiscoverySetupTask() {
		discoverySetupTask = nil
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

	/// Directly stops active scanning and awaits completion — unlike the reactive
	/// `discoverDevices()` `onTermination` cancellation chain, whose final step spawns a
	/// detached, unawaited `Task` to reach this actor (see that closure). Because this actor
	/// method has no internal `await` after the setup-task teardown below, a caller's `await`
	/// here only returns once `centralManager.stopScan()` has actually executed. Idempotent,
	/// same as `stopScanning()`.
	///
	/// Cancels and awaits `discoverySetupTask` first: `Task.cancel()` alone is cooperative, so
	/// without awaiting it, that task could still be suspended on `setupCompleteGate.wait()`
	/// and resume to call `scanForPeripherals()` *after* this method returns — reopening the
	/// scan-during-pairing race this method exists to close (#2183 review).
	func stopActiveDiscovery() async {
		if let discoverySetupTask {
			discoverySetupTask.cancel()
			await discoverySetupTask.value
			self.discoverySetupTask = nil
		}
		stopScanning()
	}

	private func stopScanning() {
		Logger.transport.debug("🛜 [BLE] Stop Scanning: BLE Discovery has been stopped.")
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
			if activeConnection != nil {
				Logger.transport.info("🛜 [BLE] CBManager has poweredOn with an already active connection")
			}
			status = .discovering
			
			// Open the gate, so anyone who was waiitng for poweredOn can continue
			Task { await self.setupCompleteGate.open() }
			
			if self.discoveredDeviceContinuation != nil && !restoreInProgress {
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
			if let connection = activeConnection {
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

	private func cancelConnectContinuation(for peripheral: CBPeripheral) {
		self.connectContinuation?.resume(throwing: CancellationError())
		self.connectContinuation = nil
		self.connectionDidDisconnect(fromPeripheral: peripheral)
	}

	func connect(to device: Device) async throws -> any Connection {
		guard let peripheral = discoveredPeripherals[UUID(uuidString: device.identifier)!] else {
			throw AccessoryError.connectionFailed("Peripheral not found")
		}
		
		do {
			if await self.activeConnection?.peripheral.state == .disconnected {
				Logger.transport.error("🛜 [BLE] Connect request while an active (but disconnected)")
				throw AccessoryError.connectionFailed("Connect request while an active connection exists")
			}
			
			let returnConnection = try await withTaskCancellationHandler {
				let newConnection: BLEConnection = try await withCheckedThrowingContinuation { cont in
					if self.connectContinuation != nil || self.activeConnection != nil {
						cont.resume(throwing: AccessoryError.connectionFailed("BLE transport is busy: already connecting or connected"))
						return
					}
					self.connectContinuation = cont
					self.connectingPeripheral = peripheral.peripheral
					guard centralManager != nil else {
						cont.resume(throwing: AccessoryError.connectionFailed("Bluetooth not initialized"))
						return
					}
					centralManager.connect(peripheral.peripheral)
				}
				self.activeConnection = newConnection
				return newConnection
			} onCancel: {
				Task {
					await self.cancelConnectContinuation(for: peripheral.peripheral)
				}
			}
			Logger.transport.debug("🛜 [BLE] Connect complete.")
			return returnConnection
		} catch {
			connectionDidDisconnect(fromPeripheral: peripheral.peripheral)
			throw error
		}
	}

	func handlePeripheralDisconnect(peripheral: CBPeripheral) {
		if let continuation = self.connectContinuation,
		   self.connectingPeripheral?.identifier == peripheral.identifier {
			// Disconnect arrived while still waiting for didConnect — resume the
			// pending continuation so the caller doesn't hang.
			Logger.transport.debug("🛜 [BLETransport] Clean disconnect during connection phase. Resuming continuation with error.")
			continuation.resume(throwing: AccessoryError.connectionFailed("Peripheral disconnected before connection completed"))
			self.connectContinuation = nil
			self.connectingPeripheral = nil
			discoveredPeripherals.removeValue(forKey: peripheral.identifier)
			discoveredDeviceContinuation?.yield(.deviceLost(peripheral.identifier))
		} else if let connection = self.activeConnection {
			discoveredPeripherals.removeValue(forKey: peripheral.identifier)
			discoveredDeviceContinuation?.yield(.deviceLost(peripheral.identifier))
			Task {
				if await connection.peripheral.identifier == peripheral.identifier {
					try await connection.disconnect(withError: AccessoryError.disconnected("BLE connection lost"), shouldReconnect: true)
				}
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
				Logger.transport.error("🛜 [BLETransport] Disconnected with CBError code: \(cbError.code.rawValue) - \(cbError.localizedDescription)")
				shouldReconnect = true
			case .peripheralDisconnected: // 7
				// Happens when the node reboots or shuts down intentionally via the firmware or app
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLETransport] Disconnected with CBError code: \(cbError.code.rawValue) - \(cbError.localizedDescription)")
				shouldReconnect = true
			default:
				// Fallback for other CBError codes
				Logger.transport.error("🛜 [BLETransport] Disconnected with CBError code: \(cbError.code.rawValue) - \(cbError.localizedDescription)")
			}
		case let otherError:
			Logger.transport.error("🛜 [BLETransport] Disconnected with non-CBError: \(otherError.localizedDescription)")
		}
		
		if let continuation = self.connectContinuation {
			Logger.transport.debug("🛜 [BLETransport] Error while connecting. Resuming connection continuation with error.")
			continuation.resume(throwing: error)
			self.connectContinuation = nil
			self.connectingPeripheral = nil
		} else if let activeConnection = self.activeConnection {
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
		// Only take the restore short-circuit when a restore is actually in flight *for this
		// peripheral*, matching what the normal path below already does with `connectingPeripheral`.
		// Unscoped, a leftover restored continuation swallows an unrelated connect's didConnect:
		// `connectContinuation` is never resumed, no BLEConnection is built, and that connect hangs
		// until its own timeout.
		if let restoredConnectContinuation,
		   restoreInProgress,
		   peripheral.identifier == restoringPeripheralIdentifier {
			restoredConnectContinuation.resume()
			self.restoredConnectContinuation = nil
			return
		}
		Logger.transport.debug("🛜 [BLE] Handle Did Connect Connected to peripheral \(peripheral.name ?? "Unknown", privacy: .public)")
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		let connection = BLEConnection(peripheral: peripheral, central: central, transport: self)
		cont.resume(returning: connection)
		self.connectContinuation = nil
		self.connectingPeripheral = nil
	}

	func handleDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
		if let restoredConnectContinuation,
		   restoreInProgress,
		   peripheral.identifier == restoringPeripheralIdentifier {
			restoredConnectContinuation.resume(throwing: AccessoryError.connectionFailed("Connection failed during restoration"))
			self.restoredConnectContinuation = nil
			return
		}
		
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		cont.resume(throwing: error ?? AccessoryError.connectionFailed("Connection failed"))
		self.connectContinuation = nil
		self.connectingPeripheral = nil
	}
	
	func handleWillRestoreState(dict: [String: Any], central: CBCentralManager) async {
		/// GVH - To test this you need to simulate the app getting killed in the background by the OS you can do this by stopping  the debugger while the app is connected to a device in the background
		/// You will see Message from debugger: killed after you see this message, power off and back on your meshtastic device, bring the app back to the foreground and
		/// look in the logs for the messages below.
		Logger.transport.error("🛜 [BLE] Will Restore State was called. Attempting to restore connection.")
		
		/// Find the peripheral that was connected before
		guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
			  let peripheral = peripherals.first else {
			Logger.transport.error("🛜 [BLE] No peripherals found in restore state dictionary.")
			return
		}
		
		// Prevent device discovery during the restore process
		beginRestore(for: peripheral.identifier)

		// Create a device object
		// TODO: maybe serialize the whole device into UserDefaults on connect?
		let id = peripheral.identifier
		let nodeNum = UserDefaults.preferredPeripheralNum != 0 ? Int64(UserDefaults.preferredPeripheralNum) : nil
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
		
		discoveredPeripherals[id] = (peripheral: peripheral, lastSeen: Date())
	
		Logger.transport.error("🛜 [BLE] Found peripheral to restore: \(peripheral.name ?? "Unknown", privacy: .public) ID: \(peripheral.identifier, privacy: .public) State: \(cbPeripheralStateDescription(peripheral.state), privacy: .public).")
		/// Create a new BLEConnection object and set it as the active connection if the state is connected
		
		// Begin a background task to handle the process.
		//
		// The restore work runs directly in this task (it used to spawn a second, nested one for
		// the .connecting case) so the `defer` below covers the whole thing. Every exit has to go
		// through `endRestore`: it clears the discovery gate plus the rest of the state this method
		// set up, where the old code cleared only `restoreInProgress` and only on the paths it
		// happened to reach.
		Task {
			var restoredConnectionIsLive = false
			defer { endRestore(clearingConnection: !restoredConnectionIsLive) }

			switch peripheral.state {
			case .connecting:
				let restoredConnection = BLEConnection(peripheral: peripheral, central: central, transport: self)
				self.activeConnection = restoredConnection
				self.restoringConnection = restoredConnection
				do {
					// Make sure we're in poweredOn before continuing
					try await self.setupCompleteGate.wait()

					Logger.transport.error("🛜 [BLE] Restoring peripheral in connecting state.  Waiting for didConnect from delegate.")

					// Complete the connect with central.connect and wait for the didConnect,
					// bounded by a timeout. If the radio was powered off or moved out of range
					// while the app was killed, none of didConnect/didFailToConnect/
					// didDisconnectPeripheral ever arrives, so an unbounded wait here suspends
					// for the life of the process.
					try await self.awaitRestoredConnect(
						timeout: Self.restoredConnectTimeout,
						connect: { central.connect(peripheral) },
						cancelConnect: { central.cancelPeripheralConnection(peripheral) }
					)

					Logger.transport.error("🛜 [BLE] Restoring peripheral in connecting state.  ✅ didConnect Received!")
					restoredConnectionIsLive = true
					let connectTask = Task { @MainActor in
						try await AccessoryManager.shared.connect(to: device, withConnection: restoredConnection, wantConfig: true, wantDatabase: true, versionCheck: true)
					}

					do {
						try await connectTask.value
					} catch {
						Logger.transport.error("🛜 [BLE] Error connecting during state restoration: \(error, privacy: .public)")
					}
				} catch {
					// We had a connection failure during restoration. The connection never reached
					// BLEConnection.connect(), so nothing will ever call connectionDidDisconnect for
					// it — the defer above is what drops it.
					Logger.transport.error("🛜 [BLE] Error restoring peripheral in connecting state. \(error, privacy: .public)")
				}

			case .connected:
				let restoredConnection = BLEConnection(peripheral: peripheral, central: central, transport: self)
				self.activeConnection = restoredConnection
				self.restoringConnection = restoredConnection
				// The link is already up, so this connection stays as the activeConnection whatever
				// the app-level connect below does.
				restoredConnectionIsLive = true
				Logger.transport.error("🛜 [BLE] Peripheral Connection found and state is connected setting this connection as the activeConnection.")
				let connectTask = Task { @MainActor in
					// In this case we need a full reconnect, so do the wantConfig, wantDatabase, and versionCheck
					try await AccessoryManager.shared.connect(to: device, withConnection: restoredConnection, wantConfig: false, wantDatabase: false, versionCheck: false)
				}
				do {
					try await connectTask.value
				} catch {
					Logger.transport.error("🛜 [BLE] Error connecting during state restoration: \(error, privacy: .public)")
				}

				Logger.transport.error("🛜 [BLE] Connection state successfully restored in the background.")
			default:
				// Since we're not going to attempt to reconnect in then allow normal device discovery
				Logger.transport.error("🛜 [BLE] Unhandled state restoration for state: \(cbPeripheralStateDescription(peripheral.state), privacy: .public).")
			}
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
		if let peripheral {
			discoveredPeripherals.removeValue(forKey: peripheral.identifier)
			discoveredDeviceContinuation?.yield(.deviceLost(peripheral.identifier))
		}

		// This is the single funnel for "the peripheral is gone", so a restore still waiting on
		// didConnect will never get one. Resume it here — with the more specific error than
		// `endRestore` would use — instead of leaving it live to be resumed by a later, unrelated
		// connect's didConnect.
		if let continuation = restoredConnectContinuation {
			restoredConnectContinuation = nil
			continuation.resume(throwing: AccessoryError.disconnected("Peripheral disconnected during state restoration"))
		}
		// Discovery gate + restore bookkeeping goes through `endRestore` so it stays the only
		// writer of `restoreInProgress`. `clearingConnection: false` because this method clears
		// `activeConnection` unconditionally below: the peripheral is gone regardless of whether
		// the connection came from a restore or a normal connect.
		endRestore(clearingConnection: false)

		self.activeConnection = nil
		self.connectingPeripheral = nil
	}
}

// MARK: - State restoration lifecycle

extension BLETransport {

	/// Marks a state restore as in flight: suppresses device discovery, and records which
	/// peripheral the restore short-circuits in `handleDidConnect` / `handleDidFailToConnect`
	/// apply to.
	func beginRestore(for peripheralIdentifier: UUID) {
		restoreInProgress = true
		restoringPeripheralIdentifier = peripheralIdentifier
	}

	/// The single exit from a state restore, clearing the transport state the restore itself owns
	/// rather than just the discovery gate. (The `discoveredPeripherals` entry
	/// `handleWillRestoreState` added is deliberately kept: it is what lets the user reconnect to
	/// the radio by hand after a failed restore, and the periodic cleanup task prunes it on its
	/// own once it stops being seen.)
	///
	/// A leftover `restoredConnectContinuation` gets resumed by the next unrelated connect's
	/// didConnect and hangs it; an `activeConnection` for a connection that never actually
	/// connected makes `connect(to:)`'s busy guards reject every later attempt, and nothing else
	/// clears it because `BLEConnection.disconnect()` (the only caller of
	/// `connectionDidDisconnect`) never runs for a connection that never started.
	///
	/// The restore task passes `clearingConnection: false` only when the restored connection is
	/// genuinely live; `connectionDidDisconnect` also passes `false` because it clears
	/// `activeConnection` itself.
	func endRestore(clearingConnection: Bool) {
		restoreInProgress = false
		restoringPeripheralIdentifier = nil
		if let continuation = restoredConnectContinuation {
			restoredConnectContinuation = nil
			continuation.resume(throwing: AccessoryError.connectionFailed(Self.restoreEndedPendingConnectMessage))
		}
		// Only ever drop the connection this restore installed, and only while it is still the
		// active one. `connectingPeripheral` is not this method's to clear at all — the restore
		// path never sets it. Clearing either unconditionally hands the original bug back from the
		// other direction: a `connect(to:)` that started after something else already released
		// `activeConnection` (a disconnect, the watchdog) would lose its `connectingPeripheral`, so
		// `handleDidConnect`'s identity guard fails, `connectContinuation` is never resumed, and
		// that connect hangs to its own timeout.
		if clearingConnection, let restoringConnection, activeConnection === restoringConnection {
			activeConnection = nil
		}
		restoringConnection = nil
	}

	/// True while a restore is suspended waiting for `didConnect`.
	var isAwaitingRestoredConnect: Bool { restoredConnectContinuation != nil }

	/// Suspends until the restored peripheral reports `didConnect`, `timeout` elapses, the
	/// peripheral is reported gone (`connectionDidDisconnect`), the enclosing task is cancelled, or
	/// another restore supersedes this one. On every one of those give-up paths the outstanding
	/// CoreBluetooth connect request is withdrawn via `cancelConnect`, since CoreBluetooth keeps
	/// pending connect requests alive indefinitely.
	///
	/// Takes closures rather than a `CBPeripheral` so the timeout behaviour can be exercised in
	/// tests: `CBPeripheral` has no public initializer.
	func awaitRestoredConnect(
		timeout: Duration,
		connect: @escaping @Sendable () -> Void,
		cancelConnect: @escaping @Sendable () -> Void
	) async throws {
		restoredConnectGeneration += 1
		let generation = restoredConnectGeneration
		let watchdog = Task { [weak self] in
			try? await Task.sleep(for: timeout)
			guard !Task.isCancelled else { return }
			await self?.failRestoredConnect(
				generation: generation,
				with: AccessoryError.connectionFailed(Self.restoredConnectTimedOutMessage),
				cancelConnect: cancelConnect
			)
		}
		defer { watchdog.cancel() }
		// A checked continuation isn't cancellation-aware on its own: without this handler a
		// cancelled restore task stays suspended here until the watchdog fires, and its
		// `defer { endRestore }` (the discovery gate) waits that long with it.
		try await withTaskCancellationHandler {
			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				// A second restore must not orphan the first one's continuation: the task suspended
				// on it would never resume, so its `defer { endRestore }` never runs and the
				// discovery gate stays latched — exactly the failure this path exists to prevent.
				if let superseded = restoredConnectContinuation {
					restoredConnectContinuation = nil
					superseded.resume(throwing: AccessoryError.connectionFailed(Self.restoredConnectSupersededMessage))
				}
				// Cancellation between entering this function and installing the continuation would
				// otherwise miss the handler above and leave a CoreBluetooth connect request
				// outstanding for a restore nobody is waiting on.
				guard !Task.isCancelled else {
					continuation.resume(throwing: CancellationError())
					return
				}
				restoredConnectContinuation = continuation
				connect()
			}
		} onCancel: {
			Task { [weak self] in
				await self?.failRestoredConnect(
					generation: generation,
					with: CancellationError(),
					cancelConnect: cancelConnect
				)
			}
		}
	}

	/// Fails a pending restored connect. No-op if it already resolved, so the watchdog can't
	/// double-resume a continuation `handleDidConnect` already took, and no-op for a stale
	/// `generation`, so a watchdog that woke up just as its own wait was resolved can't take down
	/// the continuation a later restore installed in the meantime.
	private func failRestoredConnect(generation: Int, with error: Error, cancelConnect: @Sendable () -> Void) {
		guard generation == restoredConnectGeneration,
			  let continuation = restoredConnectContinuation else { return }
		restoredConnectContinuation = nil
		cancelConnect()
		continuation.resume(throwing: error)
	}

	/// Messages the restore path resolves a pending `restoredConnectContinuation` with. Shared
	/// constants (same reasoning as `poweredOffStatusMessage`) so tests can tell *which* give-up
	/// path resolved a wait without duplicating the literals or timing the resolution.
	static let restoreEndedPendingConnectMessage = "State restoration ended before the peripheral connected"
	static let restoredConnectTimedOutMessage = "Timed out waiting for the restored peripheral to connect"
	static let restoredConnectSupersededMessage = "Superseded by another state restoration"
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
			Logger.transport.error("🛜 [BLETransport] Error while disconnecting peripheral: \(peripheral.name ?? ""): \(error)")
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
