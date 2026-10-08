//
//  MultiRadioTransportTests.swift
//  MeshtasticTests
//
//  Feature 021: BLETransport keeps one connection per peripheral, so several radios can be
//  connected at once, and AccessoryManager keeps an additional radio's events away from the
//  first radio.
//

@preconcurrency import CoreBluetooth
import Foundation
import MeshtasticProtobufs
import ObjectiveC.runtime
import SwiftData
import Testing

@testable import Meshtastic

// MARK: - Doubles

private actor Reached {
	private var count = 0
	private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

	func mark() {
		count += 1
		let ready = waiters.filter { $0.0 <= count }
		waiters.removeAll { $0.0 <= count }
		ready.forEach { $0.1.resume() }
	}

	func wait(for target: Int) async {
		guard count < target else { return }
		await withCheckedContinuation { waiters.append((target, $0)) }
	}
}

private class FakePeripheral: CBPeripheral, @unchecked Sendable {
	class var fakeIdentifier: UUID { UUID() }
	override var identifier: UUID { Self.fakeIdentifier }

	static func make() -> Self {
		// CBPeripheral has no public initializer; this double carries no CoreBluetooth state.
		guard let instance = class_createInstance(self, 0) as? Self else {
			fatalError("Unable to allocate a fake peripheral")
		}
		return instance
	}
}

private final class PeripheralA: FakePeripheral, @unchecked Sendable {
	static let id = UUID()
	override static var fakeIdentifier: UUID { id }
}

private final class PeripheralB: FakePeripheral, @unchecked Sendable {
	static let id = UUID()
	override static var fakeIdentifier: UUID { id }
}

private final class TwoPeripheralCentral: CBCentralManager, @unchecked Sendable {
	private let peripherals: [CBPeripheral]
	private let connects: Reached

	init(peripherals: [CBPeripheral], connects: Reached) {
		self.peripherals = peripherals
		self.connects = connects
		super.init(delegate: nil, queue: nil, options: nil)
	}

	override var state: CBManagerState { .poweredOn }
	override var isScanning: Bool { false }
	override func stopScan() {}
	override func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}

	override func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
		peripherals.filter { identifiers.contains($0.identifier) }
	}

	override func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {
		Task { await connects.mark() }
	}
}

/// A radio iOS restored still connected (T062).
private final class RestoredPeripheralC: FakePeripheral, @unchecked Sendable {
	static let id = UUID()
	override static var fakeIdentifier: UUID { id }
	override var state: CBPeripheralState { .connected }
	override var name: String? { "C" }
}

private final class RestoredPeripheralD: FakePeripheral, @unchecked Sendable {
	static let id = UUID()
	override static var fakeIdentifier: UUID { id }
	override var state: CBPeripheralState { .connected }
	override var name: String? { "D" }
}

/// Records which peripherals had their link cancelled.
private final class CancelRecordingCentral: CBCentralManager, @unchecked Sendable {
	private let peripherals: [CBPeripheral]
	private let connects: Reached
	private let lock = NSLock()
	private var cancelledIds: [UUID] = []

	init(peripherals: [CBPeripheral], connects: Reached) {
		self.peripherals = peripherals
		self.connects = connects
		super.init(delegate: nil, queue: nil, options: nil)
	}

	var cancelled: [UUID] { lock.withLock { cancelledIds } }

	override var state: CBManagerState { .poweredOn }
	override var isScanning: Bool { false }
	override func stopScan() {}
	override func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]? = nil) {}
	override func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] {
		peripherals.filter { identifiers.contains($0.identifier) }
	}
	override func connect(_ peripheral: CBPeripheral, options: [String: Any]? = nil) {
		Task { await connects.mark() }
	}
	override func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
		lock.withLock { cancelledIds.append(peripheral.identifier) }
	}
}

private func device(for peripheral: CBPeripheral, name: String) -> Device {
	Device(id: peripheral.identifier, name: name, transportType: .ble, identifier: peripheral.identifier.uuidString)
}

// MARK: - BLE transport

@Suite("Multi-radio BLE transport", .timeLimit(.minutes(1)))
struct MultiRadioBLETransportTests {

	@Test("Two radios can be connecting and connected at the same time")
	func twoPeripheralsConnect() async throws {
		let peripheralA = PeripheralA.make()
		let peripheralB = PeripheralB.make()
		let connects = Reached()
		let central = TwoPeripheralCentral(peripherals: [peripheralA, peripheralB], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)

		let first = Task { try await transport.connect(to: device(for: peripheralA, name: "A")) }
		let second = Task { try await transport.connect(to: device(for: peripheralB, name: "B")) }
		await connects.wait(for: 2)

		// Out of order on purpose: each didConnect must reach its own caller.
		await transport.handleDidConnect(peripheral: peripheralB, central: central)
		await transport.handleDidConnect(peripheral: peripheralA, central: central)

		let connectionA = try #require(try await first.value as? BLEConnection)
		let connectionB = try #require(try await second.value as? BLEConnection)
		#expect(await connectionA.peripheral.identifier == PeripheralA.id)
		#expect(await connectionB.peripheral.identifier == PeripheralB.id)
	}

	@Test("The same radio can't connect twice")
	func samePeripheralIsBusy() async throws {
		let peripheralA = PeripheralA.make()
		let connects = Reached()
		let central = TwoPeripheralCentral(peripherals: [peripheralA], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)
		let radio = device(for: peripheralA, name: "A")

		let first = Task { try await transport.connect(to: radio) }
		await connects.wait(for: 1)
		await transport.handleDidConnect(peripheral: peripheralA, central: central)
		_ = try await first.value

		await #expect(throws: AccessoryError.self) {
			_ = try await transport.connect(to: radio)
		}
	}

	@Test("One radio disconnecting leaves the other connected")
	func disconnectIsPerPeripheral() async throws {
		let peripheralA = PeripheralA.make()
		let peripheralB = PeripheralB.make()
		let connects = Reached()
		let central = TwoPeripheralCentral(peripherals: [peripheralA, peripheralB], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)
		let radioA = device(for: peripheralA, name: "A")
		let radioB = device(for: peripheralB, name: "B")

		let first = Task { try await transport.connect(to: radioA) }
		let second = Task { try await transport.connect(to: radioB) }
		await connects.wait(for: 2)
		await transport.handleDidConnect(peripheral: peripheralA, central: central)
		await transport.handleDidConnect(peripheral: peripheralB, central: central)
		_ = try await first.value
		_ = try await second.value

		await transport.connectionDidDisconnect(fromPeripheral: peripheralA)

		// B is still connected, so connecting it again is refused...
		await #expect(throws: AccessoryError.self) {
			_ = try await transport.connect(to: radioB)
		}
		// ...while A can connect again.
		let again = Task { try await transport.connect(to: radioA) }
		await connects.wait(for: 3)
		await transport.handleDidConnect(peripheral: peripheralA, central: central)
		_ = try await again.value
	}
}

// MARK: - BLE restoration (T062)

private final class TakeoverRecord<Value>: @unchecked Sendable {
	private let lock = NSLock()
	private var value: Value
	init(_ value: Value) { self.value = value }
	func set(_ newValue: Value) { lock.withLock { value = newValue } }
	func get() -> Value { lock.withLock { value } }
}

private struct IdentifiedPeripheral: RestoredPeripheral {
	let identifier: UUID
	var state: CBPeripheralState = .connecting
}

@Suite("Multi-radio BLE restoration", .timeLimit(.minutes(1)))
struct MultiRadioBLERestorationTests {

	@Test("The preferred radio is restored as the first radio, or else the first one restored")
	func firstPeripheralChoice() {
		let first = IdentifiedPeripheral(identifier: UUID())
		let preferred = IdentifiedPeripheral(identifier: UUID())
		let restored = [first, preferred]
		#expect(BLETransport.firstPeripheral(among: restored, preferredId: preferred.identifier.uuidString)?.identifier == preferred.identifier)
		#expect(BLETransport.firstPeripheral(among: restored, preferredId: UUID().uuidString)?.identifier == first.identifier)
		#expect(BLETransport.firstPeripheral(among: [IdentifiedPeripheral](), preferredId: "") == nil)
	}

	@Test("A radio restored still connected is the first one over a preferred radio still connecting")
	func connectedRadioIsRestoredAsFirst() {
		let preferred = IdentifiedPeripheral(identifier: UUID(), state: .connecting)
		let connected = IdentifiedPeripheral(identifier: UUID(), state: .connected)
		let alsoConnected = IdentifiedPeripheral(identifier: UUID(), state: .connected)
		#expect(BLETransport.firstPeripheral(among: [preferred, connected], preferredId: preferred.identifier.uuidString)?.identifier == connected.identifier)
		#expect(BLETransport.firstPeripheral(among: [connected, alsoConnected], preferredId: alsoConnected.identifier.uuidString)?.identifier == alsoConnected.identifier)
	}

	@Test("A standby radio that connects while the first radio's restore still waits takes over the restore")
	func standbyConnectingFirstTakesOver() async throws {
		let peripheralA = PeripheralA.make()
		let peripheralB = PeripheralB.make()
		let connects = Reached()
		let central = TwoPeripheralCentral(peripherals: [peripheralA, peripheralB], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)
		let tookOver = Reached()
		let takenOverId = TakeoverRecord<UUID?>(nil)
		await transport.setRestoreTakeover { peripheral, _ in
			takenOverId.set(peripheral.identifier)
			await tookOver.mark()
		}
		await transport.holdRestoredPeripherals([peripheralB], gracePeriod: .seconds(60))

		let restore = Task { try await transport.waitForRestoredConnect(of: peripheralA) }
		await connects.wait(for: 1)
		await transport.handleDidConnect(peripheral: peripheralB, central: central)

		await #expect(throws: BLETransport.RestoreHandedOver.self) { try await restore.value }
		await tookOver.wait(for: 1)
		#expect(takenOverId.get() == PeripheralB.id)
	}

	@Test("Another radio's connect finishing doesn't end the wait of the first radio's restore")
	func restoreWaitIsPerPeripheral() async throws {
		let peripheralA = PeripheralA.make()
		let peripheralB = PeripheralB.make()
		let connects = Reached()
		let central = TwoPeripheralCentral(peripherals: [peripheralA, peripheralB], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)
		let finished = Reached()

		let restore = Task {
			try await transport.waitForRestoredConnect(of: peripheralA)
			await finished.mark()
		}
		await connects.wait(for: 1)
		let other = Task { try await transport.connect(to: device(for: peripheralB, name: "B")) }
		await connects.wait(for: 2)

		await transport.handleDidConnect(peripheral: peripheralB, central: central)
		let connectionB = try #require(try await other.value as? BLEConnection)
		#expect(await connectionB.peripheral.identifier == PeripheralB.id, "B's didConnect reaches B's connect")

		await transport.handleDidConnect(peripheral: peripheralA, central: central)
		try await restore.value
		await finished.wait(for: 1)
	}

	@Test("A radio restored still connected is taken over without connecting again")
	func connectedRestoredRadioIsTakenOver() async throws {
		let restored = RestoredPeripheralC.make()
		let connects = Reached()
		let central = CancelRecordingCentral(peripherals: [restored], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)
		await transport.holdRestoredPeripherals([restored], gracePeriod: .seconds(60))

		let connection = try #require(try await transport.connect(to: device(for: restored, name: "C")) as? BLEConnection)
		#expect(await connection.peripheral.identifier == RestoredPeripheralC.id)
		#expect(await connection.isKeptByRestore, "its connect asks only for the config (#2584)")
		// Claimed once: a second connect is the ordinary busy case.
		await #expect(throws: AccessoryError.self) {
			_ = try await transport.connect(to: device(for: restored, name: "C"))
		}
		await transport.releaseUnclaimedRestoredPeripherals()
		#expect(central.cancelled.isEmpty, "a claimed radio keeps its link")
	}

	@Test("A restored radio nobody claims is released")
	func unclaimedRestoredRadioIsReleased() async throws {
		let claimed = RestoredPeripheralC.make()
		let unclaimed = RestoredPeripheralD.make()
		let connects = Reached()
		let central = CancelRecordingCentral(peripherals: [claimed, unclaimed], connects: connects)
		let transport = BLETransport(createCentralManagerImmediately: false, centralManager: central)
		await transport.holdRestoredPeripherals([claimed, unclaimed], gracePeriod: .milliseconds(50))
		_ = try await transport.connect(to: device(for: claimed, name: "C"))

		try await Task.sleep(for: .milliseconds(300))
		#expect(central.cancelled == [RestoredPeripheralD.id])
	}
}

// MARK: - Session routing

private actor RecordingConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true
	private(set) var sent: [ToRadio] = []
	private(set) var disconnects = 0

	func send(_ data: ToRadio) async throws { sent.append(data) }
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		isConnected = false
		disconnects += 1
	}
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Multi-radio sessions", .serialized)
struct MultiRadioSessionTests {

	private func makeSession(name: String, num: Int64?) -> (RadioSession, RecordingConnection) {
		let connection = RecordingConnection()
		let device = Device(id: UUID(), name: name, transportType: .ble, identifier: name, connectionState: .connected, num: num)
		return (RadioSession(device: device, connection: connection), connection)
	}

	private struct Fixture {
		let manager: AccessoryManager
		let first: RadioSession
		let firstConnection: RecordingConnection
	}

	private func makeManager() -> Fixture {
		let (first, connection) = makeSession(name: "First", num: 0x0000_0A0A)
		let manager = AccessoryManager(transports: [])
		manager.activeConnection = first
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.updateState(.subscribed)
		return Fixture(manager: manager, first: first, firstConnection: connection)
	}

	private func addRadio(to manager: AccessoryManager, num: Int64? = 0x0000_0B0B) -> (RadioSession, RecordingConnection) {
		let (session, connection) = makeSession(name: "Extra", num: num)
		let radio = session
		manager.additionalRadios[session.device.id] = radio
		return (radio, connection)
	}

	@Test("An additional radio's error disconnects only that radio")
	func errorStaysWithItsRadio() async {
		let fixture = makeManager()
		let manager = fixture.manager, first = fixture.first, firstConnection = fixture.firstConnection
		let (radio, extraConnection) = addRadio(to: manager)

		await manager.didReceive(.error(AccessoryError.disconnected("lost")), from: radio)

		#expect(manager.activeConnection === first)
		#expect(manager.additionalRadios.isEmpty)
		#expect(await extraConnection.disconnects == 1)
		#expect(await firstConnection.disconnects == 0)
	}

	@Test("Late events from a disconnected additional radio are dropped")
	func retiredSessionIsIgnored() async {
		let fixture = makeManager()
		let manager = fixture.manager, first = fixture.first, firstConnection = fixture.firstConnection
		let (radio, _) = addRadio(to: manager)
		await manager.disconnectAdditionalRadio(radio.device.id)

		await manager.didReceive(.disconnected(shouldReconnect: false), from: radio)
		await manager.didReceive(.rssiUpdate(-30), from: radio)

		#expect(manager.activeConnection === first)
		#expect(await firstConnection.disconnects == 0)
		#expect(first.device.rssi != -30)
	}

	@Test("Another radio's config completion leaves the first radio's refresh stamp alone")
	func configCompleteGoesToTheAdditionalRadio() async {
		let manager = makeManager().manager
		let (radio, _) = addRadio(to: manager)
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .configCompleteID(12_345)

		await manager.didReceive(.data(fromRadio), from: radio)

		// The first radio's config-complete bookkeeping is untouched.
		#expect(manager.lastConfigRefresh == nil)
	}

	@Test("An additional radio's MyInfo leaves the preferred radio alone")
	func myInfoDoesNotChangeThePreferredRadio() async {
		let previous = UserDefaults.preferredPeripheralNum
		UserDefaults.preferredPeripheralNum = 0x0000_0A0A
		defer { UserDefaults.preferredPeripheralNum = previous }
		let manager = makeManager().manager
		let (radio, _) = addRadio(to: manager, num: nil)
		var myInfo = MyNodeInfo()
		myInfo.myNodeNum = 0x0000_0C0C
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .myInfo(myInfo)

		await manager.didReceive(.data(fromRadio), from: radio)

		#expect(radio.nodeNum == 0x0000_0C0C)
		#expect(UserDefaults.preferredPeripheralNum == 0x0000_0A0A)
		#expect(manager.activeDeviceNum == nil || manager.activeDeviceNum == 0x0000_0A0A)

		await MeshPackets.shared.flushDebouncedSaves()
		let context = ModelContext(PersistenceController.shared.container)
		let written: Int64 = 0x0000_0C0C
		for row in (try? context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == written }))) ?? [] {
			context.delete(row)
		}
		try? context.save()
	}

	@Test("A radio reporting the first radio's number is dropped")
	func duplicateOfFirstIsDisconnected() async {
		let fixture = makeManager()
		let manager = fixture.manager, first = fixture.first
		let (radio, _) = addRadio(to: manager, num: nil)
		var myInfo = MyNodeInfo()
		myInfo.myNodeNum = 0x0000_0A0A
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = .myInfo(myInfo)

		await manager.didReceive(.data(fromRadio), from: radio)

		#expect(manager.additionalRadios.isEmpty)
		#expect(manager.activeConnection === first)
	}

	@Test("A dropped additional radio is reconnected; one the user disconnects is not")
	func reconnectRules() async {
		let manager = makeManager().manager
		let (dropped, _) = addRadio(to: manager, num: 1)
		let (refused, _) = addRadio(to: manager, num: 2)
		let (closed, _) = addRadio(to: manager, num: 3)

		await manager.didReceive(.error(AccessoryError.disconnected("lost")), from: dropped)
		await manager.didReceive(.errorWithoutReconnect(AccessoryError.bondLost), from: refused)
		await manager.didReceive(.disconnected(shouldReconnect: false), from: closed)

		#expect(Set(manager.additionalRadioReconnects.keys) == [dropped.device.id])

		await manager.disconnectAdditionalRadio(dropped.device.id, byUser: true)
		#expect(manager.additionalRadioReconnects.isEmpty)
	}

	@Test("At most four radios are connected at once")
	func capOfFour() {
		let manager = makeManager().manager
		#expect(manager.connectedRadioCount == 1)
		for num in 1...3 {
			#expect(manager.canConnectAnotherRadio)
			_ = addRadio(to: manager, num: Int64(num))
		}
		#expect(manager.connectedRadioCount == 4)
		#expect(!manager.canConnectAnotherRadio)
		#expect(manager.connectedRadios.first?.name == "First")
		#expect(manager.additionalRadioDevices.count == 3)
	}
}
