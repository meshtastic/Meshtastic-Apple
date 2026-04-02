//
//  BLETransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
@preconcurrency import CoreBluetooth
import SwiftUI
import OSLog

actor BLETransport: Transport {

	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
	private let kCentralRestoreID = "com.meshtastic.central"

	let type: TransportType = .ble
	private var centralManager: CBCentralManager
	private var discoveredPeripherals: [UUID: (peripheral: CBPeripheral, lastSeen: Date)] = [:]
	private var discoveredDeviceContinuation: AsyncStream<DiscoveryEvent>.Continuation?
	private let delegate: BLEDelegate
	private var connectingPeripheral: CBPeripheral?
	private var activeConnection: BLEConnection?
	private var connectContinuation: CheckedContinuation<BLEConnection, Error>?
	private var restoredConnectContinuation: CheckedContinuation<Void, Error>?
	private var setupCompleteGate: AsyncGate
	private var restoreInProgress: Bool = false
	var status: TransportStatus = .uninitialized

	private var cleanupTask: Task<Void, Never>?
	
	// Transport properties
	let supportsManualConnection: Bool = false
	let requiresPeriodicHeartbeat = false
			
	init() {
		self.discoveredPeripherals = [:]
		self.discoveredDeviceContinuation = nil
		self.delegate = BLEDelegate()
		self.setupCompleteGate = AsyncGate()
		centralManager = CBCentralManager(delegate: delegate,
										  queue: .global(qos: .utility),
										  options: [CBCentralManagerOptionRestoreIdentifierKey: kCentralRestoreID]
		)
		self.delegate.setTransport(self)
	}

	private func setDiscoveredDeviceContinuation(_ cont: AsyncStream<DiscoveryEvent>.Continuation?) {
		self.discoveredDeviceContinuation = cont
	}

	func discoverDevices() -> AsyncStream<DiscoveryEvent> {
		AsyncStream { cont in
			Task {
				await self.setDiscoveredDeviceContinuation(cont)
				
				// This gate is opened when the CBCentralManager is in poweredOn state.
				// Its probably open already, but just to be sure in case we get here too quickly.
				try await self.setupCompleteGate.wait()
				
				if await !self.restoreInProgress {
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
			status = .error("Bluetooth is powered off")
			if let connection = activeConnection {
				Task {
					Logger.transport.error("🛜 [BLE] Bluetooth has powered off during active connection. Cleaning up.")
					try await connection.disconnect(withError: AccessoryError.disconnected("Bluetooth powered off"), shouldReconnect: true)
					await self.connectionDidDisconnect(fromPeripheral: connection.peripheral)
				}
			}
			status = .ready
			
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
		if let connection = self.activeConnection {
			discoveredPeripherals.removeValue(forKey: peripheral.identifier)
			discoveredDeviceContinuation?.yield(.deviceLost(peripheral.identifier))
			Task {
				if await connection.peripheral.identifier == peripheral.identifier {
					try await connection.disconnect(withError: AccessoryError.disconnected("BLE connection lost"), shouldReconnect: true)
					await self.connectionDidDisconnect(fromPeripheral: peripheral)
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
		} else if let activeConnection = self.activeConnection {
			// Inform the active connection that there was an error and it should disconnect
			Logger.transport.debug("🛜 [BLETransport] Error while connecting. Disconnecting the active connection.")
			Task {
				try? await activeConnection.disconnect(withError: error, shouldReconnect: shouldReconnect)
				await self.connectionDidDisconnect(fromPeripheral: peripheral)
			}
		} else {
			Logger.transport.error("🚨 [BLETransport] unhandled error.  May be in an inconsistent state.")
		}
	}

	func handleDidConnect(peripheral: CBPeripheral, central: CBCentralManager) {
		if let restoredConnectContinuation {
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
		if let restoredConnectContinuation {
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
	
	func handleWillRestoreState(dict: [String: Any], central: CBCentralManager) {
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
		restoreInProgress = true

		// Create a device object
		// TODO: maybe serialize the whole device into UserDefaults on connect?
		let id = peripheral.identifier
		let nodeNum = UserDefaults.preferredPeripheralNum != 0 ? Int64(UserDefaults.preferredPeripheralNum) : nil
		var device = Device(id: id, name: peripheral.name ?? "Unknown", transportType: .ble, identifier: id.uuidString, num: nodeNum, wasRestored: true)
		
		// Get the device name
		if let nodeNum {
			let fetchMyInfoRequest = NodeInfoEntity.fetchRequest()
			fetchMyInfoRequest.predicate = NSPredicate(format: "num == %lld", Int64(nodeNum))
			do {
				let fetchedMyInfo = try PersistenceController.shared.container.viewContext.fetch(fetchMyInfoRequest)
				if fetchedMyInfo.count > 0 {
					if let longName = fetchedMyInfo[0].user?.longName {
						device.longName = longName
					}
					if let shortName = fetchedMyInfo[0].user?.shortName {
						device.shortName = shortName
					}
				}
			} catch {
				// No-op
			}
		}
		
		discoveredPeripherals[id] = (peripheral: peripheral, lastSeen: Date())
	
		Logger.transport.error("🛜 [BLE] Found peripheral to restore: \(peripheral.name ?? "Unknown", privacy: .public) ID: \(peripheral.identifier, privacy: .public) State: \(cbPeripheralStateDescription(peripheral.state), privacy: .public).")
		/// Create a new BLEConnection object and set it as the active connection if the state is connected
		
		// Begin a background task to handle the process.
		Task {
			switch peripheral.state {
			case .connecting:
				let restoredConnection = BLEConnection(peripheral: peripheral, central: central, transport: self)
				self.activeConnection = restoredConnection
				Task {
					do {
						// Make sure we're in poweredOn before continuing
						try await self.setupCompleteGate.wait()
						
						Logger.transport.error("🛜 [BLE] Restoring peripheral in connecting state.  Waiting for didConnect from delegate.")
						
						// Complete the connect with centralManager.connect and wait for the didConnect.
						try await withCheckedThrowingContinuation { cont in
							self.restoredConnectContinuation = cont
							centralManager.connect(peripheral)
						}
						
						Logger.transport.error("🛜 [BLE] Restoring peripheral in connecting state.  ✅ didConnect Received!")
						let connectTask = Task { @MainActor in
							try await AccessoryManager.shared.connect(to: device, withConnection: restoredConnection, wantConfig: true, wantDatabase: true, versionCheck: true)
						}
						
						do {
							try await connectTask.value
						} catch {
							Logger.transport.error("🛜 [BLE] Error connecting during state restoration: \(error, privacy: .public)")
						}
						self.restoreInProgress = false
					} catch {
						// We had a connection failure during restoration.
						Logger.transport.error("🛜 [BLE] Error restoring peripheral in connecting state. \(error, privacy: .public)")
						self.restoreInProgress = false
					}
				}

			case .connected:
				let restoredConnection = BLEConnection(peripheral: peripheral, central: central, transport: self)
				self.activeConnection = restoredConnection
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

				self.restoreInProgress = false
				Logger.transport.error("🛜 [BLE] Connection state successfully restored in the background.")
			default:
				// Since we're not going to attempt to reconnect in then allow normal device discovery
				Logger.transport.error("🛜 [BLE] Unhandled state restoration for state: \(cbPeripheralStateDescription(peripheral.state), privacy: .public).")
				self.restoreInProgress = false
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
		
		self.activeConnection = nil
		self.connectingPeripheral = nil
		restoreInProgress = false
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
