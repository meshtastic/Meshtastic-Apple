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

actor BLEConnection: WirelessConnection {

	var proxy: BLEConnectionProxy
	var isConnected: Bool { proxy.isConnected }

	private var needsDrain: Bool = false
	private var isDraining: Bool = false

	private var fromNumTask: Task <Void, Error>?

	init(peripheral: CBPeripheral, central: CBCentralManager, readyCallback: @escaping (Result<Void, Error>) -> Void) {
		self.proxy = BLEConnectionProxy(peripheral: peripheral,
										central: central, readyCallback: readyCallback)
	}

	func didRecieveFromRadio() async {
		try? startDrainPendingPackets()
	}

	func send(_ data: ToRadio) async throws {
		try await proxy.send(data)
	}

	func disconnect() async throws {
		self.fromNumTask?.cancel()
		try proxy.disconnect()
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
				packetStreamContinuation?.yield(decodedInfo)
			} catch {
				packetStreamContinuation?.finish()
			}
		} while true
	}

	func startDrainPendingPackets() throws {
		guard isConnected else {
			throw AccessoryError.ioFailed("Not connected")
		}
		needsDrain = true
		if !isDraining {
			Task {
				try? await drainPendingPackets()
			}
		}
	}

	private var packetStreamContinuation: AsyncStream<MeshtasticProtobufs.FromRadio>.Continuation?

	func getPacketStream() -> AsyncStream<MeshtasticProtobufs.FromRadio> {
		AsyncStream<MeshtasticProtobufs.FromRadio> { continuation in
			self.packetStreamContinuation = continuation
			continuation.onTermination = { _ in
				Task { try await self.disconnect() }
			}
		}
	}

	func getRadioLogStream() -> AsyncStream<String>? {
		return self.proxy.logRadioMessages()
	}

	func getRSSIStream() async -> AsyncStream<Int> {
		return await self.proxy.getRSSIStream()
	}

	func connect() async -> (AsyncStream<FromRadio>, AsyncStream<String>?) {
		self.fromNumTask = Task {
			for await _ in self.proxy.fromNumNotifications() {
				try? await self.drainPendingPackets()
			}
		}
		return (self.getPacketStream(), self.getRadioLogStream())
	}
}

class BLEConnectionProxy: NSObject, CBPeripheralDelegate {
	private var writeContinuations: [CheckedContinuation<Void, Error>] = []

	fileprivate var TORADIO_characteristic: CBCharacteristic?
	fileprivate var FROMRADIO_characteristic: CBCharacteristic?
	fileprivate var FROMNUM_characteristic: CBCharacteristic?
	fileprivate var LOGRADIO_characteristic: CBCharacteristic?

	private let readyCallback: (Result<Void, Error>) -> Void
	private var logRadioContinuation: AsyncStream<String>.Continuation?
	private var fromNumContinuation: AsyncStream<Data>.Continuation?

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
			Logger.transport.info("✅ [BLE] Service for Meshtastic discovered by \(peripheral.name ?? "Unknown", privacy: .public)")
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
				Logger.transport.info("✅ [BLE] did discover TORADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				TORADIO_characteristic = characteristic

			case FROMRADIO_UUID:
				Logger.transport.info("✅ [BLE] did discover FROMRADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)

			case FROMNUM_UUID:
				Logger.transport.info("✅ [BLE] did discover FROMNUM (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMNUM_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)

			case LOGRADIO_UUID:
				Logger.transport.info("✅ [BLE] did discover LOGRADIO (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				LOGRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)

			default:
				Logger.transport.info("✅ [BLE] did discover unsupported \(characteristic.uuid) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
			}
		}

		if TORADIO_characteristic != nil && FROMRADIO_characteristic != nil && FROMNUM_characteristic != nil {
			Logger.transport.info("✅ [BLE] characteristics ready")
			readyCallback(.success(()))
			// Read initial RSSI on ready
			peripheral.readRSSI()
		} else {
			Logger.transport.info("✅ [BLE] Missing required characteristics")
			readyCallback(.failure(AccessoryError.discoveryFailed("Missing required characteristics")))
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		Logger.transport.info("✅ [BLE] Did update value for \(characteristic.meshtasticCharacteristicName)=\(characteristic.value ?? Data())")
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
			fromNumContinuation?.yield(value)

		case LOGRADIO_UUID:
			do {
				let logRecord = try LogRecord(serializedBytes: characteristic.value!)
				var message = logRecord.source.isEmpty ? logRecord.message : "[\(logRecord.source)] \(logRecord.message)"
				switch logRecord.level {
				case .debug:
					message = "DEBUG | \(message)"
				case .info:
					message = "INFO  | \(message)"
				case .warning:
					message = "WARN  | \(message)"
				case .error:
					message = "ERROR | \(message)"
				case .critical:
					message = "CRIT  | \(message)"
				default:
					message = "DEBUG | \(message)"
				}
				logRadioContinuation?.yield(message)
			} catch {
				// Ignore fail to parse as LogRecord
			}

		default:
			break
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		guard characteristic.uuid == TORADIO_UUID, !writeContinuations.isEmpty else { return }
		let cont = writeContinuations.removeFirst()
		if let error = error {
			Logger.transport.error("[BLE] Did write for \(characteristic.meshtasticCharacteristicName) with error \(error)")
			cont.resume(throwing: error)
		} else {
			Logger.transport.error("[BLE] Did write for \(characteristic.meshtasticCharacteristicName)")
			cont.resume()
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		if let error = error {
			Logger.transport.error("[BLE] Error reading RSSI: \(error.localizedDescription)")
			return
		}
		rssiStreamContinuation?.yield(RSSI.intValue)
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
			Logger.transport.error("[BLE] Received empty data, ending drain operation.")
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
		readContinuation = nil
		rssiStreamContinuation?.finish()
		rssiStreamContinuation = nil
	}

	func logRadioMessages() -> AsyncStream<String> {
		return AsyncStream { continuation in
			self.logRadioContinuation = continuation
			continuation.onTermination = { _ in
				self.logRadioContinuation = nil
			}
		}
	}

	func fromNumNotifications() -> AsyncStream<Data> {
		return AsyncStream { continuation in
			self.fromNumContinuation = continuation
			continuation.onTermination = { _ in
				self.fromNumContinuation = nil
			}
		}
	}

	private var rssiStreamContinuation: AsyncStream<Int>.Continuation?
	func getRSSIStream() async -> AsyncStream<Int> {
		AsyncStream<Int> { continuation in
			self.rssiStreamContinuation = continuation
			continuation.onTermination = { _ in
				Task { try self.disconnect() }
			}
		}
	}
}
