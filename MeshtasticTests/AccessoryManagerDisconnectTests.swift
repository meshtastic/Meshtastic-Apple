//
//  AccessoryManagerDisconnectTests.swift
//  MeshtasticTests
//

// MARK: AccessoryManagerDisconnectTests

import Foundation
import SwiftData
import Testing

@testable import Meshtastic
import MeshtasticProtobufs

// MARK: - Test Doubles

private enum DisconnectTestError: Error {
	case transportFailure
}

private actor DisconnectTestConnection: Connection {
	typealias DisconnectCallback = @MainActor @Sendable () async -> Void

	let type: TransportType = .ble
	var isConnected = true
	private(set) var disconnectCallCount = 0
	private let disconnectError: DisconnectTestError?
	private var onDisconnect: DisconnectCallback?

	init(disconnectError: DisconnectTestError? = nil) {
		self.disconnectError = disconnectError
	}

	func setOnDisconnect(_ callback: @escaping DisconnectCallback) {
		onDisconnect = callback
	}

	func send(_ data: ToRadio) async throws {}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		AsyncStream { $0.finish() }
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		disconnectCallCount += 1
		isConnected = false
		await onDisconnect?()
		if let disconnectError {
			throw disconnectError
		}
	}

	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

// MARK: - Disconnect Lifecycle Tests

@MainActor
@Suite("AccessoryManager disconnect lifecycle", .serialized)
struct AccessoryManagerDisconnectTests {
	private func makeManager(connection: DisconnectTestConnection) -> AccessoryManager {
		let manager = AccessoryManager(transports: [])
		let device = Device(
			id: UUID(),
			name: "Test Radio",
			transportType: .ble,
			identifier: "test-radio",
			connectionState: .connected
		)
		manager.activeConnection = (device: device, connection: connection)
		manager.activeDeviceNum = 123
		manager.allowDisconnect = true
		// Keep closeConnection() from arming discovery for this transport-free fixture.
		manager.isSwitchingDevices = true
		manager.updateState(.subscribed)
		return manager
	}

	private func expectTornDown(_ manager: AccessoryManager, connection: DisconnectTestConnection) async {
		#expect(manager.activeConnection == nil)
		#expect(manager.activeDeviceNum == nil)
		#expect(manager.allowDisconnect == false)
		#expect(manager.isConnected == false)
		#expect(manager.state == .discovering)
		#expect(await connection.disconnectCallCount == 1)
	}

	@Test func waitsForManagerTeardown() async throws {
		let connection = DisconnectTestConnection()
		let manager = makeManager(connection: connection)

		try await manager.disconnect()

		await expectTornDown(manager, connection: connection)
	}

	@Test func tearsDownBeforePropagatingTransportError() async {
		let connection = DisconnectTestConnection(disconnectError: .transportFailure)
		let manager = makeManager(connection: connection)

		await #expect(throws: DisconnectTestError.transportFailure) {
			try await manager.disconnect()
		}

		await expectTornDown(manager, connection: connection)
	}

	@Test func ignoresMirroredDisconnectEventDuringTeardown() async throws {
		let connection = DisconnectTestConnection()
		let manager = makeManager(connection: connection)
		await connection.setOnDisconnect {
			await manager.didReceive(.disconnected(shouldReconnect: false))
		}

		try await manager.disconnect()

		await expectTornDown(manager, connection: connection)
		#expect(manager.packetsReceived == 1)
		#expect(manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
	}

	@Test func teardownInvalidatesAllRemoteAdminSessions() async throws {
		let connection = DisconnectTestConnection()
		let manager = makeManager(connection: connection)
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let context = ModelContext(container)
		let administeredNode = NodeInfoEntity()
		administeredNode.num = 101
		administeredNode.sessionPasskey = Data([0xA5, 0x5A])
		administeredNode.sessionExpiration = Date().addingTimeInterval(300)
		administeredNode.hasBeenAdministered = true
		let expirationOnlyNode = NodeInfoEntity()
		expirationOnlyNode.num = 202
		expirationOnlyNode.sessionExpiration = Date().addingTimeInterval(300)
		context.insert(administeredNode)
		context.insert(expirationOnlyNode)
		try context.save()
		manager.context = context

		try await manager.closeConnection()

		let nodes = try context.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(nodes.allSatisfy { $0.sessionPasskey == nil && $0.sessionExpiration == nil })
		#expect(nodes.first(where: { $0.num == 101 })?.hasBeenAdministered == true)
	}
}
