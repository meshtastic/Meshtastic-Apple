//
//  AccessoryManagerDisconnectTests.swift
//  MeshtasticTests
//

// MARK: AccessoryManagerDisconnectTests

import Foundation
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
	private(set) var disconnectReconnectValues: [Bool] = []
	private let disconnectError: DisconnectTestError?
	private var onDisconnect: DisconnectCallback?
	private var pausedConnect: CheckedContinuation<AsyncStream<ConnectionEvent>, Error>?
	private var pendingConnectFailure: DisconnectTestError?
	private var shouldPauseConnect = false
	private(set) var connectCallCount = 0

	init(disconnectError: DisconnectTestError? = nil) {
		self.disconnectError = disconnectError
	}

	func setOnDisconnect(_ callback: @escaping DisconnectCallback) {
		onDisconnect = callback
	}

	func pauseConnect() { shouldPauseConnect = true }
	func failPausedConnect() {
		if let pausedConnect {
			self.pausedConnect = nil
			pausedConnect.resume(throwing: DisconnectTestError.transportFailure)
		} else {
			pendingConnectFailure = .transportFailure
		}
	}

	func send(_ data: ToRadio) async throws {}

	func connect() async throws -> AsyncStream<ConnectionEvent> {
		connectCallCount += 1
		if let pendingConnectFailure {
			self.pendingConnectFailure = nil
			throw pendingConnectFailure
		}
		if shouldPauseConnect {
			return try await withCheckedThrowingContinuation { pausedConnect = $0 }
		}
		return AsyncStream { $0.finish() }
	}

	func disconnect(withError: Error?, shouldReconnect: Bool) async throws {
		disconnectCallCount += 1
		disconnectReconnectValues.append(shouldReconnect)
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

private struct DisconnectTestTransport: Transport {
	let type: TransportType = .ble
	var status: TransportStatus { get async { .ready } }
	let requiresPeriodicHeartbeat = false
	let supportsManualConnection = false
	func discoverDevices() async -> AsyncStream<DiscoveryEvent> { AsyncStream { $0.finish() } }
	func connect(to device: Device) async throws -> any Connection {
		throw AccessoryError.connectionFailed("Unexpected transport dial")
	}
	func device(forManualConnection: String) -> Device? { nil }
	func manuallyConnect(toDevice: Device) async throws {}
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

	@Test func closeConnectionDisconnectsTransportBeforeReturning() async throws {
		let connection = DisconnectTestConnection()
		let manager = makeManager(connection: connection)
		manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError = false
		await connection.setOnDisconnect {
			await manager.didReceive(.error(AccessoryError.eventStreamCancelled))
		}

		try await manager.closeConnection()

		#expect(manager.activeConnection == nil)
		#expect(manager.activeDeviceNum == nil)
		#expect(manager.allowDisconnect == false)
		#expect(await connection.disconnectCallCount == 1)
		#expect(await connection.disconnectReconnectValues == [false])
		#expect(manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError == false)
	}

	@Test func overlappingConnectDoesNotDialOrOrphanFirstConnection() async throws {
		let first = DisconnectTestConnection()
		await first.pauseConnect()
		let second = DisconnectTestConnection()
		let manager = AccessoryManager(transports: [DisconnectTestTransport()])
		manager.isSwitchingDevices = true
		let device = Device(id: UUID(), name: "Test Radio", transportType: .ble,
		                    identifier: "test-radio", connectionState: .disconnected)

		let firstAttempt = Task {
			try await manager.connect(to: device, withConnection: first,
				wantConfig: false, wantDatabase: false, versionCheck: false, retries: 1)
		}
		let deadline = ContinuousClock.now + .seconds(3)
		while await first.connectCallCount == 0 && ContinuousClock.now < deadline {
			try await Task.sleep(for: .milliseconds(10))
		}
		#expect(await first.connectCallCount == 1)
		await #expect(throws: AccessoryError.self) {
			try await manager.connect(to: device, withConnection: second,
					wantConfig: false, wantDatabase: false, versionCheck: false, retries: 1)
		}
		await first.failPausedConnect()
		try await firstAttempt.value

		#expect(await second.connectCallCount == 0)
		#expect(await first.isConnected == false)
		#expect(await first.disconnectCallCount == 1)
		#expect(await first.disconnectReconnectValues == [false])
		#expect(manager.activeConnection == nil)
	}
}
