//
//  MultiRadioLockdownTests.swift
//  MeshtasticTests
//
//  Feature 021, T065, T301: lock-down status from any connected radio, each on its own
//  coordinator.
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

/// A connection whose sends fail.
private actor FailingSendConnection: Connection {
	let type: TransportType = .tcp
	var isConnected = true
	func send(_ data: ToRadio) async throws { throw AccessoryError.ioFailed("Send failed") }
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
		let store: InMemoryPassphraseStore
	}

	/// A manager with a focused radio and one connected alongside it, B, whose saved passphrases
	/// are in `store`.
	private func makeFixture(transports: [any Transport] = []) -> Fixture {
		let manager = AccessoryManager(transports: transports)
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.appState = AppState(router: Router())
		var focused = Device(id: UUID(), name: "Focused", transportType: .tcp, identifier: "a.local:4403")
		focused.num = 0x0A0A
		let store = InMemoryPassphraseStore()
		manager.activeConnection = RadioSession(device: focused, connection: RecordingIdleConnection(), passphraseStore: store)
		let connection = RecordingIdleConnection()
		var extra = Device(id: UUID(), name: "Extra", transportType: .tcp, identifier: "b.local:4403")
		extra.num = extraNum
		let radio = RadioSession(device: extra, connection: connection, passphraseStore: store)
		manager.additionalRadios[extra.id] = radio
		return Fixture(manager: manager, radio: radio, connection: connection, store: store)
	}

	/// A lock-down status from `session`'s radio, as the event loop hands it on.
	private func deliver(_ status: LockdownStatus, to session: RadioSession, _ manager: AccessoryManager) {
		session.lockdown.handle(status)
		manager.lockdownStateChanged(session)
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

	@Test("A locked radio with a saved passphrase gets it; refused, it stays connected and prompts by name")
	func savedPassphraseIsSentOnce() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection
		let store = fixture.store
		store.entries[radio.device.id] = StoredPassphrase(passphrase: "hunter2", bootsRemaining: 3, validUntilEpoch: 0)

		deliver(status(.locked), to: radio, manager)
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

		// Refused: the saved passphrase is dropped, isn't sent again, and the user is asked.
		deliver(status(.unlockFailed), to: radio, manager)
		#expect(store.entries[radio.device.id] == nil)
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
		#expect(session.lockdown.isBlockingSession)
		#expect(manager.radioAttentionPrompt?.id == device.id)
		#expect(manager.radioAttentionPrompt?.attention.title(radioName: "Scripted Radio") == "Scripted Radio is locked")
		#expect(await scripted.disconnects == 0)
		await manager.disconnectAdditionalRadio(device.id, byUser: true)
		#expect(manager.radioAttentionPrompt == nil, "a radio that's gone isn't asked about")
	}

	@Test("A window showing a locked radio shows its passphrase sheet, without reconnecting it")
	func windowOfALockedRadioShowsTheSheet() async throws {
		var locked = LockdownStatus()
		locked.state = .locked
		let scripted = ScriptedRadio(nodeNum: 0x5100_0003, afterConfig: [.lockdownStatus(locked)])
		let fixture = makeFixture(transports: [ScriptedTransport(radio: scripted)])
		let manager = fixture.manager
		let device = Device(id: UUID(), name: "Locked", transportType: .tcp, identifier: "locked2.local:4403")
		try await manager.connectAdditionalRadio(device)

		// The window that shows it (the one window after Show This Radio, or its own on the Mac).
		let window = RadioWindow(deviceId: device.id)
		#expect(manager.session(for: window)?.lockdown.isBlockingSession == true, "the window's passphrase sheet is up, for this radio")
		#expect(manager.linkStatus(for: window).attention == .locked)
		#expect(await scripted.disconnects == 0)
	}

	@Test("A locked radio that's still connecting is asked about by name, and nothing else moves")
	func unlockDuringConnectOpensItsSheet() async throws {
		var locked = LockdownStatus()
		locked.state = .locked
		let scripted = ScriptedRadio(nodeNum: 0x5100_0005, afterConfig: [.lockdownStatus(locked)])
		let fixture = makeFixture(transports: [ScriptedTransport(radio: scripted)])
		let manager = fixture.manager
		let focused = try #require(manager.activeConnection)
		let focusedConnection = try #require(focused.connection as? RecordingIdleConnection)
		let device = Device(id: UUID(), name: "Locked", transportType: .tcp, identifier: "locked3.local:4403")

		let connect = Task { try await manager.connectAdditionalRadio(device) }
		try await waitUntil { await MainActor.run { manager.radioAttentionPrompt?.id == device.id } }
		#expect(manager.radioAttentionPrompt?.id == device.id)
		#expect(manager.activeConnection === focused)
		try await connect.value
		#expect(manager.activeConnection === focused)
		#expect(await focusedConnection.isConnected, "the focused radio isn't disconnected")
		#expect(await scripted.disconnects == 0)
	}

	@Test("A passphrase entered for a radio that isn't focused goes out on its connection, and is saved once it unlocks")
	func passphraseForARadioThatIsntFocused() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection
		let store = fixture.store
		deliver(status(.locked), to: radio, manager)
		#expect(radio.attention == .locked)
		// Its Unlock (the prompt's, or Connect's) opens its own sheet.
		manager.radioUnlockRequest = RadioUnlockRequest(id: radio.device.id, radioName: "Extra")

		#expect(radio.lockdown.canSend)
		radio.lockdown.submitPassphrase("hunter2", bootsRemaining: 5, validUntilEpoch: 0)
		#expect(radio.lockdown.isWaitingForAnswer, "its sheet stays up for the answer")
		try await waitUntil { await !connection.sent.isEmpty }

		let packet = try #require(await connection.sent.last?.packet)
		#expect(packet.to == UInt32(extraNum))
		let admin = try AdminMessage(serializedBytes: packet.decoded.payload)
		#expect(admin.lockdownAuth.passphrase == Data("hunter2".utf8))
		#expect(admin.lockdownAuth.bootsRemaining == 5)
		#expect(store.entries.isEmpty, "not saved before the radio accepts it")

		deliver(status(.unlocked), to: radio, manager)
		#expect(store.entries[radio.device.id]?.passphrase == "hunter2")
		#expect(radio.attention == nil)
		#expect(manager.radioUnlockRequest == nil)

		// A wrong one is never saved.
		store.entries.removeAll()
		deliver(status(.locked), to: radio, manager)
		radio.lockdown.submitPassphrase("wrong", bootsRemaining: 0, validUntilEpoch: 0)
		deliver(status(.unlockFailed), to: radio, manager)
		#expect(store.entries.isEmpty)
		#expect(radio.attention == .unlockFailed)
	}

	@Test("A rate-limited radio's sheet waits out the backoff, and a passphrase that can't be sent says so")
	func backoffAndFailedSend() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio
		var limited = status(.unlockFailed)
		limited.backoffSeconds = 30
		deliver(limited, to: radio, manager)

		guard case .unlockBackoff(let until) = radio.lockdown.state else {
			Issue.record("expected a backoff, got \(radio.lockdown.state)")
			return
		}
		#expect(until > Date().addingTimeInterval(25) && until <= Date().addingTimeInterval(30))
		#expect(radio.attention == .unlockFailed)
		deliver(status(.unlocked), to: radio, manager)
		#expect(!radio.lockdown.isBlockingSession)
		#expect(radio.attention == nil)

		// A passphrase that can't be sent brings the sheet back, saying so.
		var brokenDevice = Device(id: UUID(), name: "Broken", transportType: .tcp, identifier: "broken.local:4403")
		brokenDevice.num = 0x0E0E
		let broken = RadioSession(device: brokenDevice, connection: FailingSendConnection(), passphraseStore: fixture.store)
		manager.additionalRadios[brokenDevice.id] = broken
		deliver(status(.locked), to: broken, manager)
		broken.lockdown.submitPassphrase("hunter2", bootsRemaining: 0, validUntilEpoch: 0)
		try await waitUntil { await MainActor.run { broken.lockdown.sendError != nil } }
		#expect(broken.lockdown.sendError?.contains("Broken") == true)
		#expect(broken.lockdown.isBlockingSession)
	}

	@Test("Lock Now on a radio that isn't focused closes its connection once it locks, to be connected again")
	func lockNowOnARadioThatIsntFocused() async throws {
		let fixture = makeFixture()
		let manager = fixture.manager, radio = fixture.radio, connection = fixture.connection

		radio.lockdown.lockNow()
		try await waitUntil { await !connection.sent.isEmpty }
		let packet = try #require(await connection.sent.last?.packet)
		let admin = try AdminMessage(serializedBytes: packet.decoded.payload)
		#expect(admin.lockdownAuth.lockNow)

		deliver(status(.locked), to: radio, manager)
		#expect(radio.lockdown.state == .lockNowAcknowledged)
		try await waitUntil { await !connection.isConnected }
		#expect(await !connection.isConnected)
		#expect(radio.attention == nil, "nothing to ask: the user locked it")
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
		deliver(status(.locked), to: radio, manager)
		#expect(radio.attention == .locked)

		deliver(status(.unlocked), to: radio, manager)
		try await waitUntil { await !connection.sent.isEmpty }

		#expect(radio.attention == nil)
		#expect(manager.radioAttentionPrompt == nil)
		#expect(await connection.sent.map(\.wantConfigID) == [69420])
		// Nothing answers this connection; end the waiting refresh.
		await manager.tearDown(radio)
	}
}
