//
//  MultiRadioLockdownTests.swift
//  MeshtasticTests
//
//  Feature 021, T065: lock-down status from a radio connected alongside the focused one.
//

import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

/// A connection that records what it sends.
private actor RecordingIdleConnection: Connection {
	let type: TransportType = .tcp
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

private final class InMemoryPassphraseStore: LockdownPassphraseStoring {
	var entries: [UUID: StoredPassphrase] = [:]
	func get(peripheralID: UUID) -> StoredPassphrase? { entries[peripheralID] }
	func save(peripheralID: UUID, _ stored: StoredPassphrase) -> Bool { entries[peripheralID] = stored; return true }
	func delete(peripheralID: UUID) -> Bool { entries.removeValue(forKey: peripheralID) != nil }
}

@MainActor
@Suite("Multi-radio lock-down", .serialized, .timeLimit(.minutes(1)))
struct MultiRadioLockdownTests {

	private let extraNum: Int64 = 0x0B0B

	private struct Fixture {
		let manager: AccessoryManager
		let radio: RadioSession
		let connection: RecordingIdleConnection
	}

	/// A manager with a focused radio and one connected alongside it, B.
	private func makeFixture(transports: [any Transport] = []) -> Fixture {
		let manager = AccessoryManager(transports: transports)
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.appState = AppState(router: Router())
		var focused = Device(id: UUID(), name: "Focused", transportType: .tcp, identifier: "a.local:4403")
		focused.num = 0x0A0A
		manager.activeConnection = RadioSession(device: focused, connection: RecordingIdleConnection())
		let connection = RecordingIdleConnection()
		var extra = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		extra.num = extraNum
		let radio = RadioSession(device: extra, connection: connection)
		manager.additionalRadios[extra.id] = radio
		return Fixture(manager: manager, radio: radio, connection: connection)
	}

	private func status(_ state: LockdownStatus.State) -> LockdownStatus {
		var status = LockdownStatus()
		status.state = state
		return status
	}

	private func waitUntil(_ condition: () async -> Bool) async throws {
		var waited = 0
		while await !condition(), waited < 200 {
			try await Task.sleep(for: .milliseconds(10))
			waited += 1
		}
	}

	@Test("A locked radio with a saved passphrase gets it once, on its own connection")
	func savedPassphraseIsSentOnce() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection
		let store = InMemoryPassphraseStore()
		store.entries[radio.device.id] = StoredPassphrase(passphrase: "hunter2", bootsRemaining: 3, validUntilEpoch: 0)

		manager.handleAdditionalLockdown(status(.locked), session: radio, store: store)
		try await waitUntil { await !connection.sent.isEmpty }

		let sent = await connection.sent
		#expect(sent.count == 1)
		let packet = try #require(sent.first?.packet)
		#expect(packet.to == UInt32(extraNum))
		#expect(packet.from == 0)
		#expect(!packet.pkiEncrypted)
		let admin = try AdminMessage(serializedBytes: packet.decoded.payload)
		#expect(admin.lockdownAuth.passphrase == Data("hunter2".utf8))
		#expect(admin.lockdownAuth.bootsRemaining == 3)

		// Still locked after that: the passphrase isn't sent again, and the radio is dropped.
		manager.handleAdditionalLockdown(status(.locked), session: radio, store: store)
		try await waitUntil { await MainActor.run { manager.additionalRadios[radio.device.id] == nil } }
		#expect(manager.additionalRadios[radio.device.id] == nil)
		#expect(await connection.sent.count == 1)
	}

	@Test("A locked radio with no saved passphrase ends its connect with a reason, and isn't kept")
	func lockedWithoutPassphraseEndsTheConnect() async throws {
		var locked = LockdownStatus()
		locked.state = .locked
		let scripted = ScriptedRadio(nodeNum: 0x5100_0001, afterConfig: [.lockdownStatus(locked)])
		let fixture = makeFixture(transports: [ScriptedTransport(radio: scripted)])
		let manager = fixture.manager
		let device = Device(id: UUID(), name: "Locked", transportType: .tcp, identifier: "locked.local:4403")

		await #expect(throws: AdditionalRadioNeedsFocusError.self) {
			try await manager.connectAdditionalRadio(device)
		}
		#expect(manager.additionalRadios[device.id] == nil)
		#expect(manager.connectAttempts[device.id] == nil)
		#expect(await scripted.disconnects >= 1)
		#expect(AdditionalRadioNeedsFocusError(radioName: "Extra", reason: .locked).errorDescription?.contains("Extra") == true)
	}

	@Test("Firmware below the minimum turns a radio away; unknown or newer firmware doesn't")
	func firmwareGate() async throws {
		#expect(AccessoryManager.isFirmwareSupported(nil, minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("", minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("2.5.14", minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("2.7.15.567b8ea", minimum: "2.5.14"))
		#expect(!AccessoryManager.isFirmwareSupported("2.3.2.63df972", minimum: "2.5.14"))

		let old = ScriptedRadio(nodeNum: 0x5100_0002, firmwareVersion: "2.3.2.63df972")
		let fixture = makeFixture(transports: [ScriptedTransport(radio: old)])
		let manager = fixture.manager
		try manager.checkAdditionalRadioFirmware(fixture.radio)
		let device = Device(id: UUID(), name: "Old", transportType: .tcp, identifier: "old.local:4403")

		await #expect(throws: AdditionalRadioNeedsFocusError(radioName: "Scripted Radio", reason: .firmwareTooOld(version: "2.3.2.63df972"))) {
			try await manager.connectAdditionalRadio(device)
		}
		#expect(manager.additionalRadios[device.id] == nil)
	}

	@Test("Unlocking a connected radio fetches its config again")
	func unlockRefreshesAConnectedRadio() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection

		manager.handleAdditionalLockdown(status(.unlocked), session: radio, store: InMemoryPassphraseStore())
		try await waitUntil { await !connection.sent.isEmpty }

		#expect(await connection.sent.map(\.wantConfigID) == [69420])
		// Nothing answers this connection; end the waiting refresh.
		await manager.tearDown(radio)
	}
}
