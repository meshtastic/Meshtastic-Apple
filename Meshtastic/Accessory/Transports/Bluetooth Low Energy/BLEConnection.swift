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
	private var writeContinuations: [CheckedContinuation<Void, Error>]
	private var readContinuations: [CheckedContinuation<Data, Error>]
	
	private var rssiTask: Task<Void, Never>?
	
	var isConnected: Bool { peripheral.state == .connected }
	var transport: BLETransport?
	
	init(peripheral: CBPeripheral, central: CBCentralManager, transport: BLETransport) {
		self.peripheral = peripheral
		self.central = central
		self.transport = transport
		self.delegate = BLEConnectionDelegate(peripheral: peripheral)
		self.writeContinuations = []
		self.readContinuations = []
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
		
		await transport?.connectionDidDisconnect(fromPeripheral: peripheral)
		
		central.cancelPeripheralConnection(peripheral)
		peripheral.delegate = nil
				
		while !writeContinuations.isEmpty {
			let writeContinuation = writeContinuations.removeFirst()
			writeContinuation.resume(throwing: AccessoryError.disconnected("Unknown error"))
		}

		while !readContinuations.isEmpty {
			let readContinuation = readContinuations.removeFirst()
			readContinuation.resume(throwing: AccessoryError.disconnected("Unknown error"))
		}

		if let error {
			// Inform the AccessoryManager of the error and intent to reconnect
			if shouldReconnect {
				if let cbError = error as? CBError {
					connectionStreamContinuation?.yield(.error(AccessoryError.coreBluetoothError(cbError)))
				} else if let attError = error as? CBATTError {
					connectionStreamContinuation?.yield(.error(AccessoryError.coreBluetoothATTError(attError)))
				} else {
					connectionStreamContinuation?.yield(.error(error))
				}
			} else {
				if let cbError = error as? CBError {
					connectionStreamContinuation?.yield(.errorWithoutReconnect(AccessoryError.coreBluetoothError(cbError)))
				} else if let attError = error as? CBATTError {
					connectionStreamContinuation?.yield(.errorWithoutReconnect(AccessoryError.coreBluetoothATTError(attError)))
				} else {
					connectionStreamContinuation?.yield(.errorWithoutReconnect(error))
				}
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
		do {
			// Make sure we're connected
			guard self.peripheral.state == .connected else {
				throw AccessoryError.ioFailed("BLE peripheral not connected")
			}
			
			return try await withTaskCancellationHandler {
				try await discoverServices()
				startRSSITask()
				return self.getPacketStream()
			} onCancel: {
				Task {
					await self.continueConnectionProcess(throwing: CancellationError())
					await self.notifyTransportOfDisconnect()
				}
			}
		} catch {
			// Before we throw, let the transport know we didn't successfully connect
			await self.notifyTransportOfDisconnect()
			throw error
		}
	}
	
	private func continueConnectionProcess(throwing error: Error? = nil) {
		if let error {
			self.connectContinuation?.resume(throwing: error)
		} else {
			self.connectContinuation?.resume()
		}
		self.connectContinuation = nil
	}
	
	private func notifyTransportOfDisconnect() async {
		await transport?.connectionDidDisconnect(fromPeripheral: peripheral)
	}
	
	func startRSSITask() {
		if let task = self.rssiTask {
			task.cancel()
		}
		self.rssiTask = Task { [weak self] in
			guard let self else { return }
			do {
				while !Task.isCancelled {
					try await Task.sleep(for: .seconds(10))
					await self.requestRSSIRead()
				}
			} catch {
				
			}
		}
	}
	
	private func requestRSSIRead() {
		peripheral.readRSSI()
	}
	
	func didDiscoverServices(error: Error? ) {
		if let error = error {
			self.continueConnectionProcess(throwing: error)
			return
		}
		
		guard let services = peripheral.services else {
			self.continueConnectionProcess(throwing: AccessoryError.discoveryFailed("No services found"))
			return
		}
		
		var foundMeshtasticService = false
		for service in services where service.uuid == meshtasticServiceCBUUID {
			foundMeshtasticService = true
			peripheral.discoverCharacteristics([TORADIO_UUID, FROMRADIO_UUID, FROMNUM_UUID, LOGRADIO_UUID], for: service)
			Logger.transport.info("🛜  [BLE] Service for Meshtastic discovered by \(self.peripheral.name ?? "Unknown", privacy: .public)")
		}
		
		if !foundMeshtasticService {
			self.continueConnectionProcess(throwing: AccessoryError.discoveryFailed("Meshtastic service not found"))
		}
	}
	
	func didDiscoverCharacteristicsFor(service: CBService, error: Error?) {
		if let error = error {
			self.continueConnectionProcess(throwing: error)
			return
		}
		guard let characteristics = service.characteristics else {
			self.continueConnectionProcess(throwing: AccessoryError.discoveryFailed("No characteristics"))
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
			self.continueConnectionProcess()
			
			// Read initial RSSI on ready
			peripheral.readRSSI()
		} else {
			Logger.transport.info("🛜 [BLE] Missing required characteristics")
			self.continueConnectionProcess(throwing: AccessoryError.discoveryFailed("Missing required characteristics"))
		}
	}
	
	func didUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
		if let error = error {
			if characteristic.uuid == FROMRADIO_UUID {
				Logger.transport.debug("🛜 [BLE] Error updating value for \(characteristic.meshtasticCharacteristicName, privacy: .public): \(error)")
				if !readContinuations.isEmpty {
					let readContinuation = self.readContinuations.removeFirst()
					readContinuation.resume(throwing: error)
				}
			}
			Task { try await self.handlePeripheralError(error: error) }
			return
		}
		Logger.transport.debug("🛜 [BLE] Did update value for \(characteristic.meshtasticCharacteristicName, privacy: .public)=\(characteristic.value ?? Data(), privacy: .public)")

		guard let value = characteristic.value else { return }
		
		switch characteristic.uuid {
		case FROMRADIO_UUID:
			if !readContinuations.isEmpty {
				let readContinuation = self.readContinuations.removeFirst()
				readContinuation.resume(returning: value)
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
		guard characteristic.uuid == TORADIO_UUID else {
			Logger.transport.error("🛜 [BLE] didWriteValueFor a characteristic other than TORADIO_UUID.  Should not happen!")
			return
		}
		guard !writeContinuations.isEmpty else {
			Logger.transport.error("🛜 [BLE] didWriteValueFor with no waiting continuations.  Should not happen!")
			return
		}
		
		let writeContinuation = writeContinuations.removeFirst()
		
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
		try await withCheckedThrowingContinuation { newWriteContinuation in
			if writeType == .withoutResponse {
				peripheral.writeValue(binaryData, for: characteristic, type: writeType)
				newWriteContinuation.resume()
			} else {
				writeContinuations.append(newWriteContinuation)
				peripheral.writeValue(binaryData, for: characteristic, type: writeType)
			}
		}
	}
	
	func read() async throws -> Data {
		guard let FROMRADIO_characteristic else {
			throw AccessoryError.ioFailed("No FROMRADIO_characteristic ")
		}
		let data: Data = try await withCheckedThrowingContinuation { newReadContinuation in
			readContinuations.append(newReadContinuation)
			peripheral.readValue(for: FROMRADIO_characteristic)
		}
		if data.isEmpty {
			Logger.transport.debug("🛜 [BLE] Received empty data, ending drain operation.")
		}
		return data
	}
	
	func handlePeripheralError(error: Error) async throws {
		/// Explicit retries for a few specific errors where we want to re-connect, all other errors should not reconnect automatically
		var shouldReconnect = false
		switch error {
		case let attError as CBATTError:
			 switch attError.code {
			 default:
				 // All CBATTErrors should not try and reconnect
				 Logger.transport.error("🛜 [BLEConnection] Disconnected with CBATTError code: \(attError.code.rawValue) - \(attError.localizedDescription)")
			 }
		case let cbError as CBError:
			switch cbError.code {
			case .connectionTimeout: // 6
				// Happens when the node goes out of range or the shutdown or reset buttons are presses
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLEConnection] Disconnected with CBError code: \(cbError.code.rawValue) - \(cbError.localizedDescription)")
				shouldReconnect = true
			case .peripheralDisconnected: // 7
				// Happens when the node reboots or shuts down intentionally via the firmware or app
				// Should disconnect, show error, and retry when re-advertised
				Logger.transport.error("🛜 [BLEConnection] Disconnected with CBError code: \(cbError.code.rawValue) - \(cbError.localizedDescription)")
				shouldReconnect = true
			default:
				Logger.transport.error("🛜 [BLEConnection] Disconnected with CBError code: \(cbError.code.rawValue) - \(cbError.localizedDescription)")
			}
		case let otherError:
			Logger.transport.error("🛜 [BLEConnection] Disconnected with non CBError or CBATTError: \(otherError.localizedDescription)")
		}
		
		// Inform the active connection that there was an error and it should disconnect
		try await self.disconnect(withError: error, shouldReconnect: shouldReconnect)
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
