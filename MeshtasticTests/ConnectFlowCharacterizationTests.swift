//
//  ConnectFlowCharacterizationTests.swift
//  MeshtasticTests
//
//  Feature 021, T068: pins what `AccessoryManager.connect(to:)` does today, end to end, against
//  a scripted radio. These are the safety net for moving the connect flow onto `RadioSession`
//  and running every radio through it (D-17, plan.md › Every radio the same): the steps may
//  move, but what a radio sees and what the app ends up with must not change.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

// MARK: - Scripted radio

/// A radio that answers the two want-config requests the way firmware does: config, then
/// `configCompleteID`; node DB, then `configCompleteID`. Records everything the app sends.
private actor ScriptedRadio: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	private(set) var sent: [ToRadio] = []
	private(set) var disconnects = 0
	private var continuation: AsyncStream<ConnectionEvent>.Continuation?

	let nodeNum: UInt32
	let firmwareVersion: String
	let dumpNodes: [UInt32]
	/// When false, the radio never finishes the config request.
	let answersConfig: Bool
	/// The device config's `tzdef`; blank asks the app to fill it in.
	let timezone: String
	/// Canned messages module on, which makes the app ask for the messages.
	let cannedMessages: Bool

	init(
		nodeNum: UInt32,
		firmwareVersion: String = "2.7.15.567b8ea",
		dumpNodes: [UInt32] = [],
		answersConfig: Bool = true,
		timezone: String = "UTC0",
		cannedMessages: Bool = false
	) {
		self.nodeNum = nodeNum
		self.firmwareVersion = firmwareVersion
		self.dumpNodes = dumpNodes
		self.answersConfig = answersConfig
		self.timezone = timezone
		self.cannedMessages = cannedMessages
	}

	/// Sends an event as if the link produced it.
	func emit(_ event: ConnectionEvent) {
		continuation?.yield(event)
	}

	func emit(_ variant: FromRadio.OneOf_PayloadVariant) {
		yield(variant)
	}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		let (stream, continuation) = AsyncStream.makeStream(of: ConnectionEvent.self)
		self.continuation = continuation
		return stream
	}

	func send(_ data: ToRadio) async throws {
		guard isConnected else { throw AccessoryError.connectionFailed("Scripted radio disconnected") }
		sent.append(data)
		if case .wantConfigID(let nonce) = data.payloadVariant {
			// After a round trip, like a real radio. Answering inside `send` beats the app's
			// first-node wait for an empty node DB (see HANDOFF.md › Gotchas, T068).
			Task {
				try? await Task.sleep(for: .milliseconds(20))
				self.answer(nonce)
			}
		}
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		isConnected = false
		disconnects += 1
		continuation?.finish()
	}

	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}

	private func yield(_ variant: FromRadio.OneOf_PayloadVariant) {
		var fromRadio = FromRadio()
		fromRadio.payloadVariant = variant
		continuation?.yield(.data(fromRadio))
	}

	private func answer(_ nonce: UInt32) {
		switch nonce {
		case 69420:
			guard answersConfig else { return }
			var myInfo = MyNodeInfo()
			myInfo.myNodeNum = nodeNum
			myInfo.deviceID = Data((0..<16).map { UInt8(truncatingIfNeeded: Int(nodeNum) &+ $0) })
			myInfo.nodedbCount = UInt32(dumpNodes.count + 1)
			yield(.myInfo(myInfo))

			var metadata = DeviceMetadata()
			metadata.firmwareVersion = firmwareVersion
			yield(.metadata(metadata))

			yield(.nodeInfo(Self.node(nodeNum, name: "Scripted Radio", short: "SCR")))

			for index in 0..<8 {
				var channel = Channel()
				channel.index = Int32(index)
				if index == 0 {
					channel.role = .primary
					var settings = ChannelSettings()
					settings.psk = Data([1])
					channel.settings = settings
				} else {
					channel.role = .disabled
				}
				yield(.channel(channel))
			}

			var device = Config.DeviceConfig()
			// A blank timezone makes the app send one; a set one keeps the admin traffic quiet.
			device.tzdef = timezone
			var config = Config()
			config.payloadVariant = .device(device)
			yield(.config(config))

			if cannedMessages {
				var canned = ModuleConfig.CannedMessageConfig()
				canned.enabled = true
				var moduleConfig = ModuleConfig()
				moduleConfig.payloadVariant = .cannedMessage(canned)
				yield(.moduleConfig(moduleConfig))
			}

			yield(.configCompleteID(nonce))

		case 69421:
			for num in dumpNodes {
				yield(.nodeInfo(Self.node(num, name: "Node \(num)", short: "N\(num % 100)")))
			}
			yield(.configCompleteID(nonce))

		default:
			break
		}
	}

	static func node(_ num: UInt32, name: String, short: String) -> NodeInfo {
		var user = User()
		user.id = "!" + String(format: "%08x", num)
		user.longName = name
		user.shortName = short
		user.hwModel = .tbeam
		var node = NodeInfo()
		node.num = num
		node.user = user
		node.lastHeard = UInt32(Date().timeIntervalSince1970)
		return node
	}
}

/// A TCP transport that hands out the scripted radio, or fails the way it's told to.
private final class ScriptedTransport: Transport, @unchecked Sendable {
	let type: TransportType = .tcp
	var status: TransportStatus { .ready }
	let supportsManualConnection = false

	let requiresPeriodicHeartbeat: Bool
	private let radio: ScriptedRadio
	private let failure: Error?
	private let lock = NSLock()
	private var attempts = 0

	init(radio: ScriptedRadio, failure: Error? = nil, requiresPeriodicHeartbeat: Bool = false) {
		self.radio = radio
		self.failure = failure
		self.requiresPeriodicHeartbeat = requiresPeriodicHeartbeat
	}

	var connectAttempts: Int { lock.withLock { attempts } }

	func discoverDevices() async -> AsyncStream<DiscoveryEvent> { AsyncStream { $0.finish() } }
	func connect(to device: Device) async throws -> any Connection {
		lock.withLock { attempts += 1 }
		if let failure { throw failure }
		return radio
	}
	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
}

/// What the app sent, in a form the tests can compare.
private enum SentItem: Equatable {
	case heartbeat
	case wantConfig(UInt32)
	case setTime
	case setTimezone(String)
	case cannedMessagesRequest
	case admin
	case packet
	case other
}

private func describe(_ toRadio: ToRadio) -> SentItem {
	switch toRadio.payloadVariant {
	case .heartbeat:
		return .heartbeat
	case .wantConfigID(let nonce):
		return .wantConfig(nonce)
	case .packet(let packet):
		guard packet.decoded.portnum == .adminApp,
			  let admin = try? AdminMessage(serializedBytes: packet.decoded.payload) else { return .packet }
		switch admin.payloadVariant {
		case .setTimeOnly:
			return .setTime
		case .setConfig(let config):
			if case .device(let device) = config.payloadVariant { return .setTimezone(device.tzdef) }
			return .admin
		case .getCannedMessageModuleMessagesRequest:
			return .cannedMessagesRequest
		default:
			return .admin
		}
	default:
		return .other
	}
}

// MARK: - Tests

@MainActor
@Suite("Connect flow (characterization)", .serialized, .timeLimit(.minutes(1)))
struct ConnectFlowCharacterizationTests {

	/// The UserDefaults the connect flow writes, put back after each test.
	private struct SavedDefaults {
		let preferredPeripheralId = UserDefaults.preferredPeripheralId
		let preferredPeripheralNum = UserDefaults.preferredPeripheralNum
		let firmwareVersion = UserDefaults.firmwareVersion
		let lastFirmwareAPIUpdate = UserDefaults.lastFirmwareAPIUpdate

		func restore() {
			UserDefaults.preferredPeripheralId = preferredPeripheralId
			UserDefaults.preferredPeripheralNum = preferredPeripheralNum
			UserDefaults.firmwareVersion = firmwareVersion
			UserDefaults.lastFirmwareAPIUpdate = lastFirmwareAPIUpdate
		}
	}

	private func makeManager(_ transport: ScriptedTransport) -> AccessoryManager {
		// The firmware-update notifier would otherwise refresh from the network in Step 7.
		UserDefaults.lastFirmwareAPIUpdate = Date()
		let manager = AccessoryManager(transports: [transport])
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.appState = AppState(router: Router())
		return manager
	}

	private func uniqueNodeNum() -> UInt32 {
		UInt32.random(in: 0x5000_0000...0x5FFF_FFFF)
	}

	/// Polls `condition` for up to two seconds; the tests then check the outcome themselves.
	private func waitUntil(_ condition: () async -> Bool) async throws {
		for _ in 0..<200 {
			if await condition() { return }
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func device() -> Device {
		Device(id: UUID(), name: "Scripted", transportType: .tcp, identifier: "scripted-\(UUID().uuidString).local:4403")
	}

	@Test("A connect runs heartbeat, config, heartbeat, node DB, then sets the time, and ends connected")
	func happyPath() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let nodeNum = uniqueNodeNum()
		let radio = ScriptedRadio(nodeNum: nodeNum, dumpNodes: [nodeNum &+ 1, nodeNum &+ 2])
		let transport = ScriptedTransport(radio: radio)
		let manager = makeManager(transport)
		let radioDevice = device()

		try await manager.connect(to: radioDevice)

		let sent = await radio.sent.map(describe)
		#expect(Array(sent.prefix(5)) == [.heartbeat, .wantConfig(69420), .heartbeat, .wantConfig(69421), .setTime])
		#expect(transport.connectAttempts == 1)

		#expect(manager.state == .subscribed)
		#expect(manager.isConnected)
		#expect(!manager.isConnecting)
		#expect(manager.activeDeviceNum == Int64(nodeNum))
		#expect(manager.activeConnection?.device.id == radioDevice.id)
		#expect(manager.activeConnection?.device.longName == "Scripted Radio")
		#expect(manager.activeConnection?.device.shortName == "SCR")
		#expect(manager.activeConnection?.device.firmwareVersion == "2.7.15.567b8ea")
		#expect(manager.connectionStepper == nil)
		#expect(!manager.firmwareUpdateRequired)
		#expect(manager.allowDisconnect)
		#expect(manager.expectedNodeDBSize == 3)

		// What the flow records about the radio.
		#expect(UserDefaults.preferredPeripheralId == radioDevice.id.uuidString)
		#expect(UserDefaults.preferredPeripheralNum == Int(nodeNum))
		#expect(UserDefaults.firmwareVersion == "2.7.15")
		let myNodeNum = Int64(nodeNum)
		let myInfo = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == myNodeNum })).first
		#expect(myInfo?.peripheralId == radioDevice.id.uuidString)
		#expect(myInfo?.channels.count == 1, "the primary channel, with the disabled slots dropped")

		try await manager.disconnect()
	}

	@Test("Firmware below the minimum keeps the connection, behind the update gate")
	func oldFirmwareKeepsConnection() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), firmwareVersion: "2.3.0.abcdef0")
		let manager = makeManager(ScriptedTransport(radio: radio))

		try await manager.connect(to: device())

		#expect(manager.firmwareUpdateRequired)
		#expect(manager.isConnected)
		#expect(manager.state == .subscribed)
		#expect(UserDefaults.firmwareVersion == "2.3.0")
		try await manager.disconnect()
	}

	@Test("Disconnect tears everything down and returns to discovering")
	func disconnectTearsDown() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())
		// The connection's own state is on its session (T069); check the one that was closed.
		let session = try #require(manager.activeConnection)
		#expect(session.eventTask != nil)

		try await manager.disconnect()

		#expect(manager.activeConnection == nil)
		#expect(manager.activeDeviceNum == nil)
		#expect(manager.state == .discovering)
		#expect(!manager.isConnected)
		#expect(!manager.allowDisconnect)
		#expect(session.eventTask == nil)
		#expect(session.heartbeatTimer == nil)
		#expect(session.firstDatabaseNodeInfoContinuation == nil)
		#expect(session.automaticConfigRefresh == nil)
		#expect(manager.locationTask == nil)
		#expect(await radio.disconnects == 1)
	}

	@Test("A transport that keeps failing is tried twice, then the connect gives up")
	func transportFailureRetries() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let transport = ScriptedTransport(radio: radio, failure: AccessoryError.connectionFailed("Refused"))
		let manager = makeManager(transport)

		try? await manager.connect(to: device())

		#expect(transport.connectAttempts == 2)
		#expect(manager.activeConnection == nil)
		#expect(!manager.isConnected)
		#expect(manager.lastConnectionError != nil)
		#expect(manager.connectionStepper == nil)
	}

	@Test("A lost bond stops the connect at once and suspends automatic reconnects")
	func lostBondStopsRetries() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let transport = ScriptedTransport(radio: radio, failure: AccessoryError.bondLost)
		let manager = makeManager(transport)

		try? await manager.connect(to: device())

		#expect(transport.connectAttempts == 1)
		#expect(manager.activeConnection == nil)
		#expect(manager.autoReconnectSuspendedForSession)
		#expect(!manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
		if case AccessoryError.bondLost = manager.lastConnectionError ?? AccessoryError.timeout {
		} else {
			Issue.record("lastConnectionError is \(String(describing: manager.lastConnectionError)), expected bondLost")
		}
	}

	@Test("A second connect while one radio is connected is refused")
	func secondConnectRefused() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		await #expect(throws: AccessoryError.self) {
			try await manager.connect(to: device())
		}
		#expect(manager.isConnected)
		try await manager.disconnect()
	}

	@Test("The node DB dump lands in the store, with this radio's view of each node")
	func nodeDumpStored() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let nodeNum = uniqueNodeNum()
		let others: [UInt32] = [nodeNum &+ 11, nodeNum &+ 12, nodeNum &+ 13]
		let radio = ScriptedRadio(nodeNum: nodeNum, dumpNodes: others)
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		let context = PersistenceController.shared.context
		let radioNum = Int64(nodeNum)
		for num in others.map(Int64.init) {
			let node = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
			#expect(node?.user?.longName == "Node \(num)")
			let observations = try context.fetch(FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == radioNum && $0.nodeNum == num }))
			#expect(observations.count == 1, "one observation of node \(num) by the radio")
		}
		try await manager.disconnect()
	}

	@Test("A blank timezone on the radio is filled in with the phone's")
	func blankTimezoneFilled() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), timezone: "")
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())
		try await waitUntil {
			await radio.sent.map(describe).contains { if case .setTimezone = $0 { return true } else { return false } }
		}

		let timezones = await radio.sent.map(describe).compactMap { item -> String? in
			if case .setTimezone(let tz) = item { return tz } else { return nil }
		}
		#expect(timezones == [TimeZone.current.posixDescription])
		try await manager.disconnect()
	}

	@Test("With canned messages on, the app asks the radio for them")
	func cannedMessagesRequested() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), cannedMessages: true)
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		#expect(await radio.sent.map(describe).contains(.cannedMessagesRequest))
		try await manager.disconnect()
	}

	@Test("A transport that needs heartbeats gets the periodic heartbeat and its response timeout")
	func periodicHeartbeat() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio, requiresPeriodicHeartbeat: true))
		try await manager.connect(to: device())

		let session = try #require(manager.activeConnection)
		#expect(session.heartbeatTimer != nil)
		#expect(session.heartbeatResponseTimer != nil, "firmware 2.7.4 and later answers heartbeats")
		try await manager.disconnect()
		#expect(session.heartbeatTimer == nil)
		#expect(session.heartbeatResponseTimer == nil)
	}

	@Test("An error from the link tears the connection down and keeps automatic reconnects on")
	func linkErrorTearsDown() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		await radio.emit(.error(AccessoryError.disconnected("Link lost")))
		try await waitUntil { manager.activeConnection == nil && manager.state == .discovering }

		#expect(manager.activeConnection == nil)
		#expect(!manager.isConnected)
		#expect(manager.state == .discovering)
		#expect(manager.lastConnectionError != nil)
		#expect(manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
	}

	@Test("A disconnect reported by the link tears down and turns automatic reconnects off")
	func linkDisconnectTearsDown() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		await radio.emit(.disconnected(shouldReconnect: false))
		try await waitUntil { manager.activeConnection == nil && manager.state == .discovering }

		#expect(manager.activeConnection == nil)
		#expect(manager.state == .discovering)
		#expect(!manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
	}

	@Test("A reboot while connected fetches the config again")
	func rebootRefreshesConfig() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())
		let before = await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count

		await radio.emit(.rebooted(true))
		try await waitUntil { await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count > before }

		#expect(await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count == before + 1)
		#expect(manager.isConnected)
		try await manager.disconnect()
	}
}
