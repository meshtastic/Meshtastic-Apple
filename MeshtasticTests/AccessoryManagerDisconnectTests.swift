//
//  AccessoryManagerDisconnectTests.swift
//  MeshtasticTests
//

import Foundation
import Testing

@testable import Meshtastic
import MeshtasticProtobufs

private actor DisconnectTestConnection: Connection {
	let type: TransportType = .ble
	var isConnected = true
	private(set) var disconnectCallCount = 0

	func send(_ data: ToRadio) async throws {}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		AsyncStream { _ in }
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		disconnectCallCount += 1
		isConnected = false
	}

	func drainPendingPackets() async throws {}
	func startDrainPendingPackets() throws {}
	func appDidEnterBackground() {}
	func appDidBecomeActive() {}
}

@MainActor
@Suite("AccessoryManager disconnect lifecycle", .serialized)
struct AccessoryManagerDisconnectTests {
	@Test func waitsForManagerTeardown() async throws {
		let connection = DisconnectTestConnection()
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
		manager.isSwitchingDevices = true
		manager.updateState(.subscribed)

		try await manager.disconnect()

		let disconnectCallCount = await connection.disconnectCallCount
		#expect(manager.activeConnection == nil)
		#expect(manager.activeDeviceNum == nil)
		#expect(manager.allowDisconnect == false)
		#expect(manager.isConnected == false)
		#expect(manager.state == .discovering)
		#expect(disconnectCallCount == 1)
	}
}
