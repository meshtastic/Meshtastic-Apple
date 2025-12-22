//
//  AsyncCentral.swift
//  Meshtastic
//
//  Created by jake on 12/21/25.
//

import CoreBluetooth
import OSLog

private let meshtasticOTAServiceId = CBUUID(string: "4FAFC201-1FB5-459E-8FCC-C5C9C331914B")
private let statusCharacteristicId = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130003")
private let otaCharacteristicId    = CBUUID(string: "62EC0272-3EC5-11EB-B378-0242AC130005")

enum BLEError: Error {
	case poweredOff, scanTimeout, connectFailed, serviceMissing, characteristicMissing
}

final class AsyncCentral: NSObject {
	private var central: CBCentralManager!
	private var scanContinuation: CheckedContinuation<CBPeripheral, Error>?
	private var connectContinuation: CheckedContinuation<Void, Error>?
	private var serviceContinuation: CheckedContinuation<[CBService], Error>?
	private var characteristicContinuation: CheckedContinuation<[CBCharacteristic], Error>?
	private var notifyContinuation: CheckedContinuation<Void, Error>?
	private var writeContinuation: CheckedContinuation<Void, Error>?
	private var notificationStreams: [CBUUID: AsyncStream<Data>.Continuation] = [:]

	override init() {
		super.init()
		central = CBCentralManager(delegate: self, queue: nil)
	}

	func waitUntilPoweredOn() async throws {
		if central.state == .poweredOn { return }
		try await withCheckedThrowingContinuation { cont in
			self.powerContinuation = cont
		}
	}

	private var powerContinuation: CheckedContinuation<Void, Error>?
}

extension AsyncCentral: CBCentralManagerDelegate, CBPeripheralDelegate {
	func centralManagerDidUpdateState(_ central: CBCentralManager) {
		if central.state == .poweredOn {
			powerContinuation?.resume()
			powerContinuation = nil
		}
	}

	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
						advertisementData: [String : Any], rssi RSSI: NSNumber) {
		scanContinuation?.resume(returning: peripheral)
		scanContinuation = nil
		central.stopScan()
	}

	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		connectContinuation?.resume()
		connectContinuation = nil
	}

	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		connectContinuation?.resume(throwing: error ?? BLEError.connectFailed)
		connectContinuation = nil
	}

	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let error = error { serviceContinuation?.resume(throwing: error) }
		else { serviceContinuation?.resume(returning: peripheral.services ?? []) }
		serviceContinuation = nil
	}

	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		if let error = error { characteristicContinuation?.resume(throwing: error) }
		else { characteristicContinuation?.resume(returning: service.characteristics ?? []) }
		characteristicContinuation = nil
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		if let error = error { notifyContinuation?.resume(throwing: error) }
		else { notifyContinuation?.resume() }
		notifyContinuation = nil
	}

	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		guard error == nil, let data = characteristic.value else { return }
		notificationStreams[characteristic.uuid]?.yield(data)
	}

	func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		if let error = error {
			writeContinuation?.resume(throwing: error)
		} else {
			writeContinuation?.resume()
		}
		writeContinuation = nil
	}
}

extension AsyncCentral {
	func scan(for service: CBUUID, timeout: TimeInterval = 10) async throws -> CBPeripheral {
		try await withThrowingTaskGroup(of: CBPeripheral.self) { group in
			group.addTask {
				try await withCheckedThrowingContinuation { cont in
					self.scanContinuation = cont
					self.central.scanForPeripherals(withServices: [service], options: nil)
				}
			}
			group.addTask {
				try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
				throw BLEError.scanTimeout
			}
			let result = try await group.next()! // first to finish
			group.cancelAll()
			return result
		}
	}

	func connect(_ peripheral: CBPeripheral) async throws {
		try await withCheckedThrowingContinuation { cont in
			self.connectContinuation = cont
			central.connect(peripheral, options: nil)
		}
	}

	func discoverServices(_ uuids: [CBUUID], on peripheral: CBPeripheral) async throws -> [CBService] {
		peripheral.delegate = self
		peripheral.discoverServices(uuids)
		return try await withCheckedThrowingContinuation { cont in
			self.serviceContinuation = cont
		}
	}

	func discoverCharacteristics(_ uuids: [CBUUID], in service: CBService, on peripheral: CBPeripheral) async throws -> [CBCharacteristic] {
		peripheral.discoverCharacteristics(uuids, for: service)
		return try await withCheckedThrowingContinuation { cont in
			self.characteristicContinuation = cont
		}
	}

	func setNotify(_ enabled: Bool, for characteristic: CBCharacteristic, on peripheral: CBPeripheral) async throws {
		peripheral.setNotifyValue(enabled, for: characteristic)
		try await withCheckedThrowingContinuation { cont in
			self.notifyContinuation = cont
		}
	}

	func notifications(for characteristic: CBCharacteristic) -> AsyncStream<Data> {
		AsyncStream { cont in
			notificationStreams[characteristic.uuid] = cont
		}
	}

	func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, on peripheral: CBPeripheral) async throws {
		if type == .withResponse {
			try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
				self.writeContinuation = cont
				peripheral.writeValue(data, for: characteristic, type: type)
			}
		} else {
			peripheral.writeValue(data, for: characteristic, type: type)
		}
	}
}
