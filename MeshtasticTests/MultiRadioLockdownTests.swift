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

	@Test("A locked radio with a saved passphrase gets it once; still locked, it stays connected and prompts by name")
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
		#expect(radio.attention == nil, "nothing to ask while the saved passphrase is tried")

		// Still locked after that: the passphrase isn't sent again, and the user is asked.
		manager.handleAdditionalLockdown(status(.locked), session: radio, store: store)
		#expect(manager.additionalRadios[radio.device.id] === radio, "it stays connected")
		#expect(radio.attention == .unlockFailed)
		#expect(manager.radioAttentionPrompt == RadioAttentionPrompt(id: radio.device.id, radioName: "Extra", attention: .unlockFailed))
		#expect(await connection.sent.count == 1)
	}

	@Test("A locked radio with no saved passphrase connects, stays connected, and prompts by name")
	func lockedWithoutPassphraseStaysConnected() async throws {
		var locked = LockdownStatus()
		locked.state = .locked
		let scripted = ScriptedRadio(nodeNum: 0x5100_0001, afterConfig: [.lockdownStatus(locked)])
		let fixture = makeFixture(transports: [ScriptedTransport(radio: scripted)])
		let manager = fixture.manager
		let device = Device(id: UUID(), name: "Locked", transportType: .tcp, identifier: "locked.local:4403")

		try await manager.connectAdditionalRadio(device)

		let session = try #require(manager.additionalRadios[device.id])
		#expect(session.attention == .locked)
		#expect(session.lastLockdownStatus?.state == .locked)
		#expect(manager.radioAttentionPrompt?.id == device.id)
		#expect(manager.radioAttentionPrompt?.attention.title(radioName: "Scripted Radio") == "Scripted Radio is locked")
		#expect(await scripted.disconnects == 0)
		await manager.disconnectAdditionalRadio(device.id, byUser: true)
		#expect(manager.radioAttentionPrompt == nil, "a radio that's gone isn't asked about")
	}

	@Test("Focusing a locked radio shows its passphrase sheet, without reconnecting it")
	func focusingALockedRadioShowsTheSheet() async throws {
		var locked = LockdownStatus()
		locked.state = .locked
		let scripted = ScriptedRadio(nodeNum: 0x5100_0003, afterConfig: [.lockdownStatus(locked)])
		let fixture = makeFixture(transports: [ScriptedTransport(radio: scripted)])
		let manager = fixture.manager
		let coordinator = LockdownCoordinator(store: InMemoryPassphraseStore())
		manager.lockdownCoordinator = coordinator
		let device = Device(id: UUID(), name: "Locked", transportType: .tcp, identifier: "locked2.local:4403")
		try await manager.connectAdditionalRadio(device)

		#expect(await manager.focusConnectedRadio(device.id))

		#expect(manager.activeConnection?.device.id == device.id)
		#expect(coordinator.isBlockingSession, "the focused radio's passphrase sheet is up, for this radio")
		#expect(manager.radioAttentionPrompt == nil)
		#expect(manager.activeConnection?.attention == nil)
		#expect(await scripted.disconnects == 0)
	}

	@Test("Unlock while the locked radio is still connecting focuses it once connected, without disconnecting the focused radio")
	func unlockDuringConnectWaits() async throws {
		var locked = LockdownStatus()
		locked.state = .locked
		let scripted = ScriptedRadio(nodeNum: 0x5100_0005, afterConfig: [.lockdownStatus(locked)])
		let fixture = makeFixture(transports: [ScriptedTransport(radio: scripted)])
		let manager = fixture.manager
		manager.lockdownCoordinator = LockdownCoordinator(store: InMemoryPassphraseStore())
		let focusedConnection = try #require(manager.activeConnection?.connection as? RecordingIdleConnection)
		let device = Device(id: UUID(), name: "Locked", transportType: .tcp, identifier: "locked3.local:4403")

		let connect = Task { try await manager.connectAdditionalRadio(device) }
		try await waitUntil { await MainActor.run { manager.radioAttentionPrompt?.id == device.id } }
		let stillConnecting = manager.connectAttempts[device.id] != nil
		await manager.focusRadioNeedingAttention(device.id)
		if stillConnecting {
			#expect(manager.pendingAttentionFocus == device.id, "it waits for the connect")
		}
		try await connect.value

		#expect(manager.activeConnection?.device.id == device.id)
		#expect(manager.pendingAttentionFocus == nil)
		#expect(await focusedConnection.isConnected, "the previously focused radio isn't disconnected")
		#expect(await scripted.disconnects == 0)
	}

	@Test("A locked radio that loses the focus is still shown as locked and asked about")
	func lockedRadioLosingFocusKeepsItsPrompt() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager
		let focused = try #require(manager.activeConnection)
		focused.lastLockdownStatus = status(.locked)
		var ready = Device(id: UUID(), name: "Ready", transportType: .tcp, identifier: "ready.local:4403")
		ready.num = 0x0C0C
		ready.connectionState = .connected
		manager.additionalRadios[ready.id] = RadioSession(device: ready, connection: RecordingIdleConnection())

		#expect(await manager.focusConnectedRadio(ready.id))

		#expect(manager.additionalRadios[focused.device.id] === focused)
		#expect(focused.attention == .locked)
		#expect(manager.radioAttentionPrompt?.id == focused.device.id)
	}

	@Test("A second radio needing the user waits for the first radio's prompt to close")
	func promptsForSeveralRadiosQueue() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, first = fixture.radio
		var other = Device(id: UUID(), name: "Other", transportType: .tcp, identifier: "other.local:4403")
		other.num = 0x0D0D
		let second = RadioSession(device: other, connection: RecordingIdleConnection())
		manager.additionalRadios[other.id] = second

		manager.setAttention(.locked, for: first)
		manager.setAttention(.firmwareTooOld(version: "2.3.0"), for: second)
		#expect(manager.radioAttentionPrompt?.id == first.device.id, "the first prompt isn't replaced")
		#expect(manager.pendingAttentionPrompts.map(\.id) == [other.id])

		manager.radioAttentionPrompt = nil
		try await waitUntil { await MainActor.run { manager.radioAttentionPrompt != nil } }
		#expect(manager.radioAttentionPrompt?.id == other.id)
		#expect(manager.pendingAttentionPrompts.isEmpty)
	}

	@Test("Firmware below the minimum keeps a radio connected and prompts for an update")
	func firmwareGate() async throws {
		#expect(AccessoryManager.isFirmwareSupported(nil, minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("", minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("2.5.14", minimum: "2.5.14"))
		#expect(AccessoryManager.isFirmwareSupported("2.7.15.567b8ea", minimum: "2.5.14"))
		#expect(!AccessoryManager.isFirmwareSupported("2.3.2.63df972", minimum: "2.5.14"))

		let old = ScriptedRadio(nodeNum: 0x5100_0002, firmwareVersion: "2.3.2.63df972")
		let fixture = makeFixture(transports: [ScriptedTransport(radio: old)])
		let manager = fixture.manager
		#expect(manager.firmwareAttention(for: fixture.radio) == nil)
		let device = Device(id: UUID(), name: "Old", transportType: .tcp, identifier: "old.local:4403")

		try await manager.connectAdditionalRadio(device)

		let session = try #require(manager.additionalRadios[device.id])
		#expect(session.attention == .firmwareTooOld(version: "2.3.2.63df972"))
		#expect(manager.radioAttentionPrompt?.attention.actionTitle == "Update")
		#expect(!manager.firmwareUpdateRequired, "the focused radio's gate isn't raised for another radio")
	}

	@Test("Unlocking a connected radio clears its prompt and fetches its config again")
	func unlockRefreshesAConnectedRadio() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection
		manager.handleAdditionalLockdown(status(.locked), session: radio, store: InMemoryPassphraseStore())
		#expect(radio.attention == .locked)

		manager.handleAdditionalLockdown(status(.unlocked), session: radio, store: InMemoryPassphraseStore())
		try await waitUntil { await !connection.sent.isEmpty }

		#expect(radio.attention == nil)
		#expect(manager.radioAttentionPrompt == nil)
		#expect(await connection.sent.map(\.wantConfigID) == [69420])
		// Nothing answers this connection; end the waiting refresh.
		await manager.tearDown(radio)
	}
}
