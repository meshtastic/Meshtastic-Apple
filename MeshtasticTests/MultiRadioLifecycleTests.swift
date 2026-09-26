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

/// A connection that does nothing and records disconnects.
private actor IdleConnection: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	private(set) var disconnects = 0

	func send(_ data: ToRadio) async throws {}
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
		let focusedDevice = device("Focused")
		manager.activeConnection = RadioSession(device: focusedDevice, connection: IdleConnection())

		let absent = device("Absent")
		await #expect(throws: AccessoryError.self) {
			try await manager.connectAdditionalRadio(absent, connectTimeout: .milliseconds(200))
		}
		#expect(manager.additionalRadios.isEmpty)
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

		// A focused connect records the time but leaves the choice alone.
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
