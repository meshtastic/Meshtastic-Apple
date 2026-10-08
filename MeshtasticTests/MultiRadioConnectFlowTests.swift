//
//  MultiRadioConnectFlowTests.swift
//  MeshtasticTests
//
//  Feature 021, D-17: a second radio runs the same connect steps as the first one (T071), and
//  the window switches between connected radios without reconnecting (T072). Scripted radios as in
//  `ConnectFlowCharacterizationTests`.
//

import Combine
import Foundation
import MeshtasticProtobufs
import SwiftData
import SwiftUI
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

	@Test("A radio connected alongside gets the same requests as the first one, and stays second")
	func secondRadioRunsTheSameSteps() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let firstNum = uniqueNodeNum()
		let secondNum = firstNum &+ 0x100
		let firstRadio = ScriptedRadio(nodeNum: firstNum, dumpNodes: [firstNum &+ 1])
		let secondRadio = ScriptedRadio(nodeNum: secondNum, dumpNodes: [secondNum &+ 1], timezone: "", cannedMessages: true)
		let secondDevice = device()
		let transport = ScriptedTransport(radio: firstRadio, radiosByIdentifier: [secondDevice.identifier: secondRadio])
		let manager = makeManager(transport)
		let firstDevice = device()

		try await manager.connect(to: firstDevice)
		try await manager.connectAdditionalRadio(secondDevice)

		// The step requests, in order. The second radio's blank timezone adds a reply between them.
		func steps(_ items: [SentItem]) -> [SentItem] {
			Array(items.filter { [.heartbeat, .wantConfig(69420), .wantConfig(69421), .setTime].contains($0) }.prefix(5))
		}
		let expectedSteps: [SentItem] = [.heartbeat, .wantConfig(69420), .heartbeat, .wantConfig(69421), .setTime]
		#expect(steps(await firstRadio.sent.map(describe)) == expectedSteps)
		#expect(steps(await secondRadio.sent.map(describe)) == expectedSteps, "the same steps as the first radio")
		try await waitUntil { await secondRadio.sent.map(describe).contains(.cannedMessagesRequest) }
		#expect(await secondRadio.sent.map(describe).contains(.cannedMessagesRequest), "its own module config is handled like the first radio's, on its own connection")
		#expect(!(await firstRadio.sent.map(describe).contains(.cannedMessagesRequest)))
		try await waitUntil {
			await secondRadio.sent.map(describe).contains { if case .setTimezone = $0 { return true } else { return false } }
		}
		#expect(await secondRadio.sent.map(describe).contains { if case .setTimezone = $0 { return true } else { return false } })

		// The app-wide state stays with the first radio.
		#expect(manager.activeConnection?.device.id == firstDevice.id)
		#expect(manager.activeDeviceNum == Int64(firstNum))
		#expect(UserDefaults.preferredPeripheralId == firstDevice.id.uuidString)
		#expect(UserDefaults.preferredPeripheralNum == Int(firstNum))
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
		#expect(second.eventTask == nil, "torn down like the first radio's")
		#expect(await secondRadio.disconnects == 1)
		#expect(manager.activeConnection?.device.id == firstDevice.id)
		try await manager.disconnect()
	}

	@Test("Adding a radio keeps the other connected, and the one window shows the new radio")
	func addRadioKeepsTheOther() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let firstNum = uniqueNodeNum()
		let first = ScriptedRadio(nodeNum: firstNum)
		let second = ScriptedRadio(nodeNum: firstNum &+ 0x300)
		let secondDevice = device()
		let manager = makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second]))
		let firstDevice = device()
		try await manager.connect(to: firstDevice)

		try await manager.addRadio(secondDevice)

		#expect(manager.additionalRadios[secondDevice.id] != nil)
		#expect(manager.activeConnection?.device.id == firstDevice.id, "the other stays connected, and nothing moves")
		#expect(await first.disconnects == 0)
		// The window, set to show it (`selectWindowRadio`), shows it.
		#expect(manager.oneWindowRadio(stored: secondDevice.id) == RadioWindow(deviceId: secondDevice.id))
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("The one window shows the radio picked while it's around, else the radio the app connects first")
	func oneWindowRadioChoice() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager

		#expect(manager.oneWindowRadio(stored: nil) == .firstRadio, "one radio's users never pick: as before")
		#expect(manager.oneWindowRadio(stored: radios.firstDevice.id) == .firstRadio)
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == RadioWindow(deviceId: radios.secondDevice.id))
		#expect(manager.oneWindowRadio(stored: UUID()) == .firstRadio, "a radio that's gone")

		// Dropped, and being brought back: the window keeps it.
		manager.scheduleAdditionalRadioReconnect(radios.secondDevice)
		manager.additionalRadios.removeValue(forKey: radios.secondDevice.id)
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == RadioWindow(deviceId: radios.secondDevice.id))
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.additionalRadioReconnects.removeAll()
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == RadioWindow(deviceId: radios.secondDevice.id), "off and not coming back, it stays until the user picks another (W-02)")
		manager.knownNodeNums.removeValue(forKey: radios.secondDevice.id)
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == .firstRadio, "removed")
		try await manager.disconnect()
	}

	@Test("A radio connected alongside that fails to connect throws, and leaves the first radio alone")
	func secondRadioFailureIsItsOwn() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let transport = ScriptedTransport(radio: ScriptedRadio(nodeNum: uniqueNodeNum()), failure: AccessoryError.connectionFailed("Refused"))
		let manager = makeManager(transport)
		let first = ScriptedRadio(nodeNum: uniqueNodeNum())
		manager.activeConnection = RadioSession(device: device(), connection: first)
		let refusing = device()

		await #expect(throws: (any Error).self) {
			try await manager.connectAdditionalRadio(refusing)
		}
		#expect(transport.connectAttempts == 2, "retried like the first radio's connect")
		#expect(manager.additionalRadios.isEmpty)
		#expect(manager.connectAttempts.isEmpty)
		#expect(manager.activeConnection != nil)
		#expect(await first.disconnects == 0)
		#expect(manager.lastConnectionError == nil, "the first radio's error state is untouched")

		// Its window reads why it failed, until the user disconnects it (T300).
		let status = manager.linkStatus(of: refusing.id)
		#expect(status.lastError != nil)
		#expect(status.state == .idle)
		#expect(!status.canDisconnect)
		await manager.disconnectAdditionalRadio(refusing.id, byUser: true)
		#expect(manager.linkStatus(of: refusing.id).lastError == nil)
	}

	@Test("A window's radio finds its own session and number; the default window follows the first radio")
	func windowRadioLookups() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let first = RadioWindow(deviceId: radios.firstDevice.id)
		let second = RadioWindow(deviceId: radios.secondDevice.id)

		#expect(EnvironmentValues().windowRadio == .firstRadio)
		#expect(manager.session(for: .firstRadio) === manager.activeConnection)
		#expect(manager.nodeNum(for: .firstRadio) == manager.activeDeviceNum)
		#expect(manager.session(for: first) === manager.activeConnection)
		#expect(manager.session(for: second) === manager.additionalRadios[radios.secondDevice.id])
		#expect(manager.nodeNum(for: first) == Int64(radios.firstNum))
		#expect(manager.nodeNum(for: second) == Int64(radios.secondNum))
		#expect(manager.isConnected(second))
		#expect(!manager.isConnecting(second))
		#expect(manager.isConnecting(.firstRadio) == manager.isConnecting)
		#expect(manager.linkStatus(for: second).state == .subscribed)
		#expect(manager.radioNodeNum(for: .firstRadio) == PreferredRadio.nodeNum)
		#expect(manager.radioNodeNum(for: second) == Int64(radios.secondNum))
		#expect(manager.radioPeripheralId(for: .firstRadio) == PreferredRadio.peripheralId)
		#expect(manager.radioPeripheralId(for: second) == radios.secondDevice.id.uuidString)
		#expect(manager.firmwareVersion(for: second) == manager.additionalRadios[radios.secondDevice.id]?.device.firmwareVersion)
		#expect(manager.firmwareVersion(for: second) != nil)
		#expect(manager.lastConfigRefresh(for: .firstRadio) == manager.lastConfigRefresh)
		#expect(manager.lastConfigRefresh(for: second) != nil, "its own config's arrival")
		#expect(manager.isVersionSupported(forVersion: "2.5.0", for: second))
		#expect(!manager.isVersionSupported(forVersion: "9.0.0", for: second), "its own firmware, 2.7.15")

		// Connected and connecting count as the manager's flags do.
		#expect(RadioLinkStatus(state: .retrievingDatabase(nodeCount: 3), canDisconnect: true).isConnected)
		#expect(RadioLinkStatus(state: .retrying(attempt: 2, maxAttempts: 3), canDisconnect: true).isConnecting)
		#expect(!RadioLinkStatus(state: .idle, canDisconnect: false).isConnected)

		#expect(manager.sendingRadio(for: .firstRadio) == nil, "the one window sends as before")
		#expect(manager.sendingRadio(for: second) == Int64(radios.secondNum))
		#expect(manager.otherConnectedRadios(than: second).map(\.id) == [radios.firstDevice.id], "B's Settings names A, not B")
		#expect(manager.otherConnectedRadios(than: .firstRadio).map(\.id) == [radios.secondDevice.id])

		let gone = RadioWindow(deviceId: UUID())
		#expect(manager.session(for: gone) == nil)
		#expect(manager.sendingRadio(for: gone) != nil, "a window's send never falls back to another radio")
		#expect(manager.nodeNum(for: gone) == nil)
		#expect(!manager.isConnected(gone))
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("Disconnecting a radio, the first or another, says so, so its window learns it was the user")
	func disconnectRadioSaysSo() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		var disconnected: [UUID] = []
		let subscription = manager.radioDisconnectedByUser.sink { disconnected.append($0) }
		defer { subscription.cancel() }

		await manager.disconnectRadio(radios.secondDevice.id)
		#expect(disconnected == [radios.secondDevice.id])
		#expect(manager.additionalRadios[radios.secondDevice.id] == nil)

		await manager.disconnectRadio(radios.firstDevice.id)
		#expect(disconnected == [radios.secondDevice.id, radios.firstDevice.id])
		#expect(manager.activeConnection == nil)
	}

	@Test("With the first radio gone, radios join the others and don't take its place")
	func joinWhileFirstIsGone() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let firstNum = uniqueNodeNum()
		let first = ScriptedRadio(nodeNum: firstNum)
		let second = ScriptedRadio(nodeNum: firstNum &+ 0x400)
		let third = ScriptedRadio(nodeNum: firstNum &+ 0x500)
		let secondDevice = device(), thirdDevice = device()
		let manager = makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second, thirdDevice.identifier: third]))
		let firstDevice = device()
		try await manager.connect(to: firstDevice)
		try await manager.connectAdditionalRadio(secondDevice)
		// The first radio drops; the second stays (D-19).
		try await manager.closeConnection()
		#expect(manager.activeConnection == nil)

		// Added now, the third joins the second (W3) ...
		try await manager.addRadio(thirdDevice)
		#expect(manager.additionalRadios[thirdDevice.id] != nil)
		#expect(manager.activeConnection == nil, "it doesn't take the first radio's place")
		#expect(PreferredRadio.peripheralId == firstDevice.id.uuidString, "the first stays the preferred radio")

		// ... and a radio alongside that drops is brought back while the first is still gone (W2).
		await manager.disconnectAdditionalRadio(secondDevice.id)
		manager.scheduleAdditionalRadioReconnect(secondDevice)
		manager.radioSeen(secondDevice.id)
		try await waitUntil { manager.additionalRadios[secondDevice.id] != nil && manager.connectAttempts[secondDevice.id] == nil }
		#expect(manager.additionalRadios[secondDevice.id] != nil, "connected, its connect finished")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		await manager.disconnectRadio(secondDevice.id)
		await manager.disconnectRadio(thirdDevice.id)
	}

	/// Lets a test's manager start discovery, as the app's does, and stops it afterwards.
	private func allowDiscovery(_ manager: AccessoryManager) {
		manager.isSwitchingDevices = false
	}

	private func endDiscovery(_ manager: AccessoryManager) {
		manager.isSwitchingDevices = true
		manager.rememberedRadioFallbackTask?.cancel()
		manager.stopDiscovery()
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
	}

	@Test("After Disconnect on the first radio, the radio kept connected comes back as the first radio when it drops, once it's seen")
	func keptRadioComesBackAsFirst() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		try await disconnectFirstRadio(accessoryManager: manager)
		// B drops, not by the user: no radio is left for it to join.
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		#expect(manager.connectedRadioCount == 0)
		allowDiscovery(manager)

		// Not seen by discovery: its loop doesn't connect it blind.
		manager.scheduleAdditionalRadioReconnect(radios.secondDevice)
		try await Task.sleep(for: .milliseconds(300))
		#expect(manager.activeConnection == nil)
		#expect(manager.additionalRadioReconnects[radios.secondDevice.id] != nil, "still waiting for it")

		// Seen: back as the first radio.
		manager.radioSeen(radios.secondDevice.id)
		try await waitUntil { manager.activeConnection?.device.id == radios.secondDevice.id && manager.connectAttempts[radios.secondDevice.id] == nil }
		#expect(manager.activeConnection?.device.id == radios.secondDevice.id, "connected, its connect finished")
		#expect(manager.isConnected)
		#expect(PreferredRadio.peripheralId == radios.secondDevice.id.uuidString)
		let firstNum = Int64(radios.firstNum)
		let first = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == firstNum })).first
		#expect(first?.autoConnect == false, "the radio the user disconnected stays off")
		#expect(manager.additionalRadioReconnects[radios.secondDevice.id] == nil, "its loop is done once it's connected")

		// Disconnected now by the user, it stays off though discovery sees it again (review V14 P1).
		try await disconnectFirstRadio(accessoryManager: manager)
		manager.radioSeen(radios.secondDevice.id)
		try await Task.sleep(for: .milliseconds(300))
		#expect(manager.activeConnection == nil)
		endDiscovery(manager)
	}

	@Test("Removing a radio that isn't connected cancels a connect of it as the first radio")
	func removeCancelsAConnectAsFirst() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let num = uniqueNodeNum()
		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: num)))
		var dropped = device()
		dropped.num = Int64(num)
		// Its connect as the first radio waits at the handshake gate, before Step 1.
		await manager.handshakeGate.acquire()
		let connecting = Task { try await manager.connect(to: dropped) }
		try await waitUntil { manager.connectAttempts[dropped.id] != nil }
		#expect(manager.connectAttempts[dropped.id]?.isFirst == true)

		await manager.stopBringingBack(Int64(num))
		manager.handshakeGate.release()
		_ = try? await connecting.value
		#expect(manager.activeConnection == nil, "it doesn't connect once the gate opens")
	}

	/// A, the preferred radio, dropped (not by the user), then B; B's connect as the first radio in
	/// A's place waits at the handshake gate, as if it had got as far as recording itself as the
	/// preferred radio. The caller releases the gate and awaits the task.
	private func standInAtTheGate() async throws -> (radios: TwoRadios, standIn: Task<Void, Never>) {
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		try await manager.closeConnection()
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		#expect(!manager.userRequestedConnectionCancellation)
		allowDiscovery(manager)
		await manager.handshakeGate.acquire()
		let standIn = Task { await manager.connectAsFirst(radios.secondDevice) }
		try await waitUntil { manager.connectAttempts[radios.secondDevice.id] != nil }
		PreferredRadio.set(radios.secondDevice)
		return (radios, standIn)
	}

	@Test("Cancelling a radio connecting in the dropped preferred radio's place leaves the preferred radio to come back")
	func cancelledStandInLeavesThePreferredRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let (radios, standIn) = try await standInAtTheGate()
		let manager = radios.manager

		// The user disconnects B while it connects.
		await manager.disconnectRadio(radios.secondDevice.id)
		manager.handshakeGate.release()
		await standIn.value
		#expect(manager.activeConnection == nil)
		#expect(PreferredRadio.peripheralId == radios.firstDevice.id.uuidString, "A is still the preferred radio")
		#expect(!manager.userRequestedConnectionCancellation, "so discovery brings A back")
		#expect(manager.standInConnect == nil)
		// Disconnected before its connect knew its number, B isn't brought back at the next launch
		// either (review V17 U2).
		let secondNum = Int64(radios.secondNum)
		let second = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondNum })).first
		#expect(second?.autoConnect == false)
		endDiscovery(manager)
	}

	@Test("Removing the stand-in from Device Config while it downloads leaves the preferred radio to come back")
	func removeStandInWhileItDownloads() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let firstNum = uniqueNodeNum(), standInNum = firstNum &+ 0x600
		// B never answers the config request, so its connect stays in progress past Step 1.
		var standInDevice = device()
		standInDevice.num = Int64(standInNum)
		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: firstNum), radiosByIdentifier: [standInDevice.identifier: ScriptedRadio(nodeNum: standInNum, answersConfig: false)]))
		let firstDevice = device()
		try await manager.connect(to: firstDevice)
		// A, the preferred radio, drops (not the user).
		try await manager.closeConnection()
		#expect(PreferredRadio.peripheralId == firstDevice.id.uuidString)
		allowDiscovery(manager)

		let standIn = Task { await manager.connectAsFirst(standInDevice) }
		try await waitUntil { manager.activeConnection?.device.id == standInDevice.id }
		#expect(manager.connectAttempts[standInDevice.id] != nil, "still connecting")
		PreferredRadio.set(standInDevice)

		await manager.removeRadio(Int64(standInNum))
		await standIn.value
		#expect(manager.activeConnection == nil)
		#expect(PreferredRadio.peripheralId == firstDevice.id.uuidString, "A is still the preferred radio")
		#expect(!manager.userRequestedConnectionCancellation, "so discovery brings A back")
		endDiscovery(manager)
	}
}

// MARK: - Dropped radios, reconnect loops and updates

extension MultiRadioConnectFlowTests {
	@Test("Disconnect on a radio alongside that isn't connected turns off its reconnect at the next launch")
	func disconnectDroppedRadioForgetsIt() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		// B drops: it stays remembered, to come back.
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		let secondNum = Int64(radios.secondNum)
		let context = PersistenceController.shared.context
		#expect(try context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondNum })).first?.autoConnect == true)

		await manager.disconnectRadio(radios.secondDevice.id)
		#expect(try context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondNum })).first?.autoConnect == false)
		try await manager.disconnect()
	}

	@Test("Clear App Data or a restore during a stand-in's connect leaves nothing to reconnect, as on main")
	func resetDuringAStandInKeepsTheFlag() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let (radios, standIn) = try await standInAtTheGate()
		let manager = radios.manager

		// What Clear App Data and Restore Backup do.
		await manager.disconnectAllAdditionalRadios()
		try await manager.disconnect()
		manager.handshakeGate.release()
		await standIn.value
		#expect(manager.activeConnection == nil)
		#expect(manager.userRequestedConnectionCancellation, "discovery doesn't reconnect into the store")
		endDiscovery(manager)
	}

	@Test("A preferred radio handed on during a stand-in's connect isn't put back by its Disconnect")
	func handedOnPreferredRadioStays() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let (radios, standIn) = try await standInAtTheGate()
		let manager = radios.manager
		// Meanwhile the preference went to another radio (A removed, say).
		let other = UUID().uuidString
		PreferredRadio.peripheralId = other

		await manager.disconnectRadio(radios.secondDevice.id)
		manager.handshakeGate.release()
		await standIn.value
		#expect(PreferredRadio.peripheralId == other)
		#expect(manager.userRequestedConnectionCancellation, "nothing auto-connects, as after any Disconnect")
		endDiscovery(manager)
	}

	@Test("Disconnect stops a reconnect loop of the radio it disconnects")
	func disconnectStopsItsLoop() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: uniqueNodeNum())))
		let only = device()
		try await manager.connect(to: only)
		manager.scheduleAdditionalRadioReconnect(only)
		try await disconnectFirstRadio(accessoryManager: manager)
		#expect(manager.additionalRadioReconnects[only.id] == nil)
	}

	@Test("A reconnect loop that's replaced doesn't remove the new loop when it ends")
	func replacedLoopKeepsTheNewOne() async throws {
		let manager = AccessoryManager(transports: [])
		let dropped = device()
		manager.scheduleAdditionalRadioReconnect(dropped)
		manager.additionalRadioReconnects.removeValue(forKey: dropped.id)?.cancel()
		manager.scheduleAdditionalRadioReconnect(dropped)
		try await Task.sleep(for: .milliseconds(200))
		#expect(manager.additionalRadioReconnects[dropped.id] != nil)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
	}

	@Test("With the first radio dropped, the other radio dropping comes back as the first radio, and the first is remembered to join it")
	func lastRadioComesBackAsFirst() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		// The first radio drops (not the user), then the other one.
		try await manager.closeConnection()
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		#expect(manager.connectedRadioCount == 0)
		allowDiscovery(manager)
		manager.devices = [radios.secondDevice]

		manager.scheduleAdditionalRadioReconnect(radios.secondDevice)
		try await waitUntil { manager.activeConnection?.device.id == radios.secondDevice.id && manager.connectAttempts[radios.secondDevice.id] == nil }
		#expect(manager.activeConnection?.device.id == radios.secondDevice.id, "connected, its connect finished")
		#expect(manager.isConnected)
		let firstNum = Int64(radios.firstNum)
		let first = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == firstNum })).first
		#expect(first?.autoConnect == true, "the first radio joins when it's back, as the fallback has it")
		endDiscovery(manager)
		for deviceId in Array(manager.additionalRadios.keys) {
			await manager.disconnectRadio(deviceId)
		}
		try await manager.disconnect()
	}

	@Test("A radio that dropped comes back as the first radio after the user disconnected the first one, which stays off")
	func droppedRadioComesBackWithoutTheDisconnectedOne() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		// B drops first; then the user disconnects A, the preferred radio, with nothing else connected.
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		try await disconnectFirstRadio(accessoryManager: manager)
		#expect(PreferredRadio.peripheralId == radios.firstDevice.id.uuidString, "no other radio was connected to take it")
		allowDiscovery(manager)
		manager.devices = [radios.secondDevice]

		manager.scheduleAdditionalRadioReconnect(radios.secondDevice)
		try await waitUntil { manager.activeConnection?.device.id == radios.secondDevice.id && manager.connectAttempts[radios.secondDevice.id] == nil }
		#expect(manager.activeConnection?.device.id == radios.secondDevice.id, "connected, its connect finished")
		#expect(manager.isConnected)
		let firstNum = Int64(radios.firstNum)
		let first = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == firstNum })).first
		#expect(first?.autoConnect == false, "not remembered: the user disconnected it")
		endDiscovery(manager)
		try await manager.disconnect()
	}

	@Test("Disconnecting every radio alongside, for Clear App Data or a restore, also stops the ones being brought back")
	func disconnectAllStopsTheDropped() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		// B dropped and is being brought back; another radio is waited for by discovery.
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		manager.scheduleAdditionalRadioReconnect(radios.secondDevice)
		let awaited = UUID()
		manager.awaitedRememberedRadios.insert(awaited)

		await manager.disconnectAllAdditionalRadios()
		#expect(manager.additionalRadioReconnects.isEmpty)
		#expect(manager.awaitedRememberedRadios.isEmpty)
		try await manager.disconnect()
	}

	@Test("A dropped radio waits rather than taking the first place during a switch, an OTA, an update of the first radio, a store reset, or with another radio connected")
	func droppedRadioWaitsWhenItShould() {
		let manager = AccessoryManager(transports: [])
		let dropped = device()
		#expect(manager.mayConnectAsFirst(dropped))
		manager.isSwitchingDevices = true
		#expect(!manager.mayConnectAsFirst(dropped))
		manager.isSwitchingDevices = false
		manager.otaInProgress = true
		#expect(!manager.mayConnectAsFirst(dropped))
		manager.otaInProgress = false
		manager.firstRadioReleasedForUpdate = true
		#expect(!manager.mayConnectAsFirst(dropped))
		manager.firstRadioReleasedForUpdate = false
		manager.appState = AppState()
		manager.appState.isDatabaseResetting = true
		#expect(!manager.mayConnectAsFirst(dropped), "not while the store is replaced")
		manager.appState.isDatabaseResetting = false
		#expect(manager.mayConnectAsFirst(dropped))
		var other = device()
		other.num = 0x0A0A
		manager.additionalRadios[other.id] = RadioSession(device: other, connection: ScriptedRadio(nodeNum: 0x0A0A))
		#expect(!manager.mayConnectAsFirst(dropped), "it joins the connected radio instead")
	}

	@Test("A window whose radio is off still knows which radio it is, and sends through it")
	func windowKeepsItsRadioWhileOff() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let second = RadioWindow(deviceId: radios.secondDevice.id)

		await manager.disconnectRadio(radios.secondDevice.id)
		#expect(manager.session(for: second) == nil)

		#expect(manager.radioNodeNum(for: second) == Int64(radios.secondNum), "Settings keeps its radio")
		#expect(manager.sendingRadio(for: second) == Int64(radios.secondNum), "a send fails rather than using the other radio")
		#expect(!manager.isVersionSupported(forVersion: "9.0.0", for: second), "its own firmware, not the other radio's")
		#expect(manager.isVersionSupported(forVersion: "2.5.0", for: second))
		try await manager.disconnect()
	}

	@Test("A firmware update releases only its radio, keeps its window, and brings it back")
	func releaseForUpdate() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		var disconnected: [UUID] = []
		let subscription = manager.radioDisconnectedByUser.sink { disconnected.append($0) }
		defer { subscription.cancel() }
		let firstSession = try #require(manager.activeConnection)

		try await manager.releaseRadioForUpdate(radios.secondDevice.id)
		#expect(manager.additionalRadios[radios.secondDevice.id] == nil)
		#expect(manager.activeConnection === firstSession, "the first radio isn't touched")
		#expect(await radios.first.disconnects == 0)
		#expect(disconnected.isEmpty, "its window stays open")
		let secondNum = Int64(radios.secondNum)
		let second = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondNum })).first
		#expect(second?.autoConnect == true, "still remembered")

		manager.reclaimRadioAfterUpdate(radios.secondDevice)
		#expect(manager.additionalRadioReconnects[radios.secondDevice.id] != nil)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }

		try await manager.releaseRadioForUpdate(radios.firstDevice.id)
		#expect(manager.activeConnection == nil)
		#expect(disconnected.isEmpty, "the first radio's window stays too")
	}

	@Test("The one window stays on the first radio while it's released for an update; a Disconnect still shows the other")
	func updateKeepsTheOneWindow() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager

		try await manager.releaseRadioForUpdate(radios.firstDevice.id)
		#expect(manager.activeConnection == nil)
		#expect(manager.additionalRadios[radios.secondDevice.id] != nil, "the other stays connected")
		#expect(manager.oneWindowRadio(stored: nil) == .firstRadio, "not switched to the other radio")
		#expect(manager.oneWindowRadio(stored: radios.firstDevice.id) == .firstRadio)

		// The update sheet closes, whether the update worked or not, as its `releaseRadio()` does: the
		// first radio's place isn't held any more (review V14 P4), and the window stays.
		#expect(manager.firstRadioReleasedForUpdate)
		manager.userRequestedConnectionCancellation = false
		manager.reclaimRadioAfterUpdate(radios.firstDevice)
		#expect(!manager.firstRadioReleasedForUpdate)
		#expect(manager.oneWindowRadio(stored: nil) == .firstRadio, "still not switched")

		try await manager.disconnect()
		#expect(manager.oneWindowRadio(stored: nil) == RadioWindow(deviceId: radios.secondDevice.id), "the user's Disconnect")
		await manager.disconnectRadio(radios.secondDevice.id)
	}

	@Test("The app's own connect work runs for a radio connected with no other")
	func onlyConnectedRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let first = try #require(manager.activeConnection)
		let second = try #require(manager.additionalRadios[radios.secondDevice.id])

		#expect(!manager.isOnlyConnectedRadio(first), "another radio is connected")
		#expect(!manager.isOnlyConnectedRadio(second))
		#expect(!manager.isOnlyConnectedRadio(nil))
		#expect(manager.locationTask != nil, "the position loop runs for both")

		await manager.disconnectAdditionalRadio(radios.secondDevice.id, byUser: true)
		#expect(manager.isOnlyConnectedRadio(first))
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("Every radio's connection reads the same way, the first or another")
	func linkStatusForEveryRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager

		for id in [radios.firstDevice.id, radios.secondDevice.id] {
			let status = manager.linkStatus(of: id)
			#expect(status.state == .subscribed)
			#expect(status.canDisconnect)
			#expect(status.attention == nil)
			#expect(status.lastError == nil)
		}
		#expect(manager.firstDeviceId == radios.firstDevice.id)

		// The other radio shows its own attention; the first radio's comes from the
		// manager's firmware gate.
		let second = try #require(manager.additionalRadios[radios.secondDevice.id])
		manager.setAttention(.firmwareTooOld(version: "2.3.0"), for: second)
		#expect(manager.linkStatus(of: radios.secondDevice.id).firmwareUpdateRequired)
		#expect(!manager.linkStatus(of: radios.firstDevice.id).firmwareUpdateRequired)
		manager.firmwareUpdateRequired = true
		#expect(manager.linkStatus(of: radios.firstDevice.id).firmwareUpdateRequired)
		manager.firmwareUpdateRequired = false
		manager.setAttention(nil, for: second)

		let unknown = manager.linkStatus(of: UUID())
		#expect(unknown.state == .idle)
		#expect(!unknown.canDisconnect)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}
}

// MARK: - Showing another radio without reconnecting (T072)

extension MultiRadioConnectFlowTests {
	private struct TwoRadios {
		let manager: AccessoryManager
		let first: ScriptedRadio
		let second: ScriptedRadio
		let firstDevice: Device
		let secondDevice: Device
		let firstNum: UInt32
		let secondNum: UInt32
	}

	/// Radio A connected and first, radio B connected alongside it.
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

	@Test("Showing another radio in the window reconnects neither radio, and each radio's events stay its own")
	func showAnotherRadioWithoutReconnecting() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let firstSession = try #require(manager.activeConnection)
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])
		let firstRequests = await radios.first.sent.count
		let secondRequests = await radios.second.sent.count

		// What the window's radio menu or Connect's Show This Radio set (T324).
		let window = manager.oneWindowRadio(stored: radios.secondDevice.id)

		#expect(manager.session(for: window) === secondSession)
		#expect(manager.nodeNum(for: window) == Int64(radios.secondNum))
		#expect(manager.activeConnection === firstSession, "the connections don't change")
		#expect(await radios.first.disconnects == 0)
		#expect(await radios.second.disconnects == 0)
		#expect(await radios.first.sent.count == firstRequests)
		#expect(await radios.second.sent.count == secondRequests)

		// An error from the second radio ends only that radio.
		await radios.second.emit(.error(AccessoryError.disconnected("Link lost")))
		try await waitUntil { manager.additionalRadios[radios.secondDevice.id] == nil }
		#expect(manager.additionalRadios[radios.secondDevice.id] == nil)
		#expect(manager.activeConnection === firstSession)
		#expect(await radios.first.disconnects == 0)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("Disconnect on the first radio leaves the other as it is, and the one window shows it")
	func disconnectFirstLeavesTheOther() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])

		try await disconnectFirstRadio(accessoryManager: manager)

		#expect(manager.activeConnection == nil, "nothing takes its place (D-19)")
		#expect(manager.additionalRadios[radios.secondDevice.id] === secondSession)
		#expect(await radios.first.disconnects == 1)
		#expect(await radios.second.disconnects == 0)
		#expect(manager.oneWindowRadio(stored: nil) == RadioWindow(deviceId: radios.secondDevice.id))
		let firstNum = Int64(radios.firstNum)
		let first = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == firstNum })).first
		#expect(first?.autoConnect == false, "a radio the user disconnected isn't brought back")
		#expect(PreferredRadio.peripheralId == radios.secondDevice.id.uuidString, "nor at the next launch: the other is the preferred radio")
		#expect(PreferredRadio.nodeNum == Int64(radios.secondNum))
		await manager.disconnectRadio(radios.secondDevice.id)
	}

	@Test("Disconnect on the only radio, from Shortcuts too, leaves it the preferred radio, as on main")
	func disconnectOnlyRadioStaysPreferred() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let num = uniqueNodeNum()
		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: num)))
		let onlyDevice = device()
		try await manager.connect(to: onlyDevice)
		#expect(PreferredRadio.peripheralId == onlyDevice.id.uuidString)

		try await manager.disconnectRadio(nodeNum: Int64(num))

		#expect(manager.activeConnection == nil)
		#expect(PreferredRadio.peripheralId == onlyDevice.id.uuidString)
		let radioNum = Int64(num)
		let stored = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == radioNum })).first
		#expect(stored?.autoConnect == false, "the same as Disconnect in Connect")
	}

	@Test("Resetting the first radio disconnects it to come back, and leaves the other as it is")
	func resetFirstRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let firstSession = try #require(manager.activeConnection)
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])

		await manager.takeRadioOffline(Int64(radios.firstNum), reconnect: true)

		// Its link closes asking to reconnect, as a single radio's does; nothing takes its place.
		#expect(await radios.first.disconnects == 1)
		#expect(await radios.second.disconnects == 0)
		#expect(manager.additionalRadios[radios.secondDevice.id] === secondSession)
		#expect(manager.activeConnection === firstSession, "until its link reports the close")
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

	@Test("A radio disconnected stays listed as off with its window; removed, its window closes and it's forgotten")
	func disconnectKeepsWindowRemoveClosesIt() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		var removed: [UUID] = []
		let subscription = manager.radioRemoved.sink { removed.append($0) }
		defer { subscription.cancel() }

		await manager.disconnectRadio(radios.secondDevice.id)
		await manager.refreshKnownRadios()
		#expect(removed.isEmpty, "a Disconnect keeps its window (W-02)")
		#expect(manager.offlineRadio(radios.secondDevice.id)?.nodeNum == Int64(radios.secondNum))
		#expect(manager.offlineKnownRadios.contains { $0.deviceId == radios.secondDevice.id }, "the Mac lists it")
		#expect(manager.offlineRadio(radios.firstDevice.id) == nil, "connected")
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == RadioWindow(deviceId: radios.secondDevice.id))

		await manager.removeRadio(Int64(radios.secondNum))

		#expect(removed == [radios.secondDevice.id])
		#expect(manager.knownNodeNums[radios.secondDevice.id] == nil)
		#expect(manager.offlineRadio(radios.secondDevice.id) == nil)
		#expect(!manager.offlineKnownRadios.contains { $0.deviceId == radios.secondDevice.id })
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == .firstRadio)
		#expect(manager.activeConnection != nil, "the other stays")
		try await manager.disconnect()
	}

	@Test("Removing the only radio clears the store; with another radio's data, or another radio connected or connecting, only its own goes")
	func removalClearsStoreOnlyForTheOnlyRadio() {
		func clears(_ stored: [Int64], wasConnected: Bool = false, ownsPendingBackfill: Bool = false, otherRadioActive: Bool = false, othersHoldData: Bool = false) -> Bool {
			AccessoryManager.removalClearsStore(1, storedRadios: stored, wasConnected: wasConnected, ownsPendingBackfill: ownsPendingBackfill, otherRadioActive: otherRadioActive, othersHoldData: othersHoldData)
		}
		#expect(clears([1]))
		#expect(clears([], wasConnected: true), "connected, in its first download")
		#expect(!clears([]), "a radio the store doesn't have is only forgotten (review V27-4)")
		#expect(clears([], ownsPendingBackfill: true), "the store's own radio before its first connect since the update (review V28-3)")
		#expect(!clears([1, 2], wasConnected: true))
		#expect(!clears([2], ownsPendingBackfill: true), "another radio's data")
		#expect(!clears([1], wasConnected: true, otherRadioActive: true), "another radio connected or connecting")
		#expect(!clears([1], wasConnected: true, othersHoldData: true), "another radio's data storedRadios doesn't count (review V27-3)")
		#expect(!clears([], ownsPendingBackfill: true, othersHoldData: true))
	}

	@Test("Disconnect on the first radio with another connected says so before its link closes, and the window picked on it shows it off")
	func firstRadioDisconnectPinsTheWindow() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		await manager.refreshKnownRadios()
		#expect(manager.hasSeveralRadios)
		var told: [(deviceId: UUID, stillConnected: Bool)] = []
		let subscription = manager.radioDisconnectedByUser.sink { deviceId in
			told.append((deviceId, manager.isRadioConnected(deviceId)))
		}
		defer { subscription.cancel() }
		let secondDevice = try #require(manager.additionalRadios[radios.secondDevice.id]?.device)

		// As from Settings, the update screen or Shortcuts: `PreferredRadio` only moves to the
		// other radio once the Disconnect is done (`disconnectFirstRadio`).
		try await manager.disconnect()

		// Told while the window still showed it, so it matched its radio (review V28-1).
		#expect(told.map { $0.deviceId } == [radios.firstDevice.id])
		#expect(told.first?.stillConnected == true)
		#expect(manager.activeConnection == nil)
		#expect(PreferredRadio.peripheralId == radios.firstDevice.id.uuidString)
		#expect(manager.oneWindowRadio(stored: radios.firstDevice.id) == RadioWindow(deviceId: radios.firstDevice.id), "off, not the other radio for a moment")
		#expect(manager.oneWindowRadio(stored: nil) == RadioWindow(deviceId: radios.secondDevice.id), "a window not picked on it shows the other, as before")
		PreferredRadio.set(secondDevice)
		#expect(manager.oneWindowRadio(stored: radios.firstDevice.id) == RadioWindow(deviceId: radios.firstDevice.id), "and once the other is the preferred radio")

		// A radio alongside is told before its link closes too.
		await manager.disconnectRadio(radios.secondDevice.id)
		#expect(told.map { $0.deviceId } == [radios.firstDevice.id, radios.secondDevice.id])
		#expect(told.last?.stillConnected == true)
	}

	@Test("A radio's data goes once no handshake runs; meanwhile it isn't offered, listed or connected")
	func removalWaitsForTheHandshakeGate() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondNum = Int64(radios.secondNum)
		await manager.disconnectRadio(radios.secondDevice.id)
		await manager.refreshKnownRadios()
		#expect(manager.canRemoveRadio(secondNum))
		func storedMyInfos() throws -> Int {
			try ModelContext(PersistenceController.shared.container).fetchCount(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == secondNum }))
		}

		// Another radio's handshake holds the gate (review V27-1).
		await manager.handshakeGate.acquire()
		let removal = Task { await manager.removeRadio(secondNum) }
		try await waitUntil { manager.knownNodeNums[radios.secondDevice.id] == nil }
		#expect(manager.radiosBeingRemoved.contains(secondNum))
		#expect(!manager.canRemoveRadio(secondNum), "not offered twice (review V27-2)")
		#expect(manager.offlineRadio(radios.secondDevice.id) == nil)
		await #expect(throws: AccessoryError.self) { try await manager.connectAdditionalRadio(radios.secondDevice) }
		#expect(try storedMyInfos() == 1, "its data waits for the gate")

		manager.handshakeGate.release()
		await removal.value
		#expect(try storedMyInfos() == 0)
		#expect(manager.radiosBeingRemoved.isEmpty)
		#expect(manager.deviceIdsBeingRemoved.isEmpty)
		#expect(manager.activeConnection != nil, "the other stays")
		try await manager.disconnect()
	}

	@Test("Remove isn't offered for a radio while it connects")
	func removeNotOfferedWhileConnecting() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let num = uniqueNodeNum()
		let manager = makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: num)))
		let target = device()
		manager.knownNodeNums[target.id] = Int64(num)
		#expect(!manager.canRemoveRadio(0))
		await manager.handshakeGate.acquire()

		let connecting = Task { try await manager.connect(to: target) }
		try await waitUntil { manager.connectAttempts[target.id] != nil }
		#expect(!manager.canRemoveRadio(Int64(num)), "a packet of its handshake could land after its data is gone (review V27-5)")

		manager.handshakeGate.release()
		try await connecting.value
		#expect(manager.canRemoveRadio(Int64(num)))
		try await manager.disconnect()
	}

	@Test("A radio that's off is shown so only while the store has it, it isn't connected elsewhere, removed or updated")
	func offlineRadioExclusions() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondNum = Int64(radios.secondNum)
		await manager.disconnectRadio(radios.secondDevice.id)
		await manager.refreshKnownRadios()
		#expect(manager.offlineRadio(radios.secondDevice.id)?.nodeNum == secondNum)

		manager.radiosReleasedForUpdate.insert(radios.secondDevice.id)
		#expect(manager.offlineRadio(radios.secondDevice.id) == nil, "released for a firmware update (review V27-6)")
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == .firstRadio, "as before W-02 while it's updated")
		manager.reclaimRadioAfterUpdate(radios.secondDevice)
		#expect(!manager.radiosReleasedForUpdate.contains(radios.secondDevice.id))
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.additionalRadioReconnects.removeAll()

		manager.radiosBeingRemoved.insert(secondNum)
		#expect(manager.offlineRadio(radios.secondDevice.id) == nil, "being removed (review V27-2)")
		manager.radiosBeingRemoved.removeAll()

		// The first radio, known on another device id too (TCP and BLE), is connected (review V27-8).
		let otherId = UUID()
		manager.knownNodeNums[otherId] = Int64(radios.firstNum)
		#expect(manager.offlineRadio(otherId) == nil)

		// A radio the store no longer has, after Clear App Data or a restore (review V27-4).
		manager.knownRadios.removeAll { $0.nodeNum == secondNum }
		#expect(manager.offlineRadio(radios.secondDevice.id) == nil)
		#expect(manager.oneWindowRadio(stored: radios.secondDevice.id) == .firstRadio)
		await manager.refreshKnownRadios()
		#expect(manager.offlineRadio(radios.secondDevice.id) != nil)
		manager.knownNodeNums.removeValue(forKey: otherId)
		try await manager.disconnect()
	}

	@Test("A radio known on several devices is listed and opened by the one it last connected on")
	func offlineRadioByLastDevice() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondNum = Int64(radios.secondNum)
		await manager.disconnectRadio(radios.secondDevice.id)
		await manager.refreshKnownRadios()
		#expect(manager.radioLastDeviceIds[secondNum] == radios.secondDevice.id)

		// Also known over TCP, by ids sorting before and after its BLE one (W-03, review V28 minor 2).
		let others = [try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), try #require(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))]
		for id in others {
			manager.knownNodeNums[id] = secondNum
		}
		#expect(manager.deviceId(ofRadio: secondNum) == radios.secondDevice.id)
		#expect(manager.offlineKnownRadios.filter { $0.nodeNum == secondNum }.map(\.deviceId) == [radios.secondDevice.id])
		// Without the store's, the same one every time.
		manager.radioLastDeviceIds.removeValue(forKey: secondNum)
		#expect(manager.deviceId(ofRadio: secondNum) == others[0])
		for id in others {
			manager.knownNodeNums.removeValue(forKey: id)
		}
		try await manager.disconnect()
	}

	@Test("After the store is replaced, the radios it no longer has are forgotten and their windows close")
	func radiosNotInStoreAreForgotten() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		await manager.disconnectRadio(radios.secondDevice.id)
		let ghostId = UUID()
		manager.knownNodeNums[ghostId] = Int64(uniqueNodeNum())
		var removed: [UUID] = []
		let subscription = manager.radioRemoved.sink { removed.append($0) }
		defer { subscription.cancel() }

		await manager.forgetRadiosNotInStore()

		#expect(removed == [ghostId])
		#expect(manager.knownNodeNums[ghostId] == nil)
		#expect(manager.knownNodeNums[radios.secondDevice.id] == Int64(radios.secondNum), "the store still has it")
		#expect(manager.knownNodeNums[radios.firstDevice.id] == Int64(radios.firstNum))
		try await manager.disconnect()
	}
}

// MARK: - Handshakes, resets, removal and backfill

extension MultiRadioConnectFlowTests {
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
		#expect(manager.hasFirstConnectInProgress)
		await #expect(throws: AccessoryError.self) { try await manager.connect(to: target) }

		manager.handshakeGate.release()
		try await first.value
		#expect(manager.activeConnection?.device.id == target.id)
		#expect(!manager.hasFirstConnectInProgress)
		try await manager.disconnect()
	}

	@Test("When the first radio drops, the other stays as it is and nothing takes its place")
	func firstRadioDropsNothingMoves() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])
		let dropped = try #require(manager.activeConnection)

		try await dropped.connection.disconnect(withError: nil, shouldReconnect: true)
		try await manager.closeConnection()

		#expect(manager.activeConnection == nil)
		#expect(manager.additionalRadios[radios.secondDevice.id] === secondSession)
		#expect(await radios.second.disconnects == 0)
		#expect(await radios.second.sent.map(describe).filter { $0 == .wantConfig(69420) }.count == 1, "not connected again")
		#expect(manager.locationTask != nil, "the phone's position keeps going to the other radio")
		// The one window keeps the radio that dropped while it's brought back (D-19).
		#expect(manager.oneWindowRadio(stored: nil) == .firstRadio)
		await manager.disconnectRadio(radios.secondDevice.id)
	}

	@Test("A connect as the first radio without a handshake, as a restore of a radio iOS kept connected, makes it the preferred radio")
	func restoreWithoutHandshakeIsPreferred() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		// A is preferred and still connecting; iOS kept B connected, so B is the first restore.
		PreferredRadio.peripheralId = UUID().uuidString
		PreferredRadio.nodeNum = 0x0A0A
		let num = uniqueNodeNum()
		let radio = ScriptedRadio(nodeNum: num)
		let manager = makeManager(ScriptedTransport(radio: radio))
		var restored = device()
		restored.num = Int64(num)

		try await manager.connect(to: restored, withConnection: radio, wantConfig: false, wantDatabase: false, versionCheck: false)

		#expect(manager.activeConnection?.device.id == restored.id)
		#expect(PreferredRadio.peripheralId == restored.id.uuidString)
		#expect(PreferredRadio.nodeNum == Int64(num), "from the restore, as no MyInfo comes")
		#expect(!(await radio.sent.map(describe).contains(.wantConfig(69420))), "no handshake")
		try await manager.disconnect()
	}

	@Test("Removing the first radio with another connected makes that one the preferred radio, as Disconnect does")
	func removeFirstRadioHandsOverPreferred() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		#expect(PreferredRadio.peripheralId == radios.firstDevice.id.uuidString)

		await manager.removeRadio(Int64(radios.firstNum))

		#expect(manager.activeConnection == nil)
		#expect(manager.additionalRadios[radios.secondDevice.id] != nil, "the other stays")
		#expect(PreferredRadio.peripheralId == radios.secondDevice.id.uuidString)
		#expect(PreferredRadio.nodeNum == Int64(radios.secondNum))
		await manager.disconnectRadio(radios.secondDevice.id)
	}

	@Test("A factory reset that clears its bonds takes the only radio offline for good, also when it's connected alongside with no first radio")
	func factoryResetOfTheOnlyRadioAlongside() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondNum = Int64(radios.secondNum)
		// A removed: B is the only radio, alongside with no first radio (T316), and preferred.
		await manager.removeRadio(Int64(radios.firstNum))
		#expect(manager.activeConnection == nil)
		#expect(manager.additionalRadios[radios.secondDevice.id] != nil)

		await manager.disconnectAfterFactoryReset(secondNum)

		#expect(manager.additionalRadios[radios.secondDevice.id] == nil, "disconnected, though it isn't the first radio (review V30-1)")
		#expect(manager.additionalRadioReconnects[radios.secondDevice.id] == nil, "and not brought back")
		#expect(await radios.second.disconnects == 1)

		// The reset clears the store; then it's forgotten, rather than skipped as connected (review V29-1).
		await MeshPackets.shared.removeRadioData(secondNum, .remove)
		var removed: [UUID] = []
		let subscription = manager.radioRemoved.sink { removed.append($0) }
		defer { subscription.cancel() }
		await manager.forgetRadiosNotInStore()
		#expect(removed.contains(radios.secondDevice.id))
		#expect(manager.knownNodeNums[radios.secondDevice.id] == nil)
		#expect(manager.offlineRadio(radios.secondDevice.id) == nil)
	}

	@Test("A factory reset that clears its bonds stops a radio whose link already dropped as it reset coming back")
	func factoryResetAfterTheLinkDropped() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let firstNum = Int64(radios.firstNum)

		// B's link drops as it resets (the firmware turns Bluetooth off), not by the user: its
		// reconnect loop starts.
		await manager.disconnectAdditionalRadio(radios.secondDevice.id)
		manager.scheduleAdditionalRadioReconnect(radios.secondDevice)
		await manager.disconnectAfterFactoryReset(Int64(radios.secondNum))
		#expect(manager.additionalRadioReconnects[radios.secondDevice.id] == nil, "its loop stops")
		#expect(manager.activeConnection != nil, "the other radio stays")

		// The same for the first radio, the preferred one: discovery doesn't connect it again, as
		// after its Disconnect on `main`.
		try await manager.closeConnection()
		#expect(!manager.userRequestedConnectionCancellation)
		#expect(PreferredRadio.nodeNum == firstNum)
		await manager.disconnectAfterFactoryReset(firstNum)
		#expect(manager.userRequestedConnectionCancellation)
		#expect(manager.activeConnection == nil)
	}

	@Test("With another radio connected, a factory reset that clears the first radio's bonds stops discovery connecting it though its link dropped already, and hands the preferred radio on")
	func factoryResetOfTheFirstWithAnotherConnected() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let secondSession = try #require(manager.additionalRadios[radios.secondDevice.id])
		var told: [UUID] = []
		let subscription = manager.radioDisconnectedByUser.sink { told.append($0) }
		defer { subscription.cancel() }

		// A's link drops as it resets (the firmware turns Bluetooth off), not by the user.
		try await manager.closeConnection()
		#expect(!manager.userRequestedConnectionCancellation)

		await manager.disconnectAfterFactoryReset(Int64(radios.firstNum))

		#expect(manager.userRequestedConnectionCancellation, "discovery doesn't connect it again (review V31-1)")
		#expect(manager.additionalRadios[radios.secondDevice.id] === secondSession, "B is untouched")
		#expect(await radios.second.disconnects == 0)
		#expect(told == [radios.firstDevice.id], "its window stays on it, as for a Disconnect")
		#expect(PreferredRadio.peripheralId == radios.secondDevice.id.uuidString, "as after Disconnect on the first radio (review V12 Y3)")
		#expect(PreferredRadio.nodeNum == Int64(radios.secondNum))
		await manager.disconnectRadio(radios.secondDevice.id)
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
		// Another radio's data, so only the dead radio's goes: the only radio's removal clears the
		// whole store, which other suites share.
		let other = MyInfoEntity()
		other.myNodeNum = Int64(uniqueNodeNum())
		other.lastConnected = .now
		context.insert(other)
		try context.save()
		defer {
			context.delete(other)
			try? context.save()
		}
		PreferredRadio.peripheralId = UUID().uuidString
		PreferredRadio.nodeNum = deadNum

		// It dropped earlier, so it has a reconnect loop and is waited for by discovery.
		let deadId = UUID()
		dead.peripheralId = deadId.uuidString
		try context.save()
		manager.scheduleAdditionalRadioReconnect(Device(id: deadId, name: "Dead", transportType: .tcp, identifier: "dead.local:4403", num: deadNum))
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

	@Test("A renumber moves the recorded backfill owner to the radio's new number")
	func backfillOwnerFollowsRenumber() {
		let name = "BackfillOwner-\(UUID().uuidString)"
		let store = UserDefaults(suiteName: name)!
		defer { store.removePersistentDomain(forName: name) }
		let saved = SavedDefaults()
		defer { saved.restore() }
		PreferredRadio.nodeNum = 0x0A0A
		PreferredRadio.peripheralId = "radio-a"
		BackfillOwner.recordIfNeeded(in: store)

		BackfillOwner.renumber(from: 0x0B0B, to: 0x0C0C, in: store)
		#expect(BackfillOwner.current(in: store).nodeNum == 0x0A0A, "another radio's renumber leaves it")
		BackfillOwner.renumber(from: 0x0A0A, to: 0x0D0D, in: store)
		#expect(BackfillOwner.current(in: store) == BackfillOwner.Radio(nodeNum: 0x0D0D, peripheralId: "radio-a"))
	}

	@Test("A renumber moves the service radio choices and the Heard By choice to the new number")
	func savedChoicesFollowRenumber() {
		let name = "RenumberChoices-\(UUID().uuidString)"
		let store = UserDefaults(suiteName: name)!
		defer { store.removePersistentDomain(forName: name) }
		let filters = NodeFilterParameters(store: store, heardByFileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json"))
		UserDefaults.setServiceRadio(0x0A0A, for: .tak, in: store)
		UserDefaults.setServiceRadio(0x0B0B, for: .watch, in: store)
		filters.heardByRadio = 0x0A0A

		AccessoryManager.moveSavedRadioChoices(from: 0x0A0A, to: 0x0D0D, store: store, filters: [filters])

		#expect(UserDefaults.serviceRadio(.tak, in: store) == 0x0D0D)
		#expect(UserDefaults.serviceRadio(.watch, in: store) == 0x0B0B, "another radio's choice stays")
		#expect(filters.heardByRadio == 0x0D0D)
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

	@Test("While the first radio's live version is unknown, version checks use its own stored one")
	func versionCheckUsesTheFirstRadiosOwnVersion() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		// A runs 2.7.15, B runs 2.7.9.
		let radios = try await connectTwoRadios()
		let manager = radios.manager
		let first = try #require(manager.activeConnection)
		#expect(manager.checkIsVersionSupported(forVersion: "2.7.15"))

		// A reconnect window: the live version is briefly unknown.
		first.device.firmwareVersion = nil
		#expect(manager.checkIsVersionSupported(forVersion: "2.7.15"), "A's own stored 2.7.15, not B's 2.7.9")
		#expect(!manager.checkIsVersionSupported(forVersion: "2.7.16"))
		try await manager.disconnect()
	}
}
