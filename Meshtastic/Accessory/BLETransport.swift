//
//  BLETransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import CoreBluetooth
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
	var icon = Image(systemName: "wave.3.forward.circle")
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
				centralManager?.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: nil)
				
				setupCleanupTask()
			}
			cont.onTermination = { _ in
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
		}
	}

	private func setupCentralManager() async throws {
		try await withCheckedThrowingContinuation { cont in
			self.setupCompleteContinuation = cont
			centralManager = CBCentralManager(delegate: delegate, queue: .main)
		}
	}

	private func stopScanning() {
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
		switch state {
		case .poweredOn:
			status = .discovering
			self.setupCompleteContinuation?.resume()
			self.setupCompleteContinuation = nil

		case .poweredOff:
			status = .error("Bluetooth is powered off")
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
			discoveredDeviceContinuation?.yield(.deviceFound(device))
		} else {
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
	}

	func handlePeripheralDisconnect(peripheral: CBPeripheral) {
		if let connection = self.activeConnection {
			Task {
				if await connection.peripheral.identifier == peripheral.identifier {
					try await connection.disconnect()
					self.activeConnection = nil
				}
			}
		}
	}

	func handleDidConnect(peripheral: CBPeripheral, central: CBCentralManager) {
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		var connection: BLEConnection!
		let readyCallback: (Result<Void, Error>) -> Void = { result in
			switch result {
			case .success:
				cont.resume(returning: connection)
			case .failure(let error):
				cont.resume(throwing: error)
				central.cancelPeripheralConnection(peripheral)
			}
			self.connectContinuation = nil
			self.connectingPeripheral = nil
		}
		connection = BLEConnection(peripheral: peripheral, central: central, readyCallback: readyCallback)
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
}
