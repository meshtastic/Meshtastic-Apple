import Foundation
import Testing
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

private actor RemoteActionConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true
	private(set) var sent: [ToRadio] = []

	func send(_ data: ToRadio) async throws { sent.append(data) }
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws { isConnected = false }
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("Remote admin action transport", .serialized)
struct RemoteAdminActionTransportTests {
	private struct Fixture {
		let manager: AccessoryManager
		let connection: RemoteActionConnection
		let from: UserEntity
		let to: UserEntity
		let container: ModelContainer
	}

	private func fixture() throws -> Fixture {
		let container = try ModelContainer(for: Schema(MeshtasticSchema.allModels), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = ModelContext(container)
		let localNode = NodeInfoEntity(); localNode.num = 7; localNode.id = 7
		let remoteNode = NodeInfoEntity(); remoteNode.num = 42; remoteNode.id = 42
		remoteNode.sessionPasskey = Data([0xA5, 0x5A]); remoteNode.sessionExpiration = .now.addingTimeInterval(300)
		let from = UserEntity(); from.num = 7; from.userNode = localNode
		let to = UserEntity(); to.num = 42; to.userNode = remoteNode
		context.insert(localNode); context.insert(remoteNode); context.insert(from); context.insert(to)
		try context.save()
		let connection = RemoteActionConnection()
		let manager = AccessoryManager(transports: [])
		manager.context = context
		manager.activeConnection = (device: Device(id: UUID(), name: "Test", transportType: .ble, identifier: "test", connectionState: .connected), connection: connection)
		manager.activeDeviceNum = 7
		manager.updateState(.subscribed)
		return Fixture(manager: manager, connection: connection, from: from, to: to, container: container)
	}

	private func guardTarget(connection: RemoteActionConnection, radio: Int64 = 7) -> RemoteAdminActionTarget {
		RemoteAdminActionTarget(nodeNum: 42, name: "Target", radioNum: radio, connectionID: ObjectIdentifier(connection))
	}

	private func admin(from toRadio: ToRadio) throws -> (MeshPacket, AdminMessage) {
		guard case .packet(let packet) = toRadio.payloadVariant else { throw AccessoryError.ioFailed("missing packet") }
		return (packet, try AdminMessage(serializedBytes: packet.decoded.payload))
	}

	@Test func guardRejectsExpiredSessionWithoutSending() async {
		let connection = RemoteActionConnection()
		var sends = 0
		let error = await RemoteAdminActionGuard.run(
			target: guardTarget(connection: connection), activeRadioNum: { 7 },
			activeConnectionID: { ObjectIdentifier(connection) }, isConnected: { true }, hasLiveSession: { false },
			action: { sends += 1 }
		)
		#expect(error?.contains("Session expired") == true); #expect(sends == 0)
	}

	@Test func guardRejectsDifferentConnectionOnSameRadioWithoutSending() async {
		let expected = RemoteActionConnection(); let active = RemoteActionConnection()
		var sends = 0
		let error = await RemoteAdminActionGuard.run(
			target: guardTarget(connection: expected), activeRadioNum: { 7 },
			activeConnectionID: { ObjectIdentifier(active) }, isConnected: { true }, hasLiveSession: { true },
			action: { sends += 1 }
		)
		#expect(error?.contains("Connection changed") == true); #expect(sends == 0)
	}

	@Test func guardAllowsLiveMatchingConnectionExactlyOnce() async {
		let connection = RemoteActionConnection(); var sends = 0
		let error = await RemoteAdminActionGuard.run(
			target: guardTarget(connection: connection), activeRadioNum: { 7 },
			activeConnectionID: { ObjectIdentifier(connection) }, isConnected: { true }, hasLiveSession: { true },
			action: { sends += 1 }
		)
		#expect(error == nil); #expect(sends == 1)
	}

	@Test func actionGuardReturnsAcknowledgementStatus() async {
		let connection = RemoteActionConnection()
		let result = await RemoteAdminActionGuard.runOutcome(
			target: guardTarget(connection: connection), activeRadioNum: { 7 },
			activeConnectionID: { ObjectIdentifier(connection) }, isConnected: { true }, hasLiveSession: { true },
			action: { .acknowledged }
		)
		#expect(result == .acknowledged)
	}

	@Test func actionTrackerResolvesRoutingAckAsAcknowledged() async throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = tracker.begin(kind: .action, targetNodeNum: 42, section: "reset")
		#expect(operationID != nil)
		let packetID: UInt32 = 123
		#expect(tracker.registerPacket(packetID: packetID, targetNodeNum: 42, operationID: operationID))
		let waitTask = Task {
			await tracker.waitForPacket(packetID: packetID, operationID: try #require(operationID), timeout: .seconds(1))
		}
		await Task.yield()
		tracker.resolveRouting(packetID: packetID, sourceNodeNum: 42, reason: nil, isFailure: false)
		#expect(try await waitTask.value == .acknowledged)
	}

	@Test func actionTrackerIgnoresRoutingAckFromRelay() async throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .action, targetNodeNum: 42, section: "reset"))
		let packetID: UInt32 = 124
		#expect(tracker.registerPacket(packetID: packetID, targetNodeNum: 42, operationID: operationID))
		#expect(tracker.resolveRouting(packetID: packetID, sourceNodeNum: 7, reason: nil, isFailure: false) == nil)
		#expect(await tracker.waitForPacket(packetID: packetID, operationID: operationID, timeout: .milliseconds(1)) == .unconfirmed)
	}

	@Test func actionTrackerPropagatesRoutingFailure() async throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .action, targetNodeNum: 42, section: "reset"))
		let packetID: UInt32 = 125
		#expect(tracker.registerPacket(packetID: packetID, targetNodeNum: 42, operationID: operationID))
		tracker.resolveRouting(packetID: packetID, sourceNodeNum: 42, reason: "No route", isFailure: true)
		#expect(await tracker.waitForPacket(packetID: packetID, operationID: operationID) == .failed("No route"))
	}

	@Test func actionTrackerTimesOutAsUnconfirmed() async {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try! #require(tracker.begin(kind: .action, targetNodeNum: 42, section: "reset"))
		let packetID: UInt32 = 456
		#expect(tracker.registerPacket(packetID: packetID, targetNodeNum: 42, operationID: operationID))
		let result = await tracker.waitForPacket(packetID: packetID, operationID: operationID, timeout: .milliseconds(1))
		#expect(result == .unconfirmed)
	}

	@Test func sendTimeUsesProductionTransportAndRemoteAuth() async throws {
		let fixture = try fixture()
		try await fixture.manager.sendTime(fromUser: fixture.from, toUser: fixture.to)
		let (packet, admin) = try admin(from: await fixture.connection.sent[0])
		#expect(packet.from == 7); #expect(packet.to == 42); #expect(admin.sessionPasskey == Data([0xA5, 0x5A]))
		#expect(admin.setTimeOnly > 0); #expect(packet.decoded.portnum == .adminApp)
	}

	@Test(arguments: [false, true]) func factoryResetModesReachRemote(resetDevice: Bool) async throws {
		let fixture = try fixture()
		let action = Task {
			try await fixture.manager.sendFactoryReset(fromUser: fixture.from, toUser: fixture.to, resetDevice: resetDevice)
		}
		while await fixture.connection.sent.isEmpty { await Task.yield() }
		let (sentPacket, _) = try admin(from: await fixture.connection.sent[0])
		fixture.manager.remoteAdminConfigTracker.resolveRouting(packetID: sentPacket.id, sourceNodeNum: Int64(sentPacket.to), reason: nil, isFailure: false)
		#expect(try await action.value == .acknowledged)
		let (packet, admin) = try admin(from: await fixture.connection.sent[0])
		#expect(packet.to == 42); #expect(admin.sessionPasskey == Data([0xA5, 0x5A]))
		#expect(resetDevice ? admin.factoryResetDevice == 5 : admin.factoryResetConfig == 5)
		#expect(resetDevice ? admin.factoryResetConfig == 0 : admin.factoryResetDevice == 0)
	}

	@Test(arguments: [false, true]) func nodeDBResetPreservesRequestedFavoriteMode(preserveFavorites: Bool) async throws {
		let fixture = try fixture()
		let context = ModelContext(fixture.container)
		let local = try #require(try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 7 })).first)
		local.favorite = true; try context.save()
		let action = Task {
			try await fixture.manager.sendNodeDBReset(fromUser: fixture.from, toUser: fixture.to, preserveFavorites: preserveFavorites)
		}
		while await fixture.connection.sent.isEmpty { await Task.yield() }
		let (sentPacket, _) = try admin(from: await fixture.connection.sent[0])
		fixture.manager.remoteAdminConfigTracker.resolveRouting(packetID: sentPacket.id, sourceNodeNum: Int64(sentPacket.to), reason: nil, isFailure: false)
		#expect(try await action.value == .acknowledged)
		let (packet, admin) = try admin(from: await fixture.connection.sent[0])
		#expect(packet.from == 7); #expect(packet.to == 42); #expect(admin.nodedbReset == preserveFavorites)
		let stillThere = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 7 })).first
		#expect(stillThere?.favorite == true)
		let targetStillTracked = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == 42 })).first
		#expect(targetStillTracked != nil)
	}
}
