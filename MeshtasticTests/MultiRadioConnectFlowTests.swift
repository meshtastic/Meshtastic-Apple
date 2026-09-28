//
//  MultiRadioConnectFlowTests.swift
//  MeshtasticTests
//
//  Feature 021, D-17: a second radio runs the same connect steps as the focused one (T071), and
//  focus moves between connected radios without reconnecting (T072). Scripted radios as in
//  `ConnectFlowCharacterizationTests`.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@MainActor
@Suite("Connect flow with several radios", .serialized, .timeLimit(.minutes(1)))
struct MultiRadioConnectFlowTests {

	private typealias SavedDefaults = ConnectFlowSupport.SavedDefaults
	private func makeManager(_ transport: ScriptedTransport) -> AccessoryManager { ConnectFlowSupport.makeManager(transport) }
	private func uniqueNodeNum() -> UInt32 { ConnectFlowSupport.uniqueNodeNum() }
	private func waitUntil(_ condition: () async -> Bool) async throws { try await ConnectFlowSupport.waitUntil(condition) }
	private func device() -> Device { ConnectFlowSupport.device() }

	// MARK: - Every radio the same (D-17, T071)

	@Test("A radio connected alongside gets the same requests as the focused one, and stays second")
	func secondRadioRunsTheSameSteps() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let focusedNum = uniqueNodeNum()
		let secondNum = focusedNum &+ 0x100
		let focusedRadio = ScriptedRadio(nodeNum: focusedNum, dumpNodes: [focusedNum &+ 1])
		let secondRadio = ScriptedRadio(nodeNum: secondNum, dumpNodes: [secondNum &+ 1], timezone: "", cannedMessages: true)
		let secondDevice = device()
		let transport = ScriptedTransport(radio: focusedRadio, radiosByIdentifier: [secondDevice.identifier: secondRadio])
		let manager = makeManager(transport)
		let focusedDevice = device()

		try await manager.connect(to: focusedDevice)
		try await manager.connectAdditionalRadio(secondDevice)

		// The step requests, in order. The second radio's blank timezone adds a reply between them.
		func steps(_ items: [SentItem]) -> [SentItem] {
			Array(items.filter { [.heartbeat, .wantConfig(69420), .wantConfig(69421), .setTime].contains($0) }.prefix(5))
		}
		let expectedSteps: [SentItem] = [.heartbeat, .wantConfig(69420), .heartbeat, .wantConfig(69421), .setTime]
		#expect(steps(await focusedRadio.sent.map(describe)) == expectedSteps)
		#expect(steps(await secondRadio.sent.map(describe)) == expectedSteps, "the same steps as the focused radio")
		try await waitUntil { await secondRadio.sent.map(describe).contains(.cannedMessagesRequest) }
		#expect(await secondRadio.sent.map(describe).contains(.cannedMessagesRequest), "its own module config is handled like the focused radio's, on its own connection")
		#expect(!(await focusedRadio.sent.map(describe).contains(.cannedMessagesRequest)))
		try await waitUntil {
			await secondRadio.sent.map(describe).contains { if case .setTimezone = $0 { return true } else { return false } }
		}
		#expect(await secondRadio.sent.map(describe).contains { if case .setTimezone = $0 { return true } else { return false } })

		// Focus and the app-wide state stay with the first radio.
		#expect(manager.activeConnection?.device.id == focusedDevice.id)
		#expect(manager.activeDeviceNum == Int64(focusedNum))
		#expect(UserDefaults.preferredPeripheralId == focusedDevice.id.uuidString)
		#expect(UserDefaults.preferredPeripheralNum == Int(focusedNum))
		#expect(manager.state == .subscribed)

		// The second radio is connected, with its own session state, and remembered.
		let second = try #require(manager.additionalRadios[secondDevice.id])
		#expect(second.nodeNum == Int64(secondNum))
		#expect(second.device.connectionState == .connected)
		#expect(second.device.longName == "Scripted Radio")
		#expect(second.device.firmwareVersion == "2.7.15.567b8ea")
		#expect(second.eventTask != nil)
		#expect(manager.connectAttempts.isEmpty)
		let secondRadioNum = Int64(secondNum)
		let myInfo = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondRadioNum })).first
		#expect(myInfo?.peripheralId == secondDevice.id.uuidString)
		#expect(myInfo?.autoConnect == true)
		#expect(myInfo?.channels.count == 1)

		await manager.disconnectAdditionalRadio(secondDevice.id, byUser: true)
		#expect(manager.additionalRadios.isEmpty)
		#expect(second.eventTask == nil, "torn down like the focused radio's")
		#expect(await secondRadio.disconnects == 1)
		#expect(manager.activeConnection?.device.id == focusedDevice.id)
		try await manager.disconnect()
	}

	@Test("A radio connected alongside that fails to connect throws, and leaves the focused radio alone")
	func secondRadioFailureIsItsOwn() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let transport = ScriptedTransport(radio: ScriptedRadio(nodeNum: uniqueNodeNum()), failure: AccessoryError.connectionFailed("Refused"))
		let manager = makeManager(transport)
		let focused = ScriptedRadio(nodeNum: uniqueNodeNum())
		manager.activeConnection = RadioSession(device: device(), connection: focused)
		let refusing = device()

		await #expect(throws: (any Error).self) {
			try await manager.connectAdditionalRadio(refusing)
		}
		#expect(transport.connectAttempts == 2, "retried like the focused radio's connect")
		#expect(manager.additionalRadios.isEmpty)
		#expect(manager.connectAttempts.isEmpty)
		#expect(manager.activeConnection != nil)
		#expect(await focused.disconnects == 0)
		#expect(manager.lastConnectionError == nil, "the focused radio's error state is untouched")
	}

	// MARK: - Focus without reconnecting (T072)

	private struct TwoRadios {
		let manager: AccessoryManager
		let first: ScriptedRadio
		let second: ScriptedRadio
		let firstDevice: Device
		let secondDevice: Device
		let firstNum: UInt32
		let secondNum: UInt32
	}

	/// Radio A connected and focused, radio B connected alongside it.
	private func connectTwoRadios() async throws -> TwoRadios {
		let firstNum = uniqueNodeNum()
		let secondNum = firstNum &+ 0x200
		let first = ScriptedRadio(nodeNum: firstNum)
		let second = ScriptedRadio(nodeNum: secondNum, firmwareVersion: "2.7.9.1234567")
		let secondDevice = device()
		let manager = makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second]))
		let firstDevice = device()
		try await manager.connect(to: firstDevice)
		try await manager.connectAdditionalRadio(secondDevice)
		return TwoRadios(manager: manager, first: first, second: second, firstDevice: firstDevice, secondDevice: secondDevice, firstNum: firstNum, secondNum: secondNum)
	}

	@Test("Focusing a connected radio reconnects neither radio, and each radio's events stay its own")
	func focusWithoutReconnecting() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let firstSession = try #require(manager.activeConnection)
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])
		let firstRequests = await radios.first.sent.count
		let secondRequests = await radios.second.sent.count

		await switchToDevice(radios.secondDevice, accessoryManager: manager, appState: manager.appState)

		#expect(manager.activeConnection === secondSession)
		#expect(manager.additionalRadios[radios.firstDevice.id] === firstSession)
		#expect(manager.additionalRadios[radios.secondDevice.id] == nil)
		#expect(await radios.first.disconnects == 0)
		#expect(await radios.second.disconnects == 0)
		#expect(await radios.first.sent.count == firstRequests, "nothing is asked of the previous radio")
		#expect(await radios.second.sent.count == secondRequests, "no second connect for the new one")
		#expect(manager.activeDeviceNum == Int64(radios.secondNum))
		#expect(manager.state == .subscribed)
		#expect(manager.isConnected)
		#expect(UserDefaults.preferredPeripheralId == radios.secondDevice.id.uuidString)
		#expect(UserDefaults.preferredPeripheralNum == Int(radios.secondNum))
		#expect(manager.connectedVersion == "2.7.9.1234567")
		let previousNum = Int64(radios.firstNum)
		let previous = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == previousNum })).first
		#expect(previous?.autoConnect == true, "the previous radio comes back alongside next time")

		// An error from the previous radio now ends only that radio.
		await radios.first.emit(.error(AccessoryError.disconnected("Link lost")))
		try await waitUntil { manager.additionalRadios[radios.firstDevice.id] == nil }
		#expect(manager.additionalRadios[radios.firstDevice.id] == nil)
		#expect(manager.activeConnection === secondSession)
		#expect(await radios.second.disconnects == 0)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("Disconnect on the focused radio hands the focus over without reconnecting the other")
	func disconnectFocusedHandsOver() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])

		try await disconnectFocusedRadio(accessoryManager: manager)

		#expect(manager.activeConnection === secondSession)
		#expect(manager.additionalRadios.isEmpty)
		#expect(await radios.first.disconnects == 1)
		#expect(await radios.second.disconnects == 0)
		let firstNum = Int64(radios.firstNum)
		let first = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == firstNum })).first
		#expect(first?.autoConnect == false, "a radio the user disconnected isn't brought back")
		try await manager.disconnect()
	}

	@Test("Resetting the focused radio hands the focus over and brings the reset radio back alongside")
	func resetFocusedRadioHandsOver() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let firstSession = try #require(manager.activeConnection)
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])

		await manager.takeRadioOffline(Int64(radios.firstNum), reconnect: true)

		#expect(manager.activeConnection === secondSession)
		#expect(manager.additionalRadios[radios.firstDevice.id] == nil)
		#expect(await radios.first.disconnects == 1)
		#expect(await radios.second.disconnects == 0)
		#expect(manager.additionalRadioReconnects[radios.firstDevice.id] != nil, "a reset radio reboots and comes back")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("Removing a radio alongside disconnects only it, and it isn't brought back")
	func removeAdditionalRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let firstSession = try #require(manager.activeConnection)

		await manager.removeRadio(Int64(radios.secondNum))

		#expect(manager.activeConnection === firstSession)
		#expect(manager.additionalRadios.isEmpty)
		#expect(manager.additionalRadioReconnects.isEmpty)
		#expect(await radios.second.disconnects == 1)
		#expect(await radios.first.disconnects == 0)
		let secondNum = Int64(radios.secondNum)
		let second = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondNum }))
		#expect(second.isEmpty, "a removed radio is no longer one of the user's radios")
		try await manager.disconnect()
	}

	@Test("A radio that answers the node-DB request straight away doesn't stall the connect")
	func immediateNodeDBAnswer() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), replyDelay: .zero)
		let manager = makeManager(ScriptedTransport(radio: radio))
		let start = ContinuousClock.now

		try await manager.connect(to: device())

		#expect(manager.activeConnection != nil)
		// Missing the answer meant Step 5's 10 s timeout and a second request.
		#expect(ContinuousClock.now - start < .seconds(8))
		#expect(await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count == 1)
		try await manager.disconnect()
	}

	@Test("A second connect to a radio whose connect waits at the handshake gate is refused")
	func duplicateConnectRefused() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		let target = device()
		await manager.handshakeGate.acquire()

		let first = Task { try await manager.connect(to: target) }
		try await waitUntil { manager.connectAttempts[target.id] != nil }
		#expect(manager.hasFocusedConnectInProgress)
		#expect(manager.focusHandoverCandidate == nil)
		await #expect(throws: AccessoryError.self) { try await manager.connect(to: target) }

		manager.handshakeGate.release()
		try await first.value
		#expect(manager.activeConnection?.device.id == target.id)
		#expect(!manager.hasFocusedConnectInProgress)
		try await manager.disconnect()
	}

	@Test("When the focused radio drops, another connected radio takes the focus in place")
	func handoverWithoutReconnecting() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		manager.isSwitchingDevices = false
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])
		let dropped = try #require(manager.activeConnection)

		try await dropped.connection.disconnect(withError: nil, shouldReconnect: true)
		try await manager.closeConnection()
		manager.scheduleFocusHandover(previousRadio: Int64(radios.firstNum), previousDevice: dropped.device, after: .milliseconds(10))
		try await waitUntil { manager.activeConnection != nil && manager.additionalRadioReconnects[radios.firstDevice.id] != nil }

		#expect(manager.activeConnection === secondSession)
		#expect(await radios.second.disconnects == 0)
		#expect(await radios.second.sent.map(describe).filter { $0 == .wantConfig(69420) }.count == 1, "not connected again")
		#expect(manager.additionalRadioReconnects[radios.firstDevice.id] != nil, "the dropped radio is tried again")
		#expect(manager.locationTask != nil, "the phone's position keeps going to every radio")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.isSwitchingDevices = true
		try await manager.disconnect()
	}

	@Test("The preferred radio a BLE restore passed over takes the focus back when it rejoins")
	func displacedPreferredTakesFocusBack() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let restoredNum = uniqueNodeNum()
		let restored = ScriptedRadio(nodeNum: restoredNum)
		let preferred = ScriptedRadio(nodeNum: restoredNum &+ 0x200)
		let preferredDevice = device()
		let manager = makeManager(ScriptedTransport(radio: restored, radiosByIdentifier: [preferredDevice.identifier: preferred]))
		let restoredDevice = device()
		try await manager.connect(to: restoredDevice)
		let restoredSession = try #require(manager.activeConnection)

		await manager.noteRestoredAlongside(peripheralIds: [preferredDevice.id], displacedPreferred: preferredDevice.id)
		try await manager.connectAdditionalRadio(preferredDevice)

		#expect(manager.activeConnection?.device.id == preferredDevice.id)
		#expect(manager.additionalRadios[restoredDevice.id] === restoredSession, "the restored radio stays alongside")
		#expect(manager.restoreDisplacedPreferred == nil)
		#expect(await restored.disconnects == 0)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("The radio to connect first can differ from the focused one until a focus is chosen")
	func connectFirstOverride() async throws {
		let saved = SavedDefaults()
		defer {
			saved.restore()
			PreferredRadio.connectFirstOverride = nil
		}
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let elsewhere = UUID().uuidString

		PreferredRadio.connectFirstOverride = (elsewhere, 0x0E0E)
		#expect(PreferredRadio.connectFirstPeripheralId == elsewhere)
		#expect(PreferredRadio.peripheralId == radios.firstDevice.id.uuidString, "preferred stays the focused radio")

		#expect(await manager.focusConnectedRadio(radios.secondDevice.id))
		#expect(PreferredRadio.connectFirstOverride == nil)
		#expect(PreferredRadio.connectFirstPeripheralId == radios.secondDevice.id.uuidString)
		try await manager.disconnect()
	}

	@Test("The restore's give-back is dropped once the user picks a focus or disconnects that radio")
	func restoreGiveBackExpires() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let displaced = UUID()

		manager.restoreDisplacedPreferred = displaced
		#expect(await manager.focusConnectedRadio(radios.secondDevice.id))
		#expect(manager.restoreDisplacedPreferred == nil, "the user's focus wins")

		manager.restoreDisplacedPreferred = displaced
		await manager.disconnectAdditionalRadio(displaced, byUser: true)
		#expect(manager.restoreDisplacedPreferred == nil)
		try await manager.disconnect()
	}

	@Test("A radio that isn't connected can be removed, and stops being the preferred one")
	func removeOfflineRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: uniqueNodeNum())))
		let deadNum = Int64(uniqueNodeNum())
		let context = PersistenceController.shared.context
		let dead = MyInfoEntity()
		dead.myNodeNum = deadNum
		dead.lastConnected = .now
		context.insert(dead)
		try context.save()
		PreferredRadio.peripheralId = UUID().uuidString
		PreferredRadio.nodeNum = deadNum

		// It dropped earlier, so it has a reconnect loop and is waited for by discovery.
		let deadId = UUID()
		dead.peripheralId = deadId.uuidString
		try context.save()
		manager.scheduleAdditionalRadioReconnect(Device(id: deadId, name: "Dead", transportType: .tcp, identifier: "dead.local:4403", num: deadNum), firstDelay: .seconds(3600))
		manager.awaitedRememberedRadios.insert(deadId)

		await manager.removeRadio(deadNum)

		#expect(manager.additionalRadioReconnects[deadId] == nil, "it isn't brought back")
		#expect(!manager.awaitedRememberedRadios.contains(deadId))
		let fresh = ModelContext(PersistenceController.shared.container)
		#expect(try fresh.fetchCount(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == deadNum })) == 0)
		#expect(PreferredRadio.nodeNum == 0)
		#expect(PreferredRadio.peripheralId.isEmpty)
	}

	@Test("Old rows are attributed to the first radio when a second radio first connects")
	func backfillWhenSecondRadioJoins() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let firstNum = uniqueNodeNum()
		let first = ScriptedRadio(nodeNum: firstNum)
		let second = ScriptedRadio(nodeNum: firstNum &+ 0x200)
		let secondDevice = device()
		let manager = makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second]))
		try await manager.connect(to: device())
		// The store belongs to the first radio, as recorded at launch.
		BackfillOwner.clear()
		BackfillOwner.recordIfNeeded()
		defer { BackfillOwner.clear() }

		// A message stored by a build before feature 021: no radio columns yet.
		let context = PersistenceController.shared.context
		let old = MessageEntity()
		old.messageId = Int64.random(in: 1_000_000...9_000_000)
		old.messagePayload = "from before"
		context.insert(old)
		try context.save()
		let oldId = old.messageId
		defer {
			context.delete(old)
			try? context.save()
		}

		try await manager.connectAdditionalRadio(secondDevice)

		let fresh = ModelContext(PersistenceController.shared.container)
		let row = try #require(try fresh.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == oldId })).first)
		#expect(row.localNodeNum == Int64(firstNum))
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	/// A message stored by a build before feature 021, in the shared store; removed by the caller.
	private func insertOldMessage() throws -> MessageEntity {
		let context = PersistenceController.shared.context
		let old = MessageEntity()
		old.messageId = Int64.random(in: 1_000_000...9_000_000)
		old.messagePayload = "from before"
		context.insert(old)
		try context.save()
		return old
	}

	private func localNodeNum(ofMessage id: Int64) throws -> Int64? {
		let fresh = ModelContext(PersistenceController.shared.container)
		return try fresh.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == id })).first?.localNodeNum
	}

	@Test("Switching to another radio backfills old rows for the store's radio first, and its own radio doesn't wait")
	func backfillBeforeSwitchedRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		// The store's radio A, recorded at launch; the user switches to B, which is preferred now.
		let ownerNum = Int64(uniqueNodeNum())
		let ownerDevice = device()
		PreferredRadio.peripheralId = ownerDevice.id.uuidString
		PreferredRadio.nodeNum = ownerNum
		BackfillOwner.clear()
		BackfillOwner.recordIfNeeded()
		defer { BackfillOwner.clear() }
		let switched = device()
		PreferredRadio.peripheralId = switched.id.uuidString
		let old = try insertOldMessage()
		defer {
			PersistenceController.shared.context.delete(old)
			try? PersistenceController.shared.context.save()
		}

		// The store's own radio connecting, even from a new phone (another peripheral id):
		// nothing to wait for (T203).
		let ownerManager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: UInt32(ownerNum))))
		try await ownerManager.connect(to: device())
		#expect(try localNodeNum(ofMessage: old.messageId) == nil)
		try await ownerManager.disconnect()

		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: uniqueNodeNum())))
		try await manager.connect(to: switched)
		#expect(try localNodeNum(ofMessage: old.messageId) == ownerNum, "A's, not B's")
		try await manager.disconnect()
	}

	@Test("A failed reconnect of the dropped radio doesn't make the handover forget it")
	func handoverKeepsDroppedRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		manager.isSwitchingDevices = false
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])
		let dropped = try #require(manager.activeConnection)

		try await dropped.connection.disconnect(withError: nil, shouldReconnect: true)
		try await manager.closeConnection()
		manager.scheduleFocusHandover(previousRadio: Int64(radios.firstNum), previousDevice: dropped.device, after: .seconds(3600))
		// The dropped radio's own reconnect fails and closes again with nothing open.
		manager.scheduleFocusHandover(previousRadio: nil, previousDevice: nil, after: .milliseconds(10))
		#expect(manager.handoverPrevious?.device?.id == radios.firstDevice.id, "kept across the second close")
		try await waitUntil { manager.activeConnection != nil && manager.additionalRadioReconnects[radios.firstDevice.id] != nil }

		#expect(manager.activeConnection === secondSession)
		#expect(manager.additionalRadioReconnects[radios.firstDevice.id] != nil, "the dropped radio is still tried again")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.isSwitchingDevices = true
		try await manager.disconnect()
	}

	@Test("A radio removed while its focus handover waits isn't brought back by it")
	func removedDuringHandover() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		manager.isSwitchingDevices = false
		let dropped = try #require(manager.activeConnection)
		try await dropped.connection.disconnect(withError: nil, shouldReconnect: true)
		try await manager.closeConnection()
		manager.scheduleFocusHandover(previousRadio: Int64(radios.firstNum), previousDevice: dropped.device, after: .milliseconds(200))

		await manager.removeRadio(Int64(radios.firstNum))
		try await waitUntil { manager.activeConnection != nil && manager.focusHandoverTask == nil }
		try await Task.sleep(for: .milliseconds(100))

		#expect(manager.activeConnection?.device.id == radios.secondDevice.id)
		#expect(manager.additionalRadioReconnects[radios.firstDevice.id] == nil, "the removed radio isn't retried")
		manager.isSwitchingDevices = true
		try await manager.disconnect()
	}

	@Test("While the focused radio's live version is unknown, version checks use its own stored one")
	func versionCheckUsesTheFocusedRadiosOwnVersion() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		// A runs 2.7.15, B runs 2.7.9.
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let focused = try #require(manager.activeConnection)
		#expect(manager.checkIsVersionSupported(forVersion: "2.7.15"))

		// A reconnect window: the live version is briefly unknown.
		focused.device.firmwareVersion = nil
		#expect(manager.checkIsVersionSupported(forVersion: "2.7.15"), "A's own stored 2.7.15, not B's 2.7.9")
		#expect(!manager.checkIsVersionSupported(forVersion: "2.7.16"))
		try await manager.disconnect()
	}
}
