//
//  BLETransportAbandonedConnectTests.swift
//  MeshtasticTests
//
//  Core Bluetooth never gives up on a connect request by itself. When a connect attempt timed
//  out, the request was left pending, so the radio connected to iOS later with nothing in the
//  app waiting for it. iOS showed it connected, the app showed it disconnected, and the radio
//  stopped advertising, so the app couldn't find it.
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
	override var name: String? { "Test Radio" }

	/// What Core Bluetooth would report for this peripheral. The suite runs serially, and each
	/// test that changes it puts it back.
	nonisolated(unsafe) static var reportedState: CBPeripheralState = .disconnected
	override var state: CBPeripheralState { Self.reportedState }

	/// One instance kept for the whole run: this double skips CBPeripheral's initializer, and its
	/// dealloc then removes an observer that was never added and crashes.
	static let shared = make()

	private static func make() -> TestPeripheral {
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
		case connect(UUID)
		case cancelConnection(UUID)
	}

	private(set) var calls: [Call] = []
	private let peripheral: CBPeripheral
	var connectSignal: Signal

	init(peripheral: CBPeripheral, connectSignal: Signal) {
		self.peripheral = peripheral
		self.connectSignal = connectSignal
		super.init(delegate: nil, queue: nil, options: nil)
	}

	var reportedState: CBManagerState = .poweredOn
	override var state: CBManagerState { reportedState }
	override var isScanning: Bool { false }

	override func stopScan() {}

	override func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}

	override func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
		identifiers.contains(peripheral.identifier) ? [peripheral] : []
	}

	override func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {
		calls.append(.connect(peripheral.identifier))
		Task { await connectSignal.markReached() }
	}

	override func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
		calls.append(.cancelConnection(peripheral.identifier))
	}
}

// Serialized because every test uses the one shared peripheral double.
@Suite("BLETransport abandoned connect", .serialized, .timeLimit(.minutes(1)))
struct BLETransportAbandonedConnectTests {
	@Test func cancelledConnectCancelsTheRequestWithCoreBluetooth() async {
		let peripheral = TestPeripheral.shared
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()

		// What the connect step's timeout does when the radio is out of range.
		connection.cancel()
		_ = try? await connection.value

		#expect(centralManager.calls == [
			.connect(peripheral.identifier),
			.cancelConnection(peripheral.identifier)
		])
	}

	@Test func connectionNobodyIsWaitingForIsClosed() async {
		let peripheral = TestPeripheral.shared
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: Signal())
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)

		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)

		#expect(centralManager.calls == [.cancelConnection(peripheral.identifier)])
	}

	@Test func connectionThatIsWaitedForIsKept() async throws {
		let peripheral = TestPeripheral.shared
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()

		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)
		_ = try await connection.value

		#expect(centralManager.calls == [.connect(peripheral.identifier)])
	}

	@Test func anotherDidConnectKeepsTheActiveConnection() async throws {
		let peripheral = TestPeripheral.shared
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()
		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)
		_ = try await connection.value

		// Nothing is waiting for this one, but the link is the one already in use.
		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)

		#expect(centralManager.calls == [.connect(peripheral.identifier)])
	}

	@Test func connectAfterAFailedAttemptGoesThrough() async throws {
		let peripheral = TestPeripheral.shared
		let firstConnect = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: firstConnect)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let failed = Task { try await transport.connect(to: device) }
		await firstConnect.wait()
		failed.cancel()
		_ = try? await failed.value

		// The transport turns new attempts away while one is in progress; that has to end with it.
		let secondConnect = Signal()
		centralManager.connectSignal = secondConnect
		let retry = Task { try await transport.connect(to: device) }
		await secondConnect.wait()
		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)
		_ = try await retry.value

		#expect(centralManager.calls == [
			.connect(peripheral.identifier),
			.cancelConnection(peripheral.identifier),
			.connect(peripheral.identifier)
		])
	}

	@Test func bluetoothTurnedOffDuringConnectSendsNoCancel() async {
		let peripheral = TestPeripheral.shared
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()

		centralManager.reportedState = .poweredOff
		await transport.handleCentralState(.poweredOff, central: centralManager)
		_ = try? await connection.value

		#expect(centralManager.calls == [.connect(peripheral.identifier)])
	}

	@Test func realDisconnectStillFailsAPendingConnect() async {
		let peripheral = TestPeripheral.shared
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()

		// A real drop: the peripheral no longer shows as connecting.
		TestPeripheral.reportedState = .disconnected
		await transport.handlePeripheralDisconnect(peripheral: peripheral)
		// If the disconnect were ignored, this cancel is what would end the connect instead.
		connection.cancel()

		do {
			_ = try await connection.value
			Issue.record("The connect succeeded after the radio disconnected")
		} catch AccessoryError.connectionFailed(let message) {
			#expect(message == "Peripheral disconnected before connection completed")
		} catch {
			Issue.record("The disconnect was ignored; the connect only ended when cancelled: \(error)")
		}
	}

	@Test func disconnectFromAnEarlierCancelDoesNotFailANewConnect() async throws {
		let peripheral = TestPeripheral.shared
		defer { TestPeripheral.reportedState = .disconnected }
		let connectSignal = Signal()
		let centralManager = RecordingCentralManager(peripheral: peripheral, connectSignal: connectSignal)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: centralManager)
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: peripheral.identifier.uuidString)

		let connection = Task { try await transport.connect(to: device) }
		await connectSignal.wait()
		TestPeripheral.reportedState = .connecting

		// The disconnect Core Bluetooth reports for the previous attempt's cancel, arriving late.
		await transport.handlePeripheralDisconnect(peripheral: peripheral)
		await transport.handleDidConnect(peripheral: peripheral, central: centralManager)

		_ = try await connection.value
	}
}
