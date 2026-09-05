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

enum BLEError: Error, LocalizedError {
	case poweredOff, scanTimeout, connectFailed, connectTimeout, serviceMissing, characteristicMissing
	case discoveryTimeout, notifyTimeout, writeTimeout, disconnected

	var errorDescription: String? {
		switch self {
		case .poweredOff:
			return String(localized: "Bluetooth is not available.", comment: "OTA failed because Bluetooth is off or not permitted")
		case .scanTimeout:
			return String(localized: "The device never advertised in update mode.", comment: "OTA failed because the device never appeared in update mode")
		case .connectFailed:
			return String(localized: "Could not connect to the device.", comment: "OTA failed to connect to the device in update mode")
		case .connectTimeout:
			return String(localized: "Timed out connecting to the device.", comment: "OTA connection to the device in update mode timed out")
		case .serviceMissing:
			return String(localized: "The device is not offering the update service.", comment: "OTA failed because the device is missing the update service")
		case .characteristicMissing:
			return String(localized: "The update service is missing a characteristic.", comment: "OTA failed because the update service is incomplete")
		case .discoveryTimeout:
			return String(localized: "Timed out reading the device's update service.", comment: "OTA timed out discovering the update service")
		case .notifyTimeout:
			return String(localized: "The device never confirmed the status channel.", comment: "OTA timed out enabling status notifications")
		case .writeTimeout:
			return String(localized: "Timed out writing to the device.", comment: "OTA timed out writing to the device")
		case .disconnected:
			return String(localized: "The device disconnected.", comment: "OTA failed because the device disconnected")
		}
	}
}

/// Core Bluetooth callbacks can simply never arrive: the radio reboots, the OTA
/// advertisement never shows up, the connection drops between two delegate calls.
/// Every wait in here therefore carries its own deadline. Racing the wait against a
/// sleeping task is not enough — a checked continuation ignores cancellation, so the
/// only thing that can end a wait is resuming the continuation the delegate would
/// have resumed. That is what the `fail…` helpers below do.
@MainActor
final class AsyncCentral: NSObject {
	private var central: CBCentralManager!
	private var scanContinuation: CheckedContinuation<CBPeripheral, Error>?
	private var connectContinuation: CheckedContinuation<Void, Error>?
	private var serviceContinuation: CheckedContinuation<[CBService], Error>?
	private var characteristicContinuation: CheckedContinuation<[CBCharacteristic], Error>?
	private var notifyContinuation: CheckedContinuation<Void, Error>?
	private var writeContinuation: CheckedContinuation<Void, Error>?
	private var notificationStreams: [CBUUID: AsyncStream<Data>.Continuation] = [:]
	private var desiredUUID: UUID?
	/// The peripheral `connect` is waiting on, so a callback for a stale attempt to a
	/// different device cannot answer the current wait.
	private var connectingPeripheral: CBPeripheral?

	override init() {
		super.init()
		central = CBCentralManager(delegate: self, queue: nil)
	}

	func waitUntilPoweredOn(timeout: TimeInterval = 10) async throws {
		if central.state == .poweredOn { return }
		// A state that is already terminal produces no further callback, so waiting out the
		// deadline only delays the same answer.
		if [.poweredOff, .unauthorized, .unsupported].contains(central.state) {
			throw BLEError.poweredOff
		}
		try await withDeadline(timeout, onExpiry: { self.finishPower(with: .failure(BLEError.poweredOff)) }) {
			try await withCheckedThrowingContinuation { cont in
				self.powerContinuation = cont
			}
		}
	}

	private var powerContinuation: CheckedContinuation<Void, Error>?

	// MARK: - Waiting

	/// Runs `body`, and if it has not finished within `seconds`, calls `onExpiry` —
	/// which is expected to resume whatever continuation `body` is waiting on.
	private func withDeadline<T>(
		_ seconds: TimeInterval,
		onExpiry: @escaping @MainActor () -> Void,
		body: () async throws -> T
	) async throws -> T {
		let timer = Task { @MainActor in
			try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
			guard !Task.isCancelled else { return }
			onExpiry()
		}
		defer { timer.cancel() }
		return try await body()
	}

	// Each of these resumes at most once and clears the slot, so a delegate callback
	// arriving after a deadline has already fired is a no-op instead of a crash.

	private func finishPower(with result: Result<Void, Error>) {
		guard let cont = powerContinuation else { return }
		powerContinuation = nil
		cont.resume(with: result)
	}

	private func finishScan(with result: Result<CBPeripheral, Error>) {
		guard let cont = scanContinuation else { return }
		scanContinuation = nil
		central.stopScan()
		cont.resume(with: result)
	}

	private func finishConnect(with result: Result<Void, Error>) {
		guard let cont = connectContinuation else { return }
		connectContinuation = nil
		connectingPeripheral = nil
		cont.resume(with: result)
	}

	private func finishServices(with result: Result<[CBService], Error>) {
		guard let cont = serviceContinuation else { return }
		serviceContinuation = nil
		cont.resume(with: result)
	}

	private func finishCharacteristics(with result: Result<[CBCharacteristic], Error>) {
		guard let cont = characteristicContinuation else { return }
		characteristicContinuation = nil
		cont.resume(with: result)
	}

	private func finishNotify(with result: Result<Void, Error>) {
		guard let cont = notifyContinuation else { return }
		notifyContinuation = nil
		cont.resume(with: result)
	}

	private func finishWrite(with result: Result<Void, Error>) {
		guard let cont = writeContinuation else { return }
		writeContinuation = nil
		cont.resume(with: result)
	}

	/// A drop ends every wait, not just the one the disconnect interrupted.
	private func failAll(with error: Error) {
		finishConnect(with: .failure(error))
		finishServices(with: .failure(error))
		finishCharacteristics(with: .failure(error))
		finishNotify(with: .failure(error))
		finishWrite(with: .failure(error))
	}
}

extension AsyncCentral: CBCentralManagerDelegate, CBPeripheralDelegate {
	nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
		MainActor.assumeIsolated {
			switch central.state {
			case .poweredOn:
				finishPower(with: .success(()))
			case .poweredOff, .unauthorized, .unsupported:
				// Nothing is coming. Waiting on the radio forever leaves the update
				// screen with no way to end itself.
				Logger.services.error("📡 [ESP32 BLE OTA] Bluetooth unavailable: \(String(describing: central.state), privacy: .public)")
				finishPower(with: .failure(BLEError.poweredOff))
				failAll(with: BLEError.poweredOff)
				finishScan(with: .failure(BLEError.poweredOff))
			default:
				break
			}
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
	                                advertisementData: [String: Any], rssi RSSI: NSNumber) {
		MainActor.assumeIsolated {
			finishScan(with: .success(peripheral))
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		MainActor.assumeIsolated {
			guard peripheral.identifier == connectingPeripheral?.identifier else { return }
			finishConnect(with: .success(()))
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		MainActor.assumeIsolated {
			guard peripheral.identifier == connectingPeripheral?.identifier else { return }
			finishConnect(with: .failure(error ?? BLEError.connectFailed))
		}
	}

	nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		MainActor.assumeIsolated {
			Logger.services.info("📡 [ESP32 BLE OTA] Peripheral disconnected")
			failAll(with: error ?? BLEError.disconnected)
			for stream in notificationStreams.values { stream.finish() }
			notificationStreams.removeAll()
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		MainActor.assumeIsolated {
			if let error {
				finishServices(with: .failure(error))
			} else if let desiredUUID, peripheral.identifier != desiredUUID {
				return
			} else {
				finishServices(with: .success(peripheral.services ?? []))
			}
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		MainActor.assumeIsolated {
			if let error {
				finishCharacteristics(with: .failure(error))
			} else {
				finishCharacteristics(with: .success(service.characteristics ?? []))
			}
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		MainActor.assumeIsolated {
			finishNotify(with: error.map { .failure($0) } ?? .success(()))
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		MainActor.assumeIsolated {
			guard error == nil, let data = characteristic.value else { return }
			notificationStreams[characteristic.uuid]?.yield(data)
		}
	}

	nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
		MainActor.assumeIsolated {
			finishWrite(with: error.map { .failure($0) } ?? .success(()))
		}
	}
}

extension AsyncCentral {
	func scan(for service: CBUUID, desiredUUID: UUID? = nil, timeout: TimeInterval = 10) async throws -> CBPeripheral {
		self.desiredUUID = desiredUUID
		return try await withDeadline(timeout, onExpiry: { self.finishScan(with: .failure(BLEError.scanTimeout)) }) {
			try await withCheckedThrowingContinuation { cont in
				self.scanContinuation = cont
				self.central.scanForPeripherals(withServices: [service], options: nil)
			}
		}
	}

	func connect(_ peripheral: CBPeripheral, timeout: TimeInterval = 10) async throws {
		// Give up on the connection as well as the wait. Core Bluetooth keeps trying
		// indefinitely otherwise, and a late didConnect would resume whatever wait is
		// current by then.
		let expire = { [weak self] in
			guard let self else { return }
			self.central.cancelPeripheralConnection(peripheral)
			self.finishConnect(with: .failure(BLEError.connectTimeout))
		}
		try await withDeadline(timeout, onExpiry: expire) {
			try await withCheckedThrowingContinuation { cont in
				self.connectContinuation = cont
				self.connectingPeripheral = peripheral
				central.connect(peripheral, options: nil)
			}
		}
	}

	func disconnect(_ peripheral: CBPeripheral) {
		central.cancelPeripheralConnection(peripheral)
	}

	func discoverServices(_ uuids: [CBUUID], on peripheral: CBPeripheral, timeout: TimeInterval = 10) async throws -> [CBService] {
		peripheral.delegate = self
		return try await withDeadline(timeout, onExpiry: { self.finishServices(with: .failure(BLEError.discoveryTimeout)) }) {
			try await withCheckedThrowingContinuation { cont in
				self.serviceContinuation = cont
				peripheral.discoverServices(uuids)
			}
		}
	}

	func discoverCharacteristics(_ uuids: [CBUUID], in service: CBService, on peripheral: CBPeripheral, timeout: TimeInterval = 10) async throws -> [CBCharacteristic] {
		try await withDeadline(timeout, onExpiry: { self.finishCharacteristics(with: .failure(BLEError.discoveryTimeout)) }) {
			try await withCheckedThrowingContinuation { cont in
				self.characteristicContinuation = cont
				peripheral.discoverCharacteristics(uuids, for: service)
			}
		}
	}

	func setNotify(_ enabled: Bool, for characteristic: CBCharacteristic, on peripheral: CBPeripheral, timeout: TimeInterval = 5) async throws {
		try await withDeadline(timeout, onExpiry: { self.finishNotify(with: .failure(BLEError.notifyTimeout)) }) {
			try await withCheckedThrowingContinuation { cont in
				self.notifyContinuation = cont
				peripheral.setNotifyValue(enabled, for: characteristic)
			}
		}
	}

	func notifications(for characteristic: CBCharacteristic) -> AsyncStream<Data> {
		AsyncStream { cont in
			notificationStreams[characteristic.uuid] = cont
		}
	}

	func writeValue(_ data: Data, for characteristic: CBCharacteristic, type: CBCharacteristicWriteType, on peripheral: CBPeripheral, timeout: TimeInterval = 10) async throws {
		guard type == .withResponse else {
			peripheral.writeValue(data, for: characteristic, type: type)
			return
		}
		try await withDeadline(timeout, onExpiry: { self.finishWrite(with: .failure(BLEError.writeTimeout)) }) {
			try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
				self.writeContinuation = cont
				peripheral.writeValue(data, for: characteristic, type: type)
			}
		}
	}
}
