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
		let radio: AdditionalRadio
		let connection: RecordingIdleConnection
	}

	/// A manager with a focused radio and one additional radio, B.
	private func makeFixture() -> Fixture {
		let manager = AccessoryManager(transports: [])
		manager.isSwitchingDevices = true
		var focused = Device(id: UUID(), name: "Focused", transportType: .tcp, identifier: "a.local:4403")
		focused.num = 0x0A0A
		manager.activeConnection = RadioSession(device: focused, connection: RecordingIdleConnection())
		let connection = RecordingIdleConnection()
		var extra = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		extra.num = extraNum
		let radio = AdditionalRadio(session: RadioSession(device: extra, connection: connection))
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
		store.entries[radio.id] = StoredPassphrase(passphrase: "hunter2", bootsRemaining: 3, validUntilEpoch: 0)

		manager.handleAdditionalLockdown(status(.locked), radio: radio, store: store)
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
		manager.handleAdditionalLockdown(status(.locked), radio: radio, store: store)
		try await waitUntil { await MainActor.run { manager.additionalRadios[radio.id] == nil } }
		#expect(manager.additionalRadios[radio.id] == nil)
		#expect(await connection.sent.count == 1)
	}

	@Test("A locked radio with no saved passphrase fails its connect with a reason, and isn't retried")
	func lockedWithoutPassphraseFailsTheHandshake() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio
		let handshake = Task { @MainActor in
			try await manager.requestHandshake(radio, nonce: 42, timeout: .seconds(30))
		}
		try await waitUntil { await MainActor.run { !radio.pendingNonces.isEmpty } }

		manager.handleAdditionalLockdown(status(.locked), radio: radio, store: InMemoryPassphraseStore())

		await #expect(throws: AdditionalRadioNeedsFocusError.self) {
			try await handshake.value
		}
		#expect(AdditionalRadioNeedsFocusError(radioName: "Extra", reason: .locked).errorDescription?.contains("Extra") == true)
	}

	@Test("Firmware below the minimum turns an additional radio away; unknown or newer firmware doesn't")
	func firmwareGate() throws {
		#expect(AccessoryManager.isFirmwareSupported(nil, minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("", minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("2.5.14", minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("2.7.15.567b8ea", minimum: "2.5.14"))
		#expect(!AccessoryManager.isFirmwareSupported("2.3.2.63df972", minimum: "2.5.14"))

		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio
		try manager.checkAdditionalRadioFirmware(radio)
		radio.session.device.firmwareVersion = "2.3.2.63df972"
		#expect(throws: AdditionalRadioNeedsFocusError(radioName: "Extra", reason: .firmwareTooOld(version: "2.3.2.63df972"))) {
			try manager.checkAdditionalRadioFirmware(radio)
		}
	}

	@Test("Unlocking mid-handshake asks for the same config again")
	func unlockResendsTheWaitingRequest() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection
		let handshake = Task { @MainActor in
			try await manager.requestHandshake(radio, nonce: 42, timeout: .seconds(30))
		}
		try await waitUntil { await connection.sent.count == 1 }

		manager.handleAdditionalLockdown(status(.unlocked), radio: radio, store: InMemoryPassphraseStore())
		try await waitUntil { await connection.sent.count == 2 }

		let requests = await connection.sent.map(\.wantConfigID)
		#expect(requests == [42, 42])
		manager.finishHandshake(radio, nonce: 42, error: nil)
		try await handshake.value
	}
}
