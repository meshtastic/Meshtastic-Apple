//
//  BLETransportPeripheralResolutionTests.swift
//  MeshtasticTests
//
//  Regression coverage for #2200: stopping discovery before pairing cleared
//  BLETransport's scan cache, so connect(to:) failed before asking CoreBluetooth
//  to resolve the selected peripheral.
//

@preconcurrency import CoreBluetooth
import Foundation
import ObjectiveC.runtime
import Testing

@testable import Meshtastic

private actor Signal {
	private var reached = false
	private var continuation: CheckedContinuation<Void, Never>?

	func markReached() {
		reached = true
		continuation?.resume()
		continuation = nil
	}

	func wait() async {
		guard !reached else { return }
		await withCheckedContinuation { continuation in
			self.continuation = continuation
		}
	}
}

private final class TestPeripheral: CBPeripheral, @unchecked Sendable {
	static let testIdentifier = UUID()

	override var identifier: UUID { Self.testIdentifier }

	static func make() -> TestPeripheral {
		// CBPeripheral has no public initializer, so this test-only double has no CoreBluetooth state.
		guard let peripheral = class_createInstance(TestPeripheral.self, 0) else {
			fatalError("Unable to allocate test peripheral")
		}
		guard let testPeripheral = peripheral as? TestPeripheral else {
			fatalError("Test peripheral has an unexpected type")
		}
		return testPeripheral
	}
}

private final class RecordingCentralManager: CBCentralManager, @unchecked Sendable {
	enum Call: Equatable {
		case stopScan
		case retrievePeripherals([UUID])
		case startScan
		case connect(UUID)
	}

	private(set) var calls: [Call] = []
	private var scanning: Bool
	private let peripheral: CBPeripheral?
	private let connectSignal: Signal?

	init(scanning: Bool = true, peripheral: CBPeripheral? = nil, connectSignal: Signal? = nil) {
		self.scanning = scanning
		self.peripheral = peripheral
		self.connectSignal = connectSignal
		super.init(delegate: nil, queue: nil, options: nil)
	}

	override var state: CBManagerState { .poweredOn }
	override var isScanning: Bool { scanning }

	override func stopScan() {
		scanning = false
		calls.append(.stopScan)
	}

	override func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
		calls.append(.retrievePeripherals(identifiers))
		guard let peripheral, identifiers.contains(peripheral.identifier) else { return [] }
		return [peripheral]
	}

	override func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {
		calls.append(.connect(peripheral.identifier))
		Task { await connectSignal?.markReached() }
	}

	override func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {
		scanning = true
		calls.append(.startScan)
	}
}

@Suite("BLETransport peripheral resolution", .timeLimit(.minutes(1)))
struct BLETransportPeripheralResolutionTests {
	@Test func pairingPausePreservesResolutionWithoutRestartingAbsentDiscovery() async {
		let centralManager = RecordingCentralManager()
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			centralManager: centralManager
		)
		let peripheralID = UUID()
		let device = Device(
			id: UUID(),
			name: "Test Radio",
			transportType: .ble,
			identifier: peripheralID.uuidString
		)

		do {
			_ = try await transport.connect(to: device)
			Issue.record("connect(to:) must fail when CoreBluetooth cannot resolve the peripheral")
		} catch AccessoryError.connectionFailed(let message) {
			#expect(message == "Peripheral not found")
		} catch {
			Issue.record("Expected AccessoryError.connectionFailed, got \(error)")
		}

		#expect(
			centralManager.calls == [
				.stopScan,
				.retrievePeripherals([peripheralID])
			],
			"Pairing must pause scanning and resolve the selected peripheral without starting an unsubscribed discovery scan"
		)
	}

	@Test func discoveryStartedDuringConnectionPauseWaitsUntilFailure() async {
		let centralManager = RecordingCentralManager(scanning: false)
		let discoverySetupSignal = Signal()
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			centralManager: centralManager,
			discoverySetupHandler: { await discoverySetupSignal.markReached() }
		)

		await transport.handleCentralState(.poweredOn, central: centralManager)
		await transport.pauseScanningForConnection()

		let discovery = await transport.discoverDevices()
		await discoverySetupSignal.wait()

		#expect(
			centralManager.calls.isEmpty,
			"A retry discovery stream must not start scanning while the connection pause is active"
		)

		await transport.connectionDidDisconnect(fromPeripheral: nil)

		#expect(
			centralManager.calls == [.startScan],
			"A failed connection must resume the waiting discovery subscriber exactly once"
		)
		withExtendedLifetime(discovery) {}
	}

	@Test func lateCancellationCleanupAfterConnectKeepsTransportBusy() async throws {
		let peripheral = TestPeripheral.make()
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			centralManager: centralManager
		)
		let device = Device(
			id: UUID(),
			name: "Test Radio",
			transportType: .ble,
			identifier: peripheral.identifier.uuidString
		)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()
		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)
		_ = try await connection.value

		await transport.cancelConnectContinuation(for: peripheral)

		do {
			_ = try await transport.connect(to: device)
			Issue.record("A late cancellation cleanup must not clear the active connection")
		} catch AccessoryError.connectionFailed(let message) {
			#expect(message == "BLE transport is busy: already connecting or connected")
		}
	}
}
