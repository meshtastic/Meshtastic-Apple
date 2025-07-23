//
//  BLETransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import CoreBluetooth

class BLETransport: WirelessTransport {

	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")

	let type: TransportType = .ble
	private var centralManager: CBCentralManager?
	private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
	private var discoveredDeviceContinuation: AsyncStream<Device>.Continuation?
	private let delegate: BLEDelegate
	private var connectingPeripheral: CBPeripheral?
	private var connectedPeripheral: CBPeripheral?
	private var connectContinuation: CheckedContinuation<any Connection, Error>?
	private var setupCompleteContinuation: CheckedContinuation<Void, Error>?

	private nonisolated(unsafe) var _status: TransportStatus = .uninitialized
	nonisolated var status: TransportStatus { _status }

	init() {
		self.centralManager = nil
		self.discoveredPeripherals = [:]
		self.discoveredDeviceContinuation = nil
		self.delegate = BLEDelegate()
		self.delegate.setTransport(self)
	}

	nonisolated func discoverDevices() -> AsyncStream<Device> {
		AsyncStream { cont in
			Task {
				self.discoveredDeviceContinuation = cont
				if self.centralManager == nil {
					try await self.setupCentralManager()
				}
				centralManager?.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: nil)
			}
			cont.onTermination = { _ in
				self.stopScanning()
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
			_status = .ready
		} else {
			_status = .uninitialized
		}
		centralManager = nil
	}

	func handleCentralState(_ state: CBManagerState, central: CBCentralManager) {
		switch state {
		case .poweredOn:
			_status = .discovering
			self.setupCompleteContinuation?.resume()
			self.setupCompleteContinuation = nil

		case .poweredOff:
			_status = .error("Bluetooth is powered off")
			self.connectContinuation?.resume(throwing: AccessoryError.connectionFailed("Bluetooth is powered off"))
			self.setupCompleteContinuation = nil

		case .unauthorized:
			_status = .error("Bluetooth access is unauthorized")
			self.connectContinuation?.resume(throwing: AccessoryError.connectionFailed("Bluetooth is unauthiorized"))
			self.setupCompleteContinuation = nil

		case .unsupported:
			_status = .error("Bluetooth is unsupported on this device")
			self.connectContinuation?.resume(throwing: AccessoryError.connectionFailed("Bluetooth is unsupported"))
			self.setupCompleteContinuation = nil

		case .resetting:
			_status = .error("Bluetooth is resetting")
			// Perhaps don't finish, wait for next state

		case .unknown:
			_status = .error("Bluetooth state is unknown")
			// Perhaps wait
		@unknown default:
			_status = .error("Unknown Bluetooth state")
			self.connectContinuation?.resume(throwing: AccessoryError.connectionFailed("Unknown Bluetooth State"))
			self.setupCompleteContinuation = nil
		}
	}

	func didDiscover(peripheral: CBPeripheral, rssi: NSNumber) {
		let id = peripheral.identifier
		let isNew = discoveredPeripherals[id] == nil
		if isNew {
			discoveredPeripherals[id] = peripheral
		}
		let device = Device(id: id,
							name: peripheral.name ?? "Unknown",
							transportType: .ble,
							identifier: id.uuidString,
							rssi: rssi.intValue)
		if isNew {
			discoveredDeviceContinuation?.yield(device)
		}
		let rssiVal = rssi.intValue
		let deviceId = id
		rssiUpdateContinuation?.yield((deviceId: deviceId, rssi: rssiVal))
	}

	func connect(to device: Device) async throws -> any Connection {
		guard let peripheral = discoveredPeripherals[UUID(uuidString: device.identifier)!] else {
			throw AccessoryError.connectionFailed("Peripheral not found")
		}
		guard let cm = centralManager else {
			throw AccessoryError.connectionFailed("Central manager not available")
		}
		return try await withCheckedThrowingContinuation { cont in
			if self.connectContinuation != nil || self.connectedPeripheral != nil {
				cont.resume(throwing: AccessoryError.connectionFailed("BLE transport is busy: already connecting or connected"))
				return
			}
			self.connectContinuation = cont
			self.connectingPeripheral = peripheral
			cm.connect(peripheral)
		}
	}

	func setConnected(peripheral: CBPeripheral) {
		self.connectedPeripheral = peripheral
	}

	func handlePeripheralDisconnect(peripheral: CBPeripheral) {
		if self.connectedPeripheral?.identifier == peripheral.identifier {
			self.connectedPeripheral = nil
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
				self.setConnected(peripheral: peripheral)
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

	private var rssiUpdateContinuation: AsyncStream<TransportRSSIUpdate>.Continuation?
	func rssiStream() async -> AsyncStream<TransportRSSIUpdate> {
		AsyncStream<TransportRSSIUpdate> { cont in
			self.rssiUpdateContinuation = cont
		}
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
