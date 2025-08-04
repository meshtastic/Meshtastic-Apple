//
//  BLEConnection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
import CoreBluetooth
import OSLog
import MeshtasticProtobufs

let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")
let TORADIO_UUID = CBUUID(string: "0xF75C76D2-129E-4DAD-A1DD-7866124401E7")
let FROMRADIO_UUID = CBUUID(string: "0x2C55E69E-4993-11ED-B878-0242AC120002")
let FROMNUM_UUID = CBUUID(string: "0xED9DA18C-A800-4F66-A670-AA7547E34453")
let LOGRADIO_UUID = CBUUID(string: "0x5a3d6e49-06e6-4423-9944-e9de8cdf9547")

extension CBCharacteristic {
	
	var meshtasticCharacteristicName: String {
		switch self.uuid {
		case TORADIO_UUID:
			return "TORADIO"
		case FROMRADIO_UUID:
			return "FROMRADIO"
		case FROMNUM_UUID:
			return "FROMNUM"
		case LOGRADIO_UUID:
			return "LOGRADIO"
		default:
			return "UNKNOWN (\(self.uuid.uuidString))"
		}
	}
}

actor BLEConnection: Connection {
	
	var proxy: BLEConnectionProxy
	var isConnected: Bool { proxy.isConnected }
	
	var peripheral: CBPeripheral
	private var needsDrain: Bool = false
	private var isDraining: Bool = false
	
	private var fromNumTask: Task <Void, Error>?
	
	private var connectionStreamContinuation: AsyncStream<ConnectionEvent>.Continuation?
	
	init(peripheral: CBPeripheral, central: CBCentralManager, readyCallback: @escaping (Result<Void, Error>) -> Void) {
		self.peripheral = peripheral
		self.proxy = BLEConnectionProxy(peripheral: peripheral,
										central: central, readyCallback: readyCallback)
	}
	
	func didRecieveFromRadio() async {
		try? startDrainPendingPackets()
	}
	
	func send(_ data: ToRadio) async throws {
		try await proxy.send(data)
	}
	
	func disconnect(userInitiated: Bool) async throws {
		try await self.disconnect(withError: userInitiated ? nil : AccessoryError.disconnected("Unknown Error"))
	}
	
	func disconnect(withError error: Error? = nil) async throws {
		self.fromNumTask?.cancel()
		try proxy.disconnect()
		
		if let error {
			connectionStreamContinuation?.yield(.error(error))
		} else {
			connectionStreamContinuation?.yield(.userDisconnected)
		}
		connectionStreamContinuation?.finish()
		connectionStreamContinuation = nil
	}
	
	func startDrainPendingPackets() throws {
		guard isConnected else {
			throw AccessoryError.ioFailed("Not connected")
		}
		needsDrain = true
		if !isDraining {
			Task {
				isDraining = true
				defer { isDraining = false }
				while needsDrain {
					needsDrain = false
					do {
						try await drainPendingPackets()
					} catch {
						// Handle or log error as needed; for now, just continue to allow retry on next notification
					}
				}
			}
		}
	}
	
	func drainPendingPackets() async throws {
		guard isConnected else {
			throw AccessoryError.ioFailed("Not connected")
		}
		repeat {
			do {
				let data = try await proxy.read()
				
				if data.count == 0 {
					break
				}
				
				let decodedInfo = try FromRadio(serializedBytes: data)
				connectionStreamContinuation?.yield(.data(decodedInfo))
			} catch {
				try? await self.disconnect(withError: error)
				throw error  // Re-throw to propagate up to the caller for handling
			}
		} while true
	}
	
	func didReceiveLogMessage(_ logMessage: String) {
		self.connectionStreamContinuation?.yield(.logMessage(logMessage))
	}
	
	func didUpdateRssi(_ rssi: Int) {
		self.connectionStreamContinuation?.yield(.rssiUpdate(rssi))
	}
	
	func getPacketStream() -> AsyncStream<ConnectionEvent> {
		AsyncStream<ConnectionEvent> { continuation in
			self.connectionStreamContinuation = continuation
		}
	}
	
	func connect() async -> AsyncStream<ConnectionEvent> {
		self.fromNumTask = Task {
			for await event in self.proxy.eventNotifications() {
				switch event {
				case .fromNum:
					try? await self.drainPendingPackets()
				case .logMessage(let message):
					self.didReceiveLogMessage(message)
				case .rssiUpdate(let rssi):
					self.didUpdateRssi(rssi)
				}
			}
		}
		return self.getPacketStream()
	}
}

class BLEConnectionProxy: NSObject, CBPeripheralDelegate {
	// Similar to ConnectionEvent, but this one has .fromNum
	enum ProxyEvent {
		case fromNum(Data)
		case logMessage(String)
		case rssiUpdate(Int)
	}
	
	private var writeContinuations: [CheckedContinuation<Void, Error>] = []
	
	fileprivate var TORADIO_characteristic: CBCharacteristic?
	fileprivate var FROMRADIO_characteristic: CBCharacteristic?
	fileprivate var FROMNUM_characteristic: CBCharacteristic?
	fileprivate var LOGRADIO_characteristic: CBCharacteristic?
	
	private let readyCallback: (Result<Void, Error>) -> Void
	private var eventContinuation: AsyncStream<ProxyEvent>.Continuation?
	
	let peripheral: CBPeripheral
	weak var central: CBCentralManager?
	
	var isConnected: Bool { peripheral.state == .connected }
	
	fileprivate var readContinuation: CheckedContinuation<Data, Error>?
	
	init(peripheral: CBPeripheral, central: CBCentralManager, readyCallback: @escaping (Result<Void, Error>) -> Void) {
		self.peripheral = peripheral
		self.readyCallback = readyCallback
		self.central = central
		super.init()
		
		peripheral.delegate = self
		peripheral.discoverServices([meshtasticServiceCBUUID])
	}
	
	// MARK: CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let error = error {
			readyCallback(.failure(error))
			return
		}
		guard let services = peripheral.services else { return }
		for service in services where service.uuid == meshtasticServiceCBUUID {
			peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID, LOGRADIO_UUID], for: service)
			Logger.transport.info("🛜  [BLE] Service for Meshtastic discovered by \(peripheral.name ?? "Unknown", privacy: .public)")
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		if let error = error {
			readyCallback(.failure(error))
			return
		}
		guard let characteristics = service.characteristics else {
			readyCallback(.failure(AccessoryError.discoveryFailed("No characteristics")))
			return
		}
		
		for characteristic in characteristics {
			switch characteristic.uuid {
			case TORADIO_UUID:
				Logger.transport.info("🛜  [BLE] did discover TORADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				TORADIO_characteristic = characteristic
				
			case FROMRADIO_UUID:
				Logger.transport.info("🛜  [BLE] did discover FROMRADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)
				
			case FROMNUM_UUID:
				Logger.transport.info("🛜  [BLE] did discover FROMNUM (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMNUM_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)
				
			case LOGRADIO_UUID:
				Logger.transport.info("🛜  [BLE] did discover LOGRADIO (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				LOGRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)
				
			default:
				Logger.transport.info("🛜  [BLE] did discover unsupported \(characteristic.uuid) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
			}
		}
		
		if TORADIO_characteristic != nil && FROMRADIO_characteristic != nil && FROMNUM_characteristic != nil {
			Logger.transport.info("🛜  [BLE] characteristics ready")
			readyCallback(.success(()))
			// Read initial RSSI on ready
			peripheral.readRSSI()
		} else {
			Logger.transport.info("🛜  [BLE] Missing required characteristics")
			readyCallback(.failure(AccessoryError.discoveryFailed("Missing required characteristics")))
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		Logger.transport.info("🛜 [BLE] Did update value for \(characteristic.meshtasticCharacteristicName)=\(characteristic.value ?? Data())")
		if let error = error {
			if characteristic.uuid == FROMRADIO_UUID {
				readContinuation?.resume(throwing: error)
				readContinuation = nil
			}
			return
		}
		guard let value = characteristic.value else { return }
		
		switch characteristic.uuid {
		case FROMRADIO_UUID:
			if let readContinuation {
				readContinuation.resume(returning: value)
				self.readContinuation = nil
			}
		case FROMNUM_UUID:
			eventContinuation?.yield(.fromNum(value))
			
		case LOGRADIO_UUID:
			if let value = characteristic.value,
			   let logRecord = try? LogRecord(serializedBytes: value) {
				eventContinuation?.yield(.logMessage(logRecord.stringRepresentation))
			}
			
		default:
			break
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		guard characteristic.uuid == TORADIO_UUID, !writeContinuations.isEmpty else { return }
		let cont = writeContinuations.removeFirst()
		if let error = error {
			Logger.transport.error("🛜 [BLE] Did write for \(characteristic.meshtasticCharacteristicName) with error \(error)")
			cont.resume(throwing: error)
		} else {
			Logger.transport.error("🛜 [BLE] Did write for \(characteristic.meshtasticCharacteristicName)")
			cont.resume()
		}
	}
	
	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		if let error = error {
			Logger.transport.error("🛜 [BLE] Error reading RSSI: \(error.localizedDescription)")
			return
		}
		eventContinuation?.yield(.rssiUpdate(RSSI.intValue))
	}
	
	func send(_ data: ToRadio) async throws {
		guard let characteristic = TORADIO_characteristic, isConnected else {
			throw AccessoryError.ioFailed("Not connected or characteristic not found")
		}
		guard let binaryData = try? data.serializedData() else {
			throw AccessoryError.ioFailed("Failed to serialize data")
		}
		guard characteristic.properties.contains(.write) ||
				characteristic.properties.contains(.writeWithoutResponse) else {
			throw AccessoryError.ioFailed("Characteristic does not support write")
		}
		
		let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
		try await withCheckedThrowingContinuation { cont in
			if writeType == .withoutResponse {
				peripheral.writeValue(binaryData, for: characteristic, type: writeType)
				cont.resume()
			} else {
				writeContinuations.append(cont)
				peripheral.writeValue(binaryData, for: characteristic, type: writeType)
			}
		}
	}
	
	func read() async throws -> Data {
		guard let FROMRADIO_characteristic else {
			throw AccessoryError.ioFailed("No FROMRADIO_characteristic ")
		}
		let data: Data = try await withCheckedThrowingContinuation { cont in
			readContinuation = cont
			peripheral.readValue(for: FROMRADIO_characteristic)
		}
		if data.isEmpty {
			Logger.transport.error("🛜 [BLE] Received empty data, ending drain operation.")
		}
		return data
	}
	
	func disconnect() throws {
		if peripheral.state == .connected {
			if let characteristic = FROMRADIO_characteristic {
				peripheral.setNotifyValue(false, for: characteristic)
			}
			if let characteristic = FROMNUM_characteristic {
				peripheral.setNotifyValue(false, for: characteristic)
			}
			if let characteristic = LOGRADIO_characteristic {
				peripheral.setNotifyValue(false, for: characteristic)
			}
		}
		
		if let central = central, peripheral.state == .connected {
			central.cancelPeripheralConnection(peripheral)
		}
		peripheral.delegate = nil
		
		eventContinuation?.finish()
		eventContinuation = nil
		
		readContinuation?.resume(throwing: AccessoryError.disconnected("Unknown error"))
		readContinuation = nil
	}
	
	func eventNotifications() -> AsyncStream<ProxyEvent> {
		return AsyncStream { continuation in
			self.eventContinuation = continuation
			continuation.onTermination = { _ in
				self.eventContinuation = nil
			}
		}
	}
	
}
