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

class BLEConnection: NSObject, WirelessConnection, CBPeripheralDelegate {
	let meshtasticServiceCBUUID = CBUUID(string: "0x6BA1B218-15A8-461F-9FA8-5DCAE273EAFD")

	let peripheral: CBPeripheral
	weak var central: CBCentralManager?

	fileprivate var TORADIO_characteristic: CBCharacteristic?
	fileprivate var FROMRADIO_characteristic: CBCharacteristic?
	fileprivate var FROMNUM_characteristic: CBCharacteristic?
	fileprivate var LOGRADIO_characteristic: CBCharacteristic?

	fileprivate var readContinuation: CheckedContinuation<Data, Error>?
	private var writeContinuations: [CheckedContinuation<Void, Error>] = []

	private let readyCallback: (Result<Void, Error>) -> Void

	weak var rssiDelegate: RSSIDelegate?
	weak var packetDelegate: PacketDelegate?

	var isConnected: Bool { peripheral.state == .connected }

	private var needsDrain: Bool = false
	private var isDraining: Bool = false
	private var drainCompletionContinuations: [CheckedContinuation<Void, Never>] = []

	init(peripheral: CBPeripheral, central: CBCentralManager, readyCallback: @escaping (Result<Void, Error>) -> Void) {
		self.peripheral = peripheral
		self.central = central
		self.readyCallback = readyCallback
		super.init()

		peripheral.delegate = self
		peripheral.discoverServices([meshtasticServiceCBUUID])

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

	func disconnect() async throws {
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
		readContinuation = nil
		if let central = central, peripheral.state == .connected {
			central.cancelPeripheralConnection(peripheral)
		}
		peripheral.delegate = nil
	}

	func drainPendingPackets() async throws {
		guard isConnected else {
			throw AccessoryError.ioFailed("Not connected")
		}
		await withCheckedContinuation { cont in
			drainCompletionContinuations.append(cont)
			needsDrain = true
			if !isDraining {
				Task {
					await performDrain()
				}
			}
		}
	}

	func startDrainPendingPackets() throws {
		guard isConnected else {
			throw AccessoryError.ioFailed("Not connected")
		}
		needsDrain = true
		if !isDraining {
			Task {
				await performDrain()
			}
		}
	}

	private func performDrain() async {
		isDraining = true
		defer {
			isDraining = false
			for cont in drainCompletionContinuations {
				cont.resume()
			}
			drainCompletionContinuations = []
		}

		guard let characteristic = FROMRADIO_characteristic else { return }

		let peripheral = self.peripheral

		while needsDrain {
			needsDrain = false
			repeat {
				do {
					let data = try await withCheckedThrowingContinuation { cont in
						readContinuation = cont
						peripheral.readValue(for: characteristic)
					}
					if data.isEmpty {
						Logger.services.error("[BLE] Received empty data, ending drain operation.")
						break
					}

					do {
						let decodedInfo = try FromRadio(serializedBytes: data)
						packetDelegate?.didReceive(result: .success(decodedInfo))
					} catch {
						Logger.services.error("💥 \(error.localizedDescription, privacy: .public) \(characteristic.value ?? Data(), privacy: .public)")
						packetDelegate?.didReceive(result: .failure(error))
					}

					// Update RSSI when new data comes in
					peripheral.readRSSI()
				} catch {
					packetDelegate?.didReceive(result: .failure(error))
					break
				}
			} while true
		}
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
			Logger.services.info("✅ [BLE] Service for Meshtastic discovered by \(peripheral.name ?? "Unknown", privacy: .public)")
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
				Logger.services.info("✅ [BLE] did discover TORADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				TORADIO_characteristic = characteristic

			case FROMRADIO_UUID:
				Logger.services.info("✅ [BLE] did discover FROMRADIO characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)

			case FROMNUM_UUID:
				Logger.services.info("✅ [BLE] did discover FROMNUM (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				FROMNUM_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)

			case LOGRADIO_UUID:
				Logger.services.info("✅ [BLE] did discover LOGRADIO (Notify) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
				LOGRADIO_characteristic = characteristic
				self.peripheral.setNotifyValue(true, for: characteristic)

			default:
				Logger.services.info("✅ [BLE] did discover unsupported \(characteristic.uuid) characteristic for Meshtastic by \(self.peripheral.name ?? "Unknown", privacy: .public)")
			}
		}

		if TORADIO_characteristic != nil && FROMRADIO_characteristic != nil && FROMNUM_characteristic != nil {
			Logger.services.info("✅ [BLE] characteristics ready")
			readyCallback(.success(()))
			// Read initial RSSI on ready
			peripheral.readRSSI()
		} else {
			Logger.services.info("✅ [BLE] Missing required characteristics")
			readyCallback(.failure(AccessoryError.discoveryFailed("Missing required characteristics")))
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		Logger.services.info("✅ [BLE] Did update value for \(characteristic.meshtasticCharacteristicName)=\(characteristic.value ?? Data())")
		if let error = error {
			if characteristic.uuid == FROMRADIO_UUID {
				readContinuation?.resume(throwing: error)
				readContinuation = nil
			} else {
				packetDelegate?.didReceive(result: .failure(error))
			}
			return
		}
		guard let value = characteristic.value else { return }

		switch characteristic.uuid {
		case FROMRADIO_UUID:
			if let readContinuation {
				readContinuation.resume(returning: value)
				self.readContinuation = nil
			} else {
				do {
					let fromRadio = try FromRadio(serializedBytes: value)
					packetDelegate?.didReceive(result: .success(fromRadio))
				} catch {
					packetDelegate?.didReceive(result: .failure(error))
				}
			}
		case FROMNUM_UUID:
			Task {
				needsDrain = true
				if !isDraining {
					await performDrain()
				}
			}

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
				packetDelegate?.didReceiveLog(message: message)
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
			Logger.services.error("[BLE] Did write for \(characteristic.meshtasticCharacteristicName) with error \(error)")
			cont.resume(throwing: error)
		} else {
			Logger.services.error("[BLE] Did write for \(characteristic.meshtasticCharacteristicName)")
			cont.resume()
		}
	}

	func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
		if let error = error {
			Logger.services.error("Error reading RSSI: \(error.localizedDescription)")
			return
		}
		rssiDelegate?.didUpdateRSSI(RSSI.intValue, for: peripheral.identifier)
	}

}
