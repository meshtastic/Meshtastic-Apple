//
//  MultiRadioLifecycleTests.swift
//  MeshtasticTests
//
//  Feature 021: one handshake at a time (T064), bounded automatic connects, remembered radios
//  (T063) and ACK matching per radio.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

// MARK: - Test doubles

/// A connection that records what it sends and how often it's disconnected.
private actor IdleConnection: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	private(set) var disconnects = 0
	private(set) var sent: [ToRadio] = []

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

/// A connection whose sends fail.
private actor FailingConnection: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	func send(_ data: ToRadio) async throws { throw AccessoryError.ioFailed("Send failed") }
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

/// A TCP transport whose discovery finds `found` once asked to.
private final class OneDeviceDiscoveryTransport: Transport, @unchecked Sendable {
	let type: TransportType = .tcp
	var status: TransportStatus { .ready }
	let requiresPeriodicHeartbeat = false
	let supportsManualConnection = false
	let found: Device

	init(found: Device) { self.found = found }

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> {
		let found = found
		return AsyncStream { continuation in
			continuation.yield(.deviceFound(found))
		}
	}
	func connect(to device: Device) async throws -> any Connection {
		try await Task.sleep(for: .seconds(3600))
		return IdleConnection()
	}
	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
}

/// A TCP transport whose connect never finishes on its own, like BLE to an out-of-range radio.
private final class HangingTransport: Transport, @unchecked Sendable {
	let type: TransportType = .tcp
	var status: TransportStatus { .ready }
	let requiresPeriodicHeartbeat = false
	let supportsManualConnection = false

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> { AsyncStream { $0.finish() } }
	func connect(to device: Device) async throws -> any Connection {
		try await Task.sleep(for: .seconds(3600))
		return IdleConnection()
	}
	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
}

// MARK: - Handshake gate

@MainActor
@Suite("Handshake gate")
struct HandshakeGateTests {

	@Test("Waiters get the gate one at a time, in order")
	func servesInOrder() async {
		let gate = HandshakeGate()
		var order: [Int] = []
		await gate.acquire()
		#expect(gate.isBusy)

		let first = Task { @MainActor in
			await gate.acquire()
			order.append(1)
			gate.release()
		}
		let second = Task { @MainActor in
			// Queue behind the first waiter.
			await Task.yield()
			await gate.acquire()
			order.append(2)
			gate.release()
		}
		// Let both queue up.
		for _ in 0..<10 { await Task.yield() }
		#expect(order.isEmpty)

		gate.release()
		await first.value
		await second.value
		#expect(order == [1, 2])
		#expect(!gate.isBusy)
	}
}

// MARK: - Connect lifecycle

@MainActor
@Suite("Multi-radio connect lifecycle", .serialized, .timeLimit(.minutes(1)))
struct MultiRadioConnectLifecycleTests {

	private func device(_ name: String, transport: TransportType = .tcp) -> Device {
		Device(id: UUID(), name: name, transportType: transport, identifier: "\(name).local:4403")
	}

	@Test("A connect waiting for another radio's handshake is cancelled by disconnect")
	func disconnectCancelsAWaitingConnect() async throws {
		let manager = AccessoryManager(transports: [HangingTransport()])
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		await manager.handshakeGate.acquire()

		let radio = device("Waiting")
		let connect = Task { @MainActor in try await manager.connect(to: radio) }
		for _ in 0..<10 { await Task.yield() }
		try await manager.disconnect()
		manager.handshakeGate.release()

		await #expect(throws: AccessoryError.self) { try await connect.value }
		#expect(manager.activeConnection == nil)
		#expect(!manager.handshakeGate.isBusy)
	}

	@Test("An automatic connect to a radio that never answers gives up")
	func boundedAutomaticConnect() async throws {
		let manager = AccessoryManager(transports: [HangingTransport()])
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		let firstDevice = device("First")
		manager.activeConnection = RadioSession(device: firstDevice, connection: IdleConnection())

		let absent = device("Absent")
		await #expect(throws: AccessoryError.self) {
			try await manager.connectAdditionalRadio(absent, connectTimeout: .milliseconds(200))
		}
		#expect(manager.additionalRadios.isEmpty)
		#expect(!manager.handshakeGate.isBusy)
	}

	@Test("A connect as the first radio with a bound gives up on a radio that never answers, as the others' do")
	func boundedFirstConnect() async throws {
		let manager = AccessoryManager(transports: [HangingTransport()])
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		let absent = device("Absent")
		let started = ContinuousClock.now
		try await manager.connect(to: absent, retries: 1, connectTimeout: .milliseconds(200))
		#expect(ContinuousClock.now - started < .seconds(3), "the bound, not the 5 s step timeout")
		#expect(manager.activeConnection == nil)
		#expect(!manager.handshakeGate.isBusy)
	}

	@Test("A remembered BLE radio resolves by its peripheral id; an unknown TCP one doesn't")
	func rememberedRadioResolution() {
		let manager = AccessoryManager(transports: [])
		let bleId = UUID()
		let ble = MeshPackets.RememberedRadio(nodeNum: 0x0B0B, peripheralId: bleId.uuidString, name: "Radio B", transport: .ble)
		let resolved = manager.device(for: ble)
		#expect(resolved?.id == bleId)
		#expect(resolved?.identifier == bleId.uuidString)
		#expect(resolved?.num == 0x0B0B)

		let tcp = MeshPackets.RememberedRadio(nodeNum: 0x0C0C, peripheralId: UUID().uuidString, name: "Radio C", transport: .tcp)
		#expect(manager.device(for: tcp) == nil)

		let bad = MeshPackets.RememberedRadio(nodeNum: 0x0D0D, peripheralId: "not-a-uuid", name: "Radio D", transport: .ble)
		#expect(manager.device(for: bad) == nil)
	}

	@Test("A window's sends go through its own radio, and fail rather than use another when it's off")
	func windowSendsUseTheirRadio() async throws {
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		var first = device("First")
		first.num = 0x0A1A
		first.connectionState = .connected
		let firstConnection = IdleConnection()
		manager.activeConnection = RadioSession(device: first, connection: firstConnection)
		var second = device("Second")
		second.num = 0x0B1B
		second.connectionState = .connected
		let secondConnection = IdleConnection()
		manager.additionalRadios[second.id] = RadioSession(device: second, connection: secondConnection)
		var waypoint = Waypoint()
		waypoint.id = 0x5151
		waypoint.latitudeI = 1
		waypoint.longitudeI = 1

		try await manager.sendTraceRouteRequest(destNum: 0x1234, wantResponse: true, viaRadio: 0x0B1B)
		try await manager.sendWaypoint(waypoint: waypoint, viaRadio: 0x0B1B)
		#expect(await secondConnection.sent.count == 2)
		#expect(await firstConnection.sent.isEmpty)

		await #expect(throws: (any Error).self) {
			try await manager.sendWaypoint(waypoint: waypoint, viaRadio: 0x0C1C)
		}
		#expect(await firstConnection.sent.isEmpty, "never through another radio")
	}

	@Test("A remembered radio seen by discovery comes back while only radios other than the first are connected")
	func rememberedRadioComesBackWithoutTheFirst() async throws {
		var tcpDevice = device("Radio C")
		tcpDevice.num = 0x0C0D
		let manager = AccessoryManager(transports: [OneDeviceDiscoveryTransport(found: tcpDevice)])
		// The first radio dropped; another stays connected (D-19).
		var other = device("Other")
		other.num = 0x0B0E
		other.connectionState = .connected
		manager.additionalRadios[other.id] = RadioSession(device: other, connection: IdleConnection())
		manager.awaitedRememberedRadios.insert(tcpDevice.id)

		manager.startDiscovery()
		var waited = 0
		while manager.additionalRadioReconnects[tcpDevice.id] == nil, waited < 200 {
			try await Task.sleep(for: .milliseconds(10))
			waited += 1
		}
		#expect(manager.additionalRadioReconnects[tcpDevice.id] != nil)
		manager.stopDiscovery()
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
	}

	@Test("A remembered TCP radio seen by discovery is brought back, even after discovery stopped")
	func rememberedTCPRadioComesBack() async throws {
		var tcpDevice = device("Radio C")
		tcpDevice.num = 0x0C0C
		let manager = AccessoryManager(transports: [OneDeviceDiscoveryTransport(found: tcpDevice)])
		manager.activeConnection = RadioSession(device: device("First"), connection: IdleConnection())
		let remembered = MeshPackets.RememberedRadio(nodeNum: 0x0C0C, peripheralId: tcpDevice.id.uuidString, name: "Radio C", transport: .tcp)

		// Not seen yet: waited for, then brought back when discovery finds it.
		#expect(manager.device(for: remembered) == nil)
		manager.awaitedRememberedRadios.insert(tcpDevice.id)
		manager.startDiscovery()
		var waited = 0
		while manager.additionalRadioReconnects[tcpDevice.id] == nil, waited < 200 {
			try await Task.sleep(for: .milliseconds(10))
			waited += 1
		}
		#expect(manager.additionalRadioReconnects[tcpDevice.id] != nil)
		#expect(manager.awaitedRememberedRadios.isEmpty)

		// Seen before discovery stopped: still resolvable.
		manager.stopDiscovery()
		#expect(manager.devices.isEmpty)
		#expect(manager.device(for: remembered)?.id == tcpDevice.id)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
	}

	@Test("A remembered radio in range stands in for a missing preferred radio")
	func rememberedRadioFallback() {
		let previousAuto = UserDefaults.autoconnectOnDiscovery
		let previousPreferred = UserDefaults.preferredPeripheralId
		defer {
			UserDefaults.autoconnectOnDiscovery = previousAuto
			UserDefaults.preferredPeripheralId = previousPreferred
		}
		UserDefaults.autoconnectOnDiscovery = true
		let preferred = device("Preferred", transport: .ble)
		let inRange = device("In range", transport: .ble)
		let away = UUID()
		UserDefaults.preferredPeripheralId = preferred.id.uuidString
		let manager = AccessoryManager(transports: [])
		manager.devices = [preferred, inRange]
		let remembered = [
			MeshPackets.RememberedRadio(nodeNum: 1, peripheralId: preferred.id.uuidString, name: "Preferred", transport: .ble),
			MeshPackets.RememberedRadio(nodeNum: 2, peripheralId: away.uuidString, name: "Away", transport: .ble),
			MeshPackets.RememberedRadio(nodeNum: 3, peripheralId: inRange.id.uuidString, name: "In range", transport: .ble)
		]

		// Not the preferred radio (its own auto-connect handles it), not one that's out of range.
		#expect(manager.rememberedRadioFallbackCandidate(from: remembered)?.id == inRange.id)

		manager.userRequestedConnectionCancellation = true
		#expect(manager.rememberedRadioFallbackCandidate(from: remembered) == nil)
		manager.userRequestedConnectionCancellation = false
		UserDefaults.autoconnectOnDiscovery = false
		#expect(manager.rememberedRadioFallbackCandidate(from: remembered) == nil)
		UserDefaults.autoconnectOnDiscovery = true
		manager.activeConnection = RadioSession(device: preferred, connection: IdleConnection())
		#expect(manager.rememberedRadioFallbackCandidate(from: remembered) == nil)
	}

	@Test("The phone position loop keeps going for the other radios when the first one closes")
	func positionLoopOutlivesFirstClose() async throws {
		let manager = AccessoryManager(transports: [])
		manager.activeConnection = RadioSession(device: device("First"), connection: IdleConnection())
		var extra = device("Extra")
		extra.num = 0x0B0C
		extra.connectionState = .connected
		manager.additionalRadios[extra.id] = RadioSession(device: extra, connection: IdleConnection())
		manager.initializeLocationProvider()

		try await manager.closeConnection()
		#expect(manager.locationTask != nil, "another radio is still connected")

		manager.additionalRadios.removeAll()
		manager.activeConnection = RadioSession(device: device("Only"), connection: IdleConnection())
		try await manager.closeConnection()
		#expect(manager.locationTask == nil, "with one radio it stops, as before")
	}

	@Test("A failed send to the first radio doesn't end the position loop while other radios are connected")
	func firstPositionFailureKeepsLoop() async throws {
		let manager = AccessoryManager(transports: [])
		var first = device("First")
		first.num = 0x0A0B
		first.connectionState = .connected
		manager.activeConnection = RadioSession(device: first, connection: FailingConnection())
		// Fails whether or not the phone has a location: without one there's nothing to send.
		await #expect(throws: (any Error).self, "with one radio it ends the loop, as before") {
			try await manager.sharePhonePosition()
		}

		var extra = device("Extra")
		extra.num = 0x0B0D
		extra.connectionState = .connected
		manager.additionalRadios[extra.id] = RadioSession(device: extra, connection: FailingConnection())
		try await manager.sharePhonePosition()
	}

	@Test("Each radio's heartbeat timeout follows its own firmware, not the first radio's")
	func heartbeatTimeoutPerRadio() async {
		let manager = AccessoryManager(transports: [])
		var first = device("First")
		first.firmwareVersion = "2.7.15.abcdef0"
		manager.activeConnection = RadioSession(device: first, connection: IdleConnection())
		var old = device("Old")
		old.num = 0x0B0B
		old.firmwareVersion = "2.6.11.1234567"
		let oldSession = RadioSession(device: old, connection: IdleConnection())
		var unknown = device("Unknown")
		unknown.num = 0x0C0C
		let unknownSession = RadioSession(device: unknown, connection: IdleConnection())

		#expect(!manager.isVersionSupported(forVersion: "2.7.4", on: oldSession))
		#expect(manager.isVersionSupported(forVersion: "2.7.4", on: unknownSession), "unknown is permissive, as for the first radio")
		manager.knownFirmwareVersions[0x0C0C] = "2.5.20.1234567"
		#expect(!manager.isVersionSupported(forVersion: "2.7.4", on: unknownSession))

		await manager.setupPeriodicHeartbeat(on: oldSession)
		#expect(oldSession.heartbeatTimer != nil)
		#expect(oldSession.heartbeatResponseTimer == nil, "2.6 doesn't answer the heartbeat, so no timeout")
		await oldSession.heartbeatTimer?.cancel(withReason: "test")
	}

	@Test("Every radio's packets count towards the ingest recycle, and the retired actor keeps saving")
	func ingestRecycleCountsEveryRadio() async throws {
		let manager = AccessoryManager(transports: [])
		manager.ingestPacketsSinceRecycle = AccessoryManager.ingestRecycleInterval - 2
		let before = MeshPackets.shared

		await manager.noteIngestedPacket()
		#expect(MeshPackets.shared === before)
		await manager.noteIngestedPacket()

		#expect(MeshPackets.shared !== before)
		#expect(manager.ingestPacketsSinceRecycle == 0)
		// A memory recycle clears nothing: what other radios had in flight is still saved.
		try await Task.sleep(for: .milliseconds(50))
		#expect(await !before.invalidated)
	}

	@Test("A write that doesn't save itself, left on a recycled ingest actor, still reaches the store")
	func recycledActorSavesQueuedWrites() async throws {
		let before = MeshPackets.shared
		MeshPackets.recreateShared(invalidatingPrevious: false)
		var data = DataMessage()
		data.portnum = .positionApp
		var packet = MeshPacket()
		packet.id = UInt32.random(in: 1...UInt32.max)
		packet.from = 0x7E57_0001
		packet.to = Constants.maximumNodeNum
		packet.decoded = data
		let radioNum: Int64 = 0x7E57_00AA
		// One of the user's radios, so keyed lookups try it.
		let shared = PersistenceController.shared.context
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = radioNum
		shared.insert(myInfo)
		try shared.save()
		defer {
			shared.delete(myInfo)
			try? shared.save()
		}
		// `recordReception` never saves; the save after it goes to the new instance.
		#expect(await before.recordReception(packet: packet, radioNum: radioNum) == .first)

		let key = PacketReceptionEntity.key(radioNum: radioNum, fromNum: Int64(packet.from), packetId: Int64(packet.id))
		// Saved as it happened, so the new instance sees it at once (T198): another radio's copy
		// of the packet is a copy, not a first delivery.
		let context = ModelContext(PersistenceController.shared.container)
		#expect(((try? context.fetchCount(FetchDescriptor<PacketReceptionEntity>(predicate: #Predicate { $0.key == key }))) ?? 0) == 1)
		#expect(await MeshPackets.shared.recordReception(packet: packet, radioNum: 0x7E57_00BB) == .heardByAnotherRadio)
	}

	@Test("Analyze Current Preset from another radio's window runs on that radio, not the first")
	func currentPresetScanKeepsItsRadio() async throws {
		let manager = AccessoryManager(transports: [])
		var firstDevice = device("First")
		firstDevice.num = 0x5CA1_0011
		firstDevice.connectionState = .connected
		manager.activeConnection = RadioSession(device: firstDevice, connection: IdleConnection())
		manager.activeDeviceNum = firstDevice.num
		var otherDevice = device("Other")
		otherDevice.num = 0x5CA1_0012
		otherDevice.connectionState = .connected
		manager.additionalRadios[otherDevice.id] = RadioSession(device: otherDevice, connection: IdleConnection())
		let engine = DiscoveryScanEngine()
		engine.configure(accessoryManager: manager, modelContext: sharedModelContainer.mainContext)
		manager.discoveryScanEngine = engine
		await engine.startCurrentPresetScan(radio: 0x5CA1_0012)
		#expect(engine.currentState == .dwell)
		#expect(engine.scanRadioNum == 0x5CA1_0012)
		await engine.stopScan()
		manager.discoveryScanEngine = nil
	}

	@Test("A discovery scan counts its radio's copy of a packet another radio delivered first")
	func scanCountsItsOwnCopy() async throws {
		let manager = AccessoryManager(transports: [])
		var scanDevice = device("Scan")
		scanDevice.num = 0x5CA1_0001
		scanDevice.connectionState = .connected
		manager.activeConnection = RadioSession(device: scanDevice, connection: IdleConnection())
		manager.activeDeviceNum = scanDevice.num
		var otherDevice = device("Other")
		otherDevice.num = 0x5CA1_0002
		otherDevice.connectionState = .connected
		let other = RadioSession(device: otherDevice, connection: IdleConnection())
		manager.additionalRadios[otherDevice.id] = other
		let engine = DiscoveryScanEngine()
		engine.configure(accessoryManager: manager, modelContext: sharedModelContainer.mainContext)
		manager.discoveryScanEngine = engine
		await engine.startCurrentPresetScan()
		#expect(engine.currentState == .dwell)
		#expect(manager.linkState(ofRadio: 0x5CA1_0002) == (true, true))

		let remote: UInt32 = 0x5CA1_0F0F
		var data = DataMessage()
		data.portnum = .positionApp
		var packet = MeshPacket()
		packet.id = UInt32.random(in: 1...UInt32.max)
		packet.from = remote
		packet.to = Constants.maximumNodeNum
		packet.decoded = data
		var fromRadio = FromRadio()
		fromRadio.packet = packet

		// The other radio delivers first; the scan radio's copy still counts for the scan.
		await manager.processFromRadio(fromRadio, session: other)
		#expect(engine.session?.discoveredNodes.contains { $0.nodeNum == Int64(remote) } != true)
		await manager.processFromRadio(fromRadio, session: try #require(manager.activeConnection))
		#expect(engine.session?.discoveredNodes.contains { $0.nodeNum == Int64(remote) } == true)

		await engine.stopScan()
		manager.discoveryScanEngine = nil
	}
}

// MARK: - Favorites and sends on each radio's own connection

extension MultiRadioConnectLifecycleTests {
	@Test("Un-favoriting a node clears every radio's observation of it, so no radio's old view brings it back")
	func unfavoriteRecordsOnEveryObservation() async throws {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("Unfavorite-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let context = ModelContext(try ModelContainer(for: schema, configurations: config))
		let node = NodeInfoEntity()
		node.num = 0x4242
		node.favorite = true
		context.insert(node)
		for radio: Int64 in [0x0A0A, 0x0B0B] {
			let observation = NodeObservationEntity(radioNum: radio, nodeNum: 0x4242)
			observation.favorite = true
			context.insert(observation)
		}
		try context.save()

		try await AccessoryManager(transports: []).setFavorite(false, node: node)

		let observations = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		#expect(observations.count == 2)
		#expect(observations.allSatisfy { !$0.favorite })
	}

	@Test("Favoriting a node reaches every connected radio, each on its own connection")
	func favoriteOnEveryRadio() async throws {
		let firstNum: Int64 = 0x0A0A, extraNum: Int64 = 0x0B0B
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		let firstConnection = IdleConnection()
		var firstDevice = device("First")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: firstConnection)
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		manager.additionalRadios[extraDevice.id] = RadioSession(device: extraDevice, connection: extraConnection)
		let node = NodeInfoEntity()
		node.num = 0x1234

		try await manager.setFavorite(true, node: node)

		for (connection, radioNum) in [(firstConnection, firstNum), (extraConnection, extraNum)] {
			let sent = await connection.sent
			#expect(sent.count == 1)
			#expect(sent.first?.packet.to == UInt32(radioNum))
			let admin = try AdminMessage(serializedBytes: try #require(sent.first?.packet.decoded.payload))
			#expect(admin.setFavoriteNode == 0x1234)
		}
	}

	@Test("A message sent via another radio goes out on that radio, as that radio")
	func sendViaAdditionalRadio() async throws {
		let firstNum: Int64 = 0x0A0A, extraNum: Int64 = 0x0B0B, remoteNum: Int64 = 0x1234
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("SendVia-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		for num in [firstNum, extraNum, remoteNum] {
			let user = UserEntity()
			user.num = num
			context.insert(user)
		}
		try context.save()

		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let firstConnection = IdleConnection()
		var firstDevice = device("First")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: firstConnection)
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		let extra = RadioSession(device: extraDevice, connection: extraConnection)
		manager.additionalRadios[extraDevice.id] = extra

		try await manager.sendMessage(message: "hello", toUserNum: remoteNum, channel: 0, isEmoji: false, replyID: 0, viaRadio: extraNum)

		// The transmit runs in its own task after the save.
		var waited = 0
		while await extraConnection.sent.isEmpty, waited < 100 {
			try await Task.sleep(for: .milliseconds(10))
			waited += 1
		}
		let sent = await extraConnection.sent
		#expect(sent.count == 1)
		#expect(sent.first?.packet.from == UInt32(extraNum))
		#expect(sent.first?.packet.to == UInt32(remoteNum))
		#expect(await firstConnection.sent.isEmpty)

		let stored = try context.fetch(FetchDescriptor<MessageEntity>())
		#expect(stored.count == 1)
		#expect(stored.first?.localNodeNum == extraNum)
		#expect(stored.first?.fromNum == extraNum)
		#expect(stored.first?.messageKey == MessageEntity.key(fromNum: extraNum, messageId: stored.first?.messageId ?? 0))

		// A radio that isn't connected can't send.
		await #expect(throws: AccessoryError.self) {
			try await manager.sendMessage(message: "nope", toUserNum: remoteNum, channel: 0, isEmoji: false, replyID: 0, viaRadio: 0x0C0C)
		}
	}

	@Test("Remove Node in another radio's window goes out on that radio's connection, and not at all while it's off")
	func removeNodeOnItsRadio() async throws {
		let firstNum: Int64 = 0x0A0A, extraNum: Int64 = 0x0B0B, remoteNum: Int64 = 0x7E57_0354
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("RemoveNode-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		let node = NodeInfoEntity()
		node.num = remoteNum
		context.insert(node)
		try context.save()

		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let firstConnection = IdleConnection()
		var firstDevice = device("First")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: firstConnection)
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		manager.additionalRadios[extraDevice.id] = RadioSession(device: extraDevice, connection: extraConnection)

		await #expect(throws: AccessoryError.self, "its radio is off") {
			try await manager.removeNode(node: node, connectedNodeNum: 0x0C0C)
		}
		#expect(await firstConnection.sent.isEmpty, "never through another radio")
		#expect(try context.fetchCount(FetchDescriptor<NodeInfoEntity>()) == 1, "kept while it can't be removed from the radio")

		try await manager.removeNode(node: node, connectedNodeNum: extraNum)
		let sent = await extraConnection.sent
		#expect(sent.count == 1)
		#expect(sent.first?.packet.to == UInt32(extraNum))
		let admin = try AdminMessage(serializedBytes: sent.first?.packet.decoded.payload ?? Data())
		#expect(admin.removeByNodenum == UInt32(remoteNum))
		#expect(await firstConnection.sent.isEmpty)
		#expect(try context.fetchCount(FetchDescriptor<NodeInfoEntity>()) == 0)
	}

	@Test("Client History from another radio goes out on that radio's connection, and not at all while it's off")
	func clientHistoryOnItsRadio() async throws {
		let firstNum: Int64 = 0x0A0A, extraNum: Int64 = 0x0B0B, routerNum: Int64 = 0x7E57_0355
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("ClientHistory-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		var users: [Int64: UserEntity] = [:]
		for num in [extraNum, routerNum, 0x0C0C] {
			let user = UserEntity()
			user.num = num
			context.insert(user)
			users[num] = user
		}
		try context.save()

		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let firstConnection = IdleConnection()
		var firstDevice = device("First")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: firstConnection)
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		manager.additionalRadios[extraDevice.id] = RadioSession(device: extraDevice, connection: extraConnection)
		let router = try #require(users[routerNum])

		try await manager.requestStoreAndForwardClientHistory(fromUser: try #require(users[extraNum]), toUser: router, channel: 2)
		let sent = await extraConnection.sent
		#expect(sent.count == 1)
		#expect(sent.first?.packet.from == UInt32(extraNum))
		#expect(sent.first?.packet.channel == 2)
		#expect(await firstConnection.sent.isEmpty)

		await #expect(throws: AccessoryError.self, "its radio is off") {
			try await manager.requestStoreAndForwardClientHistory(fromUser: try #require(users[0x0C0C]), toUser: router, channel: 0)
		}
		#expect(await firstConnection.sent.isEmpty, "never through another radio")
	}

	@Test("A metadata request from another radio needs that radio connected, not the first")
	func metadataFromItsRadio() async throws {
		let extraNum: Int64 = 0x0B0B, remoteNum: Int64 = 0x7E57_0357, offNum: Int64 = 0x0C0C
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Metadata-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		var users: [Int64: UserEntity] = [:]
		for num in [extraNum, remoteNum, offNum] {
			let user = UserEntity()
			user.num = num
			context.insert(user)
			users[num] = user
		}
		try context.save()

		// The first radio is gone; only B is connected.
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		extraDevice.connectionState = .connected
		manager.additionalRadios[extraDevice.id] = RadioSession(device: extraDevice, connection: extraConnection)
		#expect(!manager.isConnected)

		_ = try await manager.requestDeviceMetadata(fromUser: try #require(users[extraNum]), toUser: try #require(users[remoteNum]))
		let sent = await extraConnection.sent
		#expect(sent.count == 1)
		#expect(sent.first?.packet.to == UInt32(remoteNum))

		await #expect(throws: AccessoryError.self, "a radio that's off") {
			_ = try await manager.requestDeviceMetadata(fromUser: try #require(users[offNum]), toUser: try #require(users[remoteNum]))
		}
	}

	@Test("Exchange User Info goes out on the radio it's from, and not through the first radio while that one is off")
	func exchangeUserInfoOnItsRadio() async throws {
		let firstNum: Int64 = 0x0A0A, extraNum: Int64 = 0x0B0B, remoteNum: Int64 = 0x7E57_0358, offNum: Int64 = 0x0C0C
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("UserInfo-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		var users: [Int64: UserEntity] = [:]
		for num in [extraNum, remoteNum, offNum] {
			let user = UserEntity()
			user.num = num
			context.insert(user)
			users[num] = user
		}
		try context.save()

		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let firstConnection = IdleConnection()
		var firstDevice = device("First")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: firstConnection)
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		manager.additionalRadios[extraDevice.id] = RadioSession(device: extraDevice, connection: extraConnection)
		let remote = try #require(users[remoteNum])

		_ = try await manager.exchangeUserInfo(fromUser: try #require(users[extraNum]), toUser: remote)
		#expect(await extraConnection.sent.count == 1)
		#expect(await firstConnection.sent.isEmpty)

		await #expect(throws: AccessoryError.self, "its radio is off") {
			_ = try await manager.exchangeUserInfo(fromUser: try #require(users[offNum]), toUser: remote)
		}
		#expect(await firstConnection.sent.isEmpty, "never through another radio")
	}

	@Test("An encrypted DM via another radio refreshes the contact on that radio and pins the node on both")
	func encryptedDirectMessageFollowUpsUseTheSendingRadio() async throws {
		let firstNum: Int64 = 0x0A0A, extraNum: Int64 = 0x0B0B, remoteNum: Int64 = 0x7E57_0021
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let container = try ModelContainer(for: schema, configurations: ModelConfiguration("SendViaPKI-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
		let context = ModelContext(container)
		for num in [firstNum, extraNum] {
			let user = UserEntity()
			user.num = num
			context.insert(user)
		}
		let remoteUser = UserEntity()
		remoteUser.num = remoteNum
		remoteUser.longName = "Remote"
		remoteUser.pkiEncrypted = true
		remoteUser.publicKey = Data(repeating: 7, count: 32)
		context.insert(remoteUser)
		let remoteNode = NodeInfoEntity()
		remoteNode.num = remoteNum
		context.insert(remoteNode)
		remoteNode.user = remoteUser
		try context.save()

		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		manager.context = context
		let firstConnection = IdleConnection()
		var firstDevice = device("First")
		firstDevice.num = firstNum
		manager.activeConnection = RadioSession(device: firstDevice, connection: firstConnection)
		let extraConnection = IdleConnection()
		var extraDevice = device("Extra")
		extraDevice.num = extraNum
		manager.additionalRadios[extraDevice.id] = RadioSession(device: extraDevice, connection: extraConnection)

		try await manager.sendMessage(message: "secret", toUserNum: remoteNum, channel: 0, isEmoji: false, replyID: 0, viaRadio: extraNum)

		// Text, add-contact and favorite on B; favorite on A. Each runs in its own task.
		var waited = 0
		while waited < 200 {
			let extraCount = await extraConnection.sent.count
			let firstCount = await firstConnection.sent.count
			if extraCount >= 3 && firstCount >= 1 { break }
			try await Task.sleep(for: .milliseconds(10))
			waited += 1
		}
		func admins(_ sent: [ToRadio]) -> [AdminMessage] {
			sent.filter { $0.packet.decoded.portnum == .adminApp }
				.compactMap { try? AdminMessage(serializedBytes: $0.packet.decoded.payload) }
		}
		let extraSent = await extraConnection.sent
		let firstSent = await firstConnection.sent
		#expect(extraSent.contains { $0.packet.decoded.portnum == .textMessageApp && $0.packet.pkiEncrypted })
		#expect(admins(extraSent).contains { $0.addContact.nodeNum == UInt32(remoteNum) })
		#expect(admins(extraSent).contains { $0.setFavoriteNode == UInt32(remoteNum) })
		// The first radio gets the pin, but not the contact or the text.
		#expect(admins(firstSent).contains { $0.setFavoriteNode == UInt32(remoteNum) })
		#expect(!admins(firstSent).contains { $0.addContact.nodeNum == UInt32(remoteNum) })
		#expect(!firstSent.contains { $0.packet.decoded.portnum == .textMessageApp })
	}
}

// MARK: - Remembered radios and ACK matching (store)

@Suite("Multi-radio remembered radios and ACKs")
struct MultiRadioRememberedTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B

	private func makePackets() async throws -> (MeshPackets, ModelContainer) {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("MultiRadioRememberedTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		let container = try ModelContainer(for: schema, configurations: config)
		let packets = MeshPackets(modelContainer: container)
		await packets.replaceNotificationScheduler { @MainActor @Sendable _ in }
		return (packets, container)
	}

	private func seedMyInfo(_ nums: [Int64], in container: ModelContainer) throws {
		let context = ModelContext(container)
		for num in nums {
			let myInfo = MyInfoEntity()
			myInfo.myNodeNum = num
			myInfo.peripheralId = UUID().uuidString
			context.insert(myInfo)
		}
		try context.save()
	}

	@Test("Radios connected alongside are remembered until the user disconnects them")
	func rememberAndForget() async throws {
		let (packets, container) = try await makePackets()
		try seedMyInfo([radioA, radioB], in: container)

		await packets.noteRadioConnected(nodeNum: radioA, transport: .ble, autoConnect: nil)
		await packets.noteRadioConnected(nodeNum: radioB, transport: .tcp, autoConnect: true)

		var remembered = await packets.rememberedRadios(excluding: [])
		#expect(remembered.map(\.nodeNum) == [radioB])
		#expect(remembered.first?.transport == .tcp)
		#expect(await packets.rememberedRadios(excluding: [radioB]).isEmpty)

		// A connect as the first radio records the time but leaves the choice alone.
		await packets.noteRadioConnected(nodeNum: radioB, transport: .tcp, autoConnect: nil)
		remembered = await packets.rememberedRadios(excluding: [])
		#expect(remembered.map(\.nodeNum) == [radioB])

		await packets.setRadioAutoConnect(nodeNum: radioB, false)
		#expect(await packets.rememberedRadios(excluding: []).isEmpty)

		let context = ModelContext(container)
		let rows = try context.fetch(FetchDescriptor<MyInfoEntity>())
		#expect(rows.allSatisfy { $0.lastConnected != nil })
		#expect(rows.first { $0.myNodeNum == radioA }?.transport == TransportType.ble.rawValue)
	}

	@Test("An ACK matches the message the delivering radio sent")
	func ackMatchesPerRadio() async throws {
		let (packets, container) = try await makePackets()
		let sharedId: Int64 = 4242
		let context = ModelContext(container)
		for (radio, text) in [(radioA, "from A"), (radioB, "from B")] {
			let message = MessageEntity()
			message.messageId = sharedId
			message.fromNum = radio
			message.messageKey = MessageEntity.key(fromNum: radio, messageId: sharedId)
			message.messagePayload = text
			context.insert(message)
		}
		let legacy = MessageEntity()
		legacy.messageId = 777
		legacy.messagePayload = "no key yet"
		context.insert(legacy)
		try context.save()

		#expect(try await packets.sentMessage(requestID: sharedId, radioNum: radioB)?.messagePayload == "from B")
		#expect(try await packets.sentMessage(requestID: sharedId, radioNum: radioA)?.messagePayload == "from A")
		// Rows the backfill hasn't reached fall back to the id alone.
		#expect(try await packets.sentMessage(requestID: 777, radioNum: radioA)?.messagePayload == "no key yet")
		#expect(try await packets.sentMessage(requestID: 999, radioNum: radioA) == nil)
	}
}
