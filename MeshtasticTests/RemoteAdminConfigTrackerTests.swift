import Foundation
import Combine
import Testing
import SwiftData
@testable import Meshtastic
import MeshtasticProtobufs

private actor RemoteAdminReceiveConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true
	func send(_ data: ToRadio) async throws {}
	func connect() async throws -> AsyncStream<ConnectionEvent> { AsyncStream { $0.finish() } }
	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {}
	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@Suite("Remote admin configuration operation tracking")
@MainActor
struct RemoteAdminConfigTrackerTests {
	private func makeManager(connection: RemoteAdminReceiveConnection) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble, identifier: "remote-admin-test", connectionState: .connected, num: 1)
		manager.activeConnection = (device: device, connection: connection)
		manager.activeDeviceNum = 1
		manager.updateState(.subscribed)
		return manager
	}

	@Test func encodedAdminResponseResolvesThroughReceivePath() async throws {
		let connection = RemoteAdminReceiveConnection()
		let manager = makeManager(connection: connection)
		let operationID = try #require(manager.beginRemoteAdminConfigOperation(kind: .request, targetNodeNum: 42))
		#expect(manager.remoteAdminConfigTracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID))

		var admin = AdminMessage()
		admin.getModuleConfigResponse = ModuleConfig()
		var data = DataMessage()
		data.portnum = .adminApp
		data.requestID = 100
		data.payload = try admin.serializedData()
		var packet = MeshPacket()
		packet.from = 42
		packet.to = 1
		packet.decoded = data
		var fromRadio = FromRadio()
		fromRadio.packet = packet

		await manager.didReceive(.data(fromRadio))
		#expect(manager.remoteAdminConfigTracker.operations[operationID]?.pendingPacketIDs.isEmpty == true)
		#expect(manager.remoteAdminConfigTracker.finish(operationID) == .succeeded)
	}
	@Test func unrelatedPacketsCannotEnroll() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		#expect(!tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: nil))
		#expect(tracker.operations[operationID]?.pendingPacketIDs.isEmpty == true)
	}

	@Test func responseMustMatchPacketIDAndTarget() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		#expect(tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID))
		#expect(tracker.resolveAdminResponse(packetID: 101, sourceNodeNum: 42) == nil)
		#expect(tracker.resolveAdminResponse(packetID: 100, sourceNodeNum: 43) == nil)
		#expect(tracker.operations[operationID]?.result == nil)
	}

	@Test func targetResponseSucceeds() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .request, targetNodeNum: 42))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		#expect(tracker.resolveAdminResponse(packetID: 100, sourceNodeNum: 42) == operationID)
		#expect(tracker.finish(operationID) == .succeeded)
	}

	@Test func routingFailurePropagatesByPacketID() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		tracker.resolveRouting(packetID: 100, sourceNodeNum: 99, reason: "No route", isFailure: true)
		#expect(tracker.operations[operationID]?.result == .failed("No route"))
	}

	@Test func routingRejectionInvalidatesOnlyRejectedTargetSession() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = ModelContext(container)
		let rejectedTarget = NodeInfoEntity()
		rejectedTarget.num = 42
		rejectedTarget.sessionPasskey = Data([0xA5])
		rejectedTarget.sessionExpiration = Date().addingTimeInterval(300)
		let unaffectedTarget = NodeInfoEntity()
		unaffectedTarget.num = 99
		unaffectedTarget.sessionPasskey = Data([0x5A])
		unaffectedTarget.sessionExpiration = Date().addingTimeInterval(300)
		context.insert(rejectedTarget)
		context.insert(unaffectedTarget)
		try context.save()

		let connection = RemoteAdminReceiveConnection()
		let manager = makeManager(connection: connection)
		manager.context = context
		let operationID = try #require(manager.beginRemoteAdminConfigOperation(kind: .save, targetNodeNum: 42))
		#expect(manager.remoteAdminConfigTracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID))

		var routing = Routing()
		routing.errorReason = .adminBadSessionKey
		var data = DataMessage()
		data.portnum = .routingApp
		data.requestID = 100
		data.payload = try routing.serializedData()
		var packet = MeshPacket()
		packet.from = 1
		packet.to = 42
		packet.decoded = data
		var fromRadio = FromRadio()
		fromRadio.packet = packet

		await manager.didReceive(.data(fromRadio))

		#expect(rejectedTarget.sessionPasskey == nil)
		#expect(rejectedTarget.sessionExpiration == nil)
		#expect(unaffectedTarget.sessionPasskey == Data([0x5A]))
		#expect(unaffectedTarget.sessionExpiration != nil)
		#expect(manager.remoteAdminConfigTracker.operations[operationID]?.result == .failed("Remote node rejected the request: adminBadSessionKey"))
	}

	@Test func relaySuccessIsIgnoredUntilTargetConfirms() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		#expect(tracker.resolveRouting(packetID: 100, sourceNodeNum: 99, reason: nil, isFailure: false) == nil)
		#expect(tracker.resolveRouting(packetID: 100, sourceNodeNum: 42, reason: nil, isFailure: false) == operationID)
	}

	@Test func requestRequiresAdminResponseInsteadOfRoutingSuccess() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .request, targetNodeNum: 42, section: "Ambient Lighting"))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		#expect(tracker.resolveRouting(packetID: 100, sourceNodeNum: 42, reason: nil, isFailure: false) == nil)
		#expect(tracker.resolveAdminResponse(packetID: 100, sourceNodeNum: 42) == operationID)
	}

	@Test func multiPacketOperationWaitsForEveryPacket() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		tracker.registerPacket(packetID: 200, targetNodeNum: 42, operationID: operationID)
		tracker.resolveAdminResponse(packetID: 100, sourceNodeNum: 42)
		#expect(tracker.finish(operationID) == .timedOut)
		tracker.resolveAdminResponse(packetID: 200, sourceNodeNum: 42)
		#expect(tracker.finish(operationID) == .succeeded)
	}

	@Test func packetTimeoutIsRetainedAsTimeout() async throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		#expect(await tracker.waitForPacket(packetID: 100, operationID: operationID, timeout: .milliseconds(1)) == .timedOut)
		#expect(tracker.operations[operationID]?.result == .timedOut)
		#expect(tracker.operations[operationID]?.pendingPacketIDs.isEmpty == true)
	}

	@Test func duplicateSaveIsBlockedAndRetryGetsNewSequence() throws {
		let tracker = RemoteAdminConfigTracker()
		let first = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		#expect(tracker.begin(kind: .save, targetNodeNum: 42) == nil)
		tracker.fail(first, with: "failed")
		let retry = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		#expect(tracker.latest(for: 42, kind: .save, section: "save")?.id == retry)
	}

	@Test func requestStateIsScopedToConfigurationSection() throws {
		let tracker = RemoteAdminConfigTracker()
		let device = try #require(tracker.begin(kind: .request, targetNodeNum: 42, section: "Device"))
		let bluetooth = try #require(tracker.begin(kind: .request, targetNodeNum: 42, section: "Bluetooth"))
		#expect(tracker.latest(for: 42, kind: .request, section: "Device")?.id == device)
		#expect(tracker.latest(for: 42, kind: .request, section: "Bluetooth")?.id == bluetooth)
	}

	@Test func forcedRemoteConfigRetryDispatchesRequest() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = ModelContext(container)
		let local = NodeInfoEntity(); local.num = 1; local.id = 1
		let remote = NodeInfoEntity(); remote.num = 2; remote.id = 2
		let from = UserEntity(); from.num = 1; from.userNode = local
		let to = UserEntity(); to.num = 2; to.userNode = remote
		local.user = from; remote.user = to
		context.insert(local); context.insert(remote); context.insert(from); context.insert(to)
		try context.save()

		let manager = AccessoryManager(transports: [])
		manager.context = context
		manager.activeDeviceNum = 1
		manager.updateState(.subscribed)
		let previousAdministration = UserDefaults.enableAdministration
		UserDefaults.enableAdministration = true
		defer { UserDefaults.enableAdministration = previousAdministration }

		var requests = 0
		requestRemoteConfig(
			node: remote,
			context: context,
			accessoryManager: manager,
			configIsNil: { _ in false },
			section: "Retry test",
			request: { _, _ in requests += 1 },
			force: true)
		for _ in 0..<20 where requests == 0 {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(requests == 1)
	}

	@Test func managerPublishesNestedTrackerMutations() {
		let manager = AccessoryManager(transports: [])
		var changeCount = 0
		let cancellable = manager.objectWillChange.sink { _ in changeCount += 1 }
		_ = manager.remoteAdminConfigTracker.begin(kind: .request, targetNodeNum: 42, section: "Device")
		#expect(changeCount > 0)
		cancellable.cancel()
	}

	@Test func disconnectInvalidatesPendingPacketsAndLateAck() throws {
		let tracker = RemoteAdminConfigTracker()
		let operationID = try #require(tracker.begin(kind: .save, targetNodeNum: 42))
		tracker.registerPacket(packetID: 100, targetNodeNum: 42, operationID: operationID)
		tracker.failAll(with: "disconnected")
		#expect(tracker.resolveAdminResponse(packetID: 100, sourceNodeNum: 42) == nil)
		#expect(tracker.operations[operationID]?.result == .failed("disconnected"))
	}
}
