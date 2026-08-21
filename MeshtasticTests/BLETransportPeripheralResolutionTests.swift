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
	private func letActorTasksRun() async throws {
		try await Task.sleep(for: .milliseconds(50))
	}

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

	@Test func discoveryStartedDuringConnectionPauseWaitsUntilFailure() async throws {
		let centralManager = RecordingCentralManager(scanning: false)
		let transport = BLETransport(
			createCentralManagerImmediately: false,
			centralManager: centralManager
		)

		await transport.handleCentralState(.poweredOn, central: centralManager)
		try await letActorTasksRun()
		await transport.pauseScanningForConnection()

		let discovery = await transport.discoverDevices()
		try await letActorTasksRun()

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
