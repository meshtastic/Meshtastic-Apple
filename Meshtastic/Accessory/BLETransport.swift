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

class BLETransport: Transport {

	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")

	let type: TransportType = .ble
	private var centralManager: CBCentralManager?
	private var discoveredPeripherals: [UUID: (peripheral: CBPeripheral, lastSeen: Date)] = [:]
	private var discoveredDeviceContinuation: AsyncStream<DiscoveryEvent>.Continuation?
	private let delegate: BLEDelegate
	private var connectingPeripheral: CBPeripheral?
	private var activeConnection: BLEConnection?
	private var connectContinuation: CheckedContinuation<BLEConnection, Error>?
	private var setupCompleteContinuation: CheckedContinuation<Void, Error>?

	var status: TransportStatus = .uninitialized

	private var cleanupTask: Task<Void, Never>?
	
	// Transport properties
	var supportsManualConnection: Bool = false
	let requiresPeriodicHeartbeat = false
	var icon = Image("custom.bluetooth")
	var name = "BLE"
			
	init() {
		self.centralManager = nil
		self.discoveredPeripherals = [:]
		self.discoveredDeviceContinuation = nil
		self.delegate = BLEDelegate()
		self.delegate.setTransport(self)
	}

	nonisolated func discoverDevices() -> AsyncStream<DiscoveryEvent> {
		AsyncStream { cont in
			Task {
				self.discoveredDeviceContinuation = cont
				if self.centralManager == nil {
					try await self.setupCentralManager()
				}
				centralManager?.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
				
				setupCleanupTask()
			}
			cont.onTermination = { _ in
				Logger.transport.error("🛜 [BLE] Discovery event stream has been canecelled.")
				self.stopScanning()
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

	private func setupCentralManager() async throws {
		try await withCheckedThrowingContinuation { cont in
			self.setupCompleteContinuation = cont
			centralManager = CBCentralManager(delegate: delegate, queue: .global())
		}
	}

	private func stopScanning() {
		Logger.transport.error("🛜 [BLE] stopScanning: BLE Discovery has been stopped.")
		centralManager?.stopScan()
		discoveredPeripherals.removeAll()
		discoveredDeviceContinuation = nil
		if let state = centralManager?.state, state == .poweredOn {
			status = .ready
		} else {
			status = .uninitialized
		}
		centralManager = nil
		cleanupTask?.cancel()
		cleanupTask = nil
	}

	func handleCentralState(_ state: CBManagerState, central: CBCentralManager) {
		Logger.transport.error("🛜 [BLE] State hast transitioned to: \(cbManagerStateDescription(state))")
		switch state {
		case .poweredOn:
			status = .discovering
			self.setupCompleteContinuation?.resume()
			self.setupCompleteContinuation = nil
			
			if self.discoveredDeviceContinuation != nil {
				// We have someone already subscribed to our discovery event stream.
				// Likely a powerOff event occcurred and need to now restore scanning.
				central.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
			}

		case .poweredOff:
			status = .error("Bluetooth is powered off")
			status = .ready
			self.setupCompleteContinuation?.resume(throwing: AccessoryError.connectionFailed("Bluetooth is powered off"))
			self.setupCompleteContinuation = nil

		case .unauthorized:
			status = .error("Bluetooth access is unauthorized")
			self.setupCompleteContinuation?.resume(throwing: AccessoryError.connectionFailed("Bluetooth is unauthorized"))
			self.setupCompleteContinuation = nil

		case .unsupported:
			status = .error("Bluetooth is unsupported on this device")
			self.setupCompleteContinuation?.resume(throwing: AccessoryError.connectionFailed("Bluetooth is unsupported"))
			self.setupCompleteContinuation = nil

		case .resetting:
			status = .error("Bluetooth is resetting")
			// Perhaps don't finish, wait for next state

		case .unknown:
			status = .error("Bluetooth state is unknown")
			// Perhaps wait
		@unknown default:
			status = .error("Unknown Bluetooth state")
			self.setupCompleteContinuation?.resume(throwing: AccessoryError.connectionFailed("Unknown Bluetooth State"))
			self.setupCompleteContinuation = nil
		}
	}

	func didDiscover(peripheral: CBPeripheral, rssi: NSNumber) {
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
			Logger.transport.error("🛜 [BLE] didDiscover new device: \(peripheral.name ?? "Unknown") (\(peripheral.identifier))")
			discoveredDeviceContinuation?.yield(.deviceFound(device))
		} else {
			// Logger.transport.error("🛜 [BLE] didDiscover previosuly seen device: \(peripheral.name ?? "Unknown") (\(peripheral.identifier))")
			let rssiVal = rssi.intValue
			let deviceId = id
			discoveredPeripherals[id]?.lastSeen = Date()
			discoveredDeviceContinuation?.yield(.deviceReportedRssi(deviceId, rssiVal))
		}
	}

	func connect(to device: Device) async throws -> any Connection {
		guard let peripheral = discoveredPeripherals[UUID(uuidString: device.identifier)!] else {
			throw AccessoryError.connectionFailed("Peripheral not found")
		}
		guard let cm = centralManager else {
			throw AccessoryError.connectionFailed("Central manager not available")
		}
		
		if await self.activeConnection?.peripheral.state == .disconnected {
			Logger.transport.warning("🛜 [BLE] Connect request while an active (but disconnected).  Cleaning up")
			try await self.activeConnection?.disconnect(withError: nil)
			self.connectContinuation?.resume(throwing: CancellationError())
			self.connectContinuation = nil
			self.activeConnection = nil
		}
		
		return try await withTaskCancellationHandler {
			let newConnection: BLEConnection = try await withCheckedThrowingContinuation { cont in
				if self.connectContinuation != nil || self.activeConnection != nil {
					cont.resume(throwing: AccessoryError.connectionFailed("BLE transport is busy: already connecting or connected"))
					return
				}
				self.connectContinuation = cont
				self.connectingPeripheral = peripheral.peripheral
				cm.connect(peripheral.peripheral)
			}
			self.activeConnection = newConnection
			return newConnection
		} onCancel: {
			self.connectContinuation?.resume(throwing: CancellationError())
			self.connectContinuation = nil
			self.activeConnection = nil
			self.connectingPeripheral = nil
		}
	}

	func handlePeripheralDisconnect(peripheral: CBPeripheral) {
		if let connection = self.activeConnection {
			discoveredPeripherals.removeValue(forKey: peripheral.identifier)
			discoveredDeviceContinuation?.yield(.deviceLost(peripheral.identifier))
			Task {
				if await connection.peripheral.identifier == peripheral.identifier {
					try await connection.disconnect(withError: AccessoryError.disconnected("BLE connection lost"))
					self.activeConnection = nil
				}
			}
		}
	}

	func handleDidConnect(peripheral: CBPeripheral, central: CBCentralManager) {
		Logger.transport.debug("🛜 [BLE] handleDidConnect Connected to peripheral \(peripheral.name ?? "Unknown")")
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		let connection = BLEConnection(peripheral: peripheral, central: central)
		cont.resume(returning: connection)
		self.connectContinuation = nil
	}

	func handleDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		cont.resume(throwing: error ?? AccessoryError.connectionFailed("Connection failed"))
		self.connectContinuation = nil
		self.connectingPeripheral = nil
	}
	
	func handleWillRestoreState(dict: [String : Any]) {
		Logger.transport.debug("🛜 [BLE] willRestoreState was called, unhandled. \(dict)")
	}
	
	func manuallyConnect(withConnectionString: String) async throws {
		Logger.transport.error("🛜 [BLE] This transport does not support manual connections")
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
		transport?.handleCentralState(central.state, central: central)
	}

	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		transport?.didDiscover(peripheral: peripheral, rssi: RSSI)
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		transport?.handleDidConnect(peripheral: peripheral, central: central)
	}

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		transport?.handleDidFailToConnect(peripheral: peripheral, error: error)
	}

	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		self.transport?.handlePeripheralDisconnect(peripheral: peripheral)
	}
	
//	func centralManager(_ central: CBCentralManager, willRestoreState dict: [String : Any]) {
//		self.transport?.handleWillRestoreState(dict: dict)
//	}
}

/// Returns a human-readable description for a CBManagerState value.
fileprivate func cbManagerStateDescription(_ state: CBManagerState) -> String {
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
