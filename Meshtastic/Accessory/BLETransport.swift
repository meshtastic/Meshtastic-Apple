//
//  BLETransport.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import CoreBluetooth
import SwiftUI

actor BLETransport: WirelessTransport {

	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")

	let type: TransportType = .ble
	private var centralManager: CBCentralManager?
	private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
	private var continuation: AsyncStream<Device>.Continuation?
	private let delegate: BLEDelegate
	private var connectedPeripheral: CBPeripheral?

	private nonisolated(unsafe) var _status: TransportStatus = .uninitialized
	nonisolated var status: TransportStatus { _status }

	init() {
		self.centralManager = nil
		self.discoveredPeripherals = [:]
		self.continuation = nil
		self.delegate = BLEDelegate()
		self.delegate.setTransport(self)
	}

	nonisolated func discoverDevices() -> AsyncStream<Device> {
		AsyncStream { cont in
			Task {
				await self.setupCentralManager(with: cont)
			}
		}
	}

	private func setupCentralManager(with continuation: AsyncStream<Device>.Continuation) {
		self.continuation = continuation
		centralManager = CBCentralManager(delegate: delegate, queue: .main)
		delegate.startScanning(with: continuation)
		continuation.onTermination = { _ in
			Task { await self.stopScanning() }
		}
	}

	private func stopScanning() {
		centralManager?.stopScan()
		discoveredPeripherals.removeAll()
		delegate.stopScanning()
		continuation = nil
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
			central.scanForPeripherals(withServices: [meshtasticServiceCBUUID], options: nil)
		case .poweredOff:
			_status = .error("Bluetooth is powered off")
			continuation?.finish()
		case .unauthorized:
			_status = .error("Bluetooth access is unauthorized")
			continuation?.finish()
		case .unsupported:
			_status = .error("Bluetooth is unsupported on this device")
			continuation?.finish()
		case .resetting:
			_status = .error("Bluetooth is resetting")
			// Perhaps don't finish, wait for next state
		case .unknown:
			_status = .error("Bluetooth state is unknown")
			// Perhaps wait
		@unknown default:
			_status = .error("Unknown Bluetooth state")
			continuation?.finish()
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
			continuation?.yield(device)
		}
		let rssiVal = rssi.intValue
		let deviceId = id
		Task {
			rssiUpdateContinuation?.yield((deviceId: deviceId, rssi: rssiVal))
		}
	}

	func connect(to device: Device) async throws -> any Connection {
		guard let peripheral = discoveredPeripherals[UUID(uuidString: device.identifier)!] else {
			throw AccessoryError.connectionFailed("Peripheral not found")
		}
		guard let cm = centralManager else {
			throw AccessoryError.connectionFailed("Central manager not available")
		}
		return try await withCheckedThrowingContinuation { cont in
			if self.delegate.connectContinuation != nil || self.connectedPeripheral != nil {
				cont.resume(throwing: AccessoryError.connectionFailed("BLE transport is busy: already connecting or connected"))
				return
			}
			cm.connect(peripheral)
			self.delegate.connect(to: peripheral, central: cm, continuation: cont)
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

	private var rssiUpdateContinuation: 	AsyncStream<TransportRSSIUpdate>.Continuation?
	func rssiStream() async -> AsyncStream<TransportRSSIUpdate> {
		AsyncStream<TransportRSSIUpdate> { cont in
			self.rssiUpdateContinuation = cont
		}
	}
}

class BLEDelegate: NSObject, CBCentralManagerDelegate {
	private weak var transport: BLETransport?
	private var continuation: AsyncStream<Device>.Continuation?
	fileprivate var connectContinuation: CheckedContinuation<any Connection, Error>?
	private var connectingPeripheral: CBPeripheral?

	override init() {
		super.init()
	}

	func setTransport(_ transport: BLETransport) {
		self.transport = transport
	}

	func startScanning(with continuation: AsyncStream<Device>.Continuation) {
		self.continuation = continuation
	}

	func stopScanning() {
		continuation?.finish()
		continuation = nil
		connectContinuation = nil
		connectingPeripheral = nil
	}

	func connect(to peripheral: CBPeripheral, central: CBCentralManager, continuation: CheckedContinuation<any Connection, Error>) {
		self.connectContinuation = continuation
		self.connectingPeripheral = peripheral
	}

	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		Task { await transport?.handleCentralState(central.state, central: central) }
	}

	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
		Task { await transport?.didDiscover(peripheral: peripheral, rssi: RSSI) }
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		var connection: BLEConnection!
		let readyCallback: (Result<Void, Error>) -> Void = { result in
			switch result {
			case .success:
				Task { await self.transport?.setConnected(peripheral: peripheral) }
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

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		guard let cont = connectContinuation,
			  let connPeripheral = connectingPeripheral,
			  peripheral.identifier == connPeripheral.identifier else {
			return
		}
		cont.resume(throwing: error ?? AccessoryError.connectionFailed("Connection failed"))
		self.connectContinuation = nil
		self.connectingPeripheral = nil
	}

	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		Task {
			await self.transport?.handlePeripheralDisconnect(peripheral: peripheral)
		}
	}
}
