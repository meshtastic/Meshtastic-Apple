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
import Testing

@testable import Meshtastic

private actor DiscoverySetupSignal {
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

private final class RecordingCentralManager: CBCentralManager, @unchecked Sendable {
	enum Call: Equatable {
		case stopScan
		case retrievePeripherals([UUID])
		case startScan
	}

	private(set) var calls: [Call] = []
	private var scanning: Bool

	init(scanning: Bool = true) {
		self.scanning = scanning
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
		return []
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
		let discoverySetupSignal = DiscoverySetupSignal()
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
}
