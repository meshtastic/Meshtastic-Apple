//
//  BLEConnection.swift
//  Meshtastic
//
//  Created by Jake Bordens on 7/10/25.
//

import Foundation
@preconcurrency import CoreBluetooth
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
	let type = TransportType.ble
	
	var delegate: BLEConnectionDelegate
	var peripheral: CBPeripheral
	var central: CBCentralManager
	private var needsDrain: Bool = false
	private var isDraining: Bool = false
	
	fileprivate var TORADIO_characteristic: CBCharacteristic?
	fileprivate var FROMRADIO_characteristic: CBCharacteristic?
	fileprivate var FROMNUM_characteristic: CBCharacteristic?
	fileprivate var LOGRADIO_characteristic: CBCharacteristic?
	
	private var connectionStreamContinuation: AsyncStream<ConnectionEvent>.Continuation?
	
	private var connectContinuation: CheckedContinuation<Void, Error>?
	private var writeContinuation: CheckedContinuation<Void, Error>?
	private var readContinuation: CheckedContinuation<Data, Error>?
	
	private var rssiTask: Task<Void, Never>?
	
	var isConnected: Bool { peripheral.state == .connected }
	var transport: BLETransport?
	
	init(peripheral: CBPeripheral, central: CBCentralManager, transport: BLETransport) {
		self.peripheral = peripheral
		self.central = central
		self.transport = transport
		self.delegate = BLEConnectionDelegate(peripheral: peripheral)
		self.delegate.setConnection(self)
	}
	
	func disconnect(withError error: Error? = nil, shouldReconnect: Bool) async throws {
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
		
		transport?.connectionDidDisconnect()
		
		central.cancelPeripheralConnection(peripheral)
		peripheral.delegate = nil
				
		writeContinuation?.resume(throwing: AccessoryError.disconnected("Unknown error"))
		writeContinuation = nil
		
		if let error {
			// Inform the AccessoryManager of the error and intent to reconnect
			if shouldReconnect {
				connectionStreamContinuation?.yield(.error(error))
			} else {
				connectionStreamContinuation?.yield(.errorWithoutReconnect(error))
			}
		} else {
			connectionStreamContinuation?.yield(.disconnected(shouldReconnect: shouldReconnect))
		}

		connectionStreamContinuation?.finish()
		connectionStreamContinuation = nil
		
		rssiTask?.cancel()
		rssiTask = nil
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
				let data = try await read()
				
				if data.count == 0 {
					break
				}
				
				let decodedInfo = try FromRadio(serializedBytes: data)
				connectionStreamContinuation?.yield(.data(decodedInfo))
			} catch {
				try? await self.disconnect(withError: error, shouldReconnect: true)
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
	
	func discoverServices() async throws {
		try await withCheckedThrowingContinuation { cont in
			self.connectContinuation = cont
			peripheral.discoverServices([meshtasticServiceCBUUID])
		}
	}
	
	func connect() async throws -> AsyncStream<ConnectionEvent> {
		try await discoverServices()
		startRSSITask()
		return self.getPacketStream()
	}
	
	func startRSSITask() {
		if let task = self.rssiTask {
			task.cancel()
		}
		self.rssiTask = Task {
			do {
				while !Task.isCancelled {
					try await Task.sleep(for: .seconds(10))
					peripheral.readRSSI()
				}
			} catch {
				
			}
		}
	}
	
	func didDiscoverServices(error: Error? ) {
		if let error = error {
			connectContinuation?.resume(throwing: error)
			return
		}
		
		guard let services = peripheral.services else { return }
		
		for service in services where service.uuid == meshtasticServiceCBUUID {
			peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID, LOGRADIO_UUID], for: service)
			Logger.transport.info("🛜  [BLE] Service for Meshtastic discovered by \(self.peripheral.name ?? "Unknown", privacy: .public)")
		}
	}
	
	func didDiscoverCharacteristicsFor(service: CBService, error: Error?) {
		if let error = error {
			connectContinuation?.resume(throwing: error)
			self.connectionStreamContinuation = nil
			return
		}
		guard let characteristics = service.characteristics else {
			connectContinuation?.resume(throwing: AccessoryError.discoveryFailed("No characteristics"))
			self.connectionStreamContinuation = nil
			return
		}
		
		for characteristic in characteristics {
			switch characteristic.uuid {
			case TORADIO_UUID:
				Logger.transport.info("🛜 [BLE] did discover TORADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				TORADIO_characteristic = characteristic
				
			case FROMRADIO_UUID:
				Logger.transport.info("🛜 [BLE] did discover FROMRADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)
				
			case FROMNUM_UUID:
				Logger.transport.info("🛜 [BLE] did discover FROMNUM (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMNUM_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)
				
			case LOGRADIO_UUID:
				Logger.transport.info("🛜 [BLE] did discover LOGRADIO (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				LOGRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)
				
			default:
				Logger.transport.info("🛜 [BLE] did discover unsupported \(characteristic.uuid) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
			}
		}
		
		if TORADIO_characteristic != nil && FROMRADIO_characteristic != nil && FROMNUM_characteristic != nil {
			Logger.transport.info("🛜 [BLE] characteristics ready")
			connectContinuation?.resume()
			self.connectionStreamContinuation = nil
			
			// Read initial RSSI on ready
			peripheral.readRSSI()
		} else {
			Logger.transport.info("🛜 [BLE] Missing required characteristics")
			connectContinuation?.resume(throwing: AccessoryError.discoveryFailed("Missing required characteristics"))
		}
	}
	
	func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
		Logger.transport.debug("🛜 [BLE] Did update value for \(characteristic.meshtasticCharacteristicName, privacy: .public)=\(characteristic.value ?? Data(), privacy: .public)")
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
			try? startDrainPendingPackets()
			
		case LOGRADIO_UUID:
			if let value = characteristic.value,
			   let logRecord = try? LogRecord(serializedBytes: value) {
				self.didReceiveLogMessage(logRecord.stringRepresentation)
			}
			
		default:
			break
		}
	}
	
	func didWriteValueFor(characteristic: CBCharacteristic, error: Error?) {
		guard characteristic.uuid == TORADIO_UUID, let writeContinuation else { return }
		if let error = error {
			Logger.transport.error("🛜 [BLE] Did write for \(characteristic.meshtasticCharacteristicName, privacy: .public) with error \(error, privacy: .public)")
			writeContinuation.resume(throwing: error)
			Task { try await self.handlePeripheralError(error: error) }
		} else {
			#if DEBUG
			// Too much logging to report every write.
			Logger.transport.error("🛜 [BLE] Did write for \(characteristic.meshtasticCharacteristicName, privacy: .public)")
			#endif
			writeContinuation.resume()
		}
		self.writeContinuation = nil
	}
	
	func didReadRSSI(RSSI: NSNumber, error: Error?) {
		if let error = error {
			Logger.transport.error("🛜 [BLE] Error reading RSSI: \(error.localizedDescription)")
			return
		}
		connectionStreamContinuation?.yield(.rssiUpdate(RSSI.intValue))
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
				writeContinuation = cont
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
			Logger.transport.debug("🛜 [BLE] Received empty data, ending drain operation.")
		}
		return data
	}
	
	func handlePeripheralError(error: Error) async throws {
		var shouldReconnect = false
		switch error {
		case let cbError as CBError:
			switch cbError.code {
			case .unknown: // 0
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to unknown error.")
			case .invalidParameters: // 1
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to invalid parameters.")
			case .invalidHandle: // 2
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to invalid handle.")
			case .notConnected: // 3
				Logger.transport.error("🛜 [BLEConnection] Disconnected because device was not connected.")
			case .outOfSpace: // 4
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to out of space.")
			case .operationCancelled: // 5
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to operation cancelled.")
			case .connectionTimeout: // 6
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to connection timeout.")
				shouldReconnect = true
			case .peripheralDisconnected: // 7
				// Likely prompting for a PIN
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLEConnection] Disconnected by peripheral.")
				shouldReconnect = true
			case .uuidNotAllowed: // 8
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to UUID not allowed.")
			case .alreadyAdvertising: // 9
				Logger.transport.error("🛜 [BLEConnection] Disconnected because already advertising.")
			case .connectionFailed: // 10
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to connection failure.")
			case .connectionLimitReached: // 11
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to connection limit reached.")
			case .unknownDevice, .unkownDevice: // 12
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to unknown device.")
			case .operationNotSupported: // 13
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to operation not supported.")
			case .peerRemovedPairingInformation: // 14
				// Should disconnect and not retry
				Logger.transport.error("🛜 [BLEConnection] Disconnected because peer removed pairing information.")
				return
			case .encryptionTimedOut: // 15
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to encryption timeout.")
			case .tooManyLEPairedDevices: // 16
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to too many LE paired devices.")
				
				// leGatt cases are watchOS only
			case .leGattExceededBackgroundNotificationLimit: // 17
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to exceeding LE GATT background notification limit.")
			case .leGattNearBackgroundNotificationLimit: // 18
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to nearing LE GATT background notification limit.")
				
			@unknown default:
				Logger.transport.error("🛜 [BLEConnection] Disconnected due to unknown future error code: \(cbError.code.rawValue)")
			}
		case let otherError:
			Logger.transport.error("🛜 [BLEConnection] Disconnected with non-CBError: \(otherError.localizedDescription)")
		}
		
		// Inform the active connection that there was an error and it should disconnect
		Task {
			try await self.disconnect(withError: error, shouldReconnect: shouldReconnect)
		}
	}
	
	func appDidEnterBackground() {
		if let task = self.rssiTask {
			Logger.transport.info("🛜 [BLE] App is entering the background, suspending RSSI reports.")
			task.cancel()
			self.rssiTask = nil
		}
	}
	
	func appDidBecomeActive() {
		if self.rssiTask == nil {
			Logger.transport.info("🛜 [BLE] App is active, restarting RSSI reports.")
			self.startRSSITask()
		}
	}
}

class BLEConnectionDelegate: NSObject, CBPeripheralDelegate {
	private weak var connection: BLEConnection?
	let peripheral: CBPeripheral
		
	init(peripheral: CBPeripheral) {
		self.peripheral = peripheral
		super.init()
		peripheral.delegate = self
	}
	
	func setConnection(_ connection: BLEConnection) {
		self.connection = connection
	}
	
	// MARK: CBPeripheralDelegate
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		Task { await connection?.didDiscoverServices(error: error) }
	}
	
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		Task { await connection?.didDiscoverCharacteristicsFor(service: service, error: error) }
	}
	
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		Task { await connection?.didUpdateValueFor(characteristic: characteristic, error: error) }
	}
	
	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		Task { await connection?.didWriteValueFor(characteristic: characteristic, error: error) }
	}
	
	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		Task { await connection?.didReadRSSI(RSSI: RSSI, error: error) }
	}
}
