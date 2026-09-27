//
//  ConnectFlowCharacterizationTests.swift
//  MeshtasticTests
//
//  Feature 021, T068: pins what `AccessoryManager.connect(to:)` does today, end to end, against
//  a scripted radio. These are the safety net for moving the connect flow onto `RadioSession`
//  and running every radio through it (D-17, plan.md › Every radio the same): the steps may
//  move, but what a radio sees and what the app ends up with must not change.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

// MARK: - Tests

@MainActor
@Suite("Connect flow (characterization)", .serialized, .timeLimit(.minutes(1)))
struct ConnectFlowCharacterizationTests {

	/// The UserDefaults the connect flow writes, put back after each test.
	private struct SavedDefaults {
		let preferredPeripheralId = UserDefaults.preferredPeripheralId
		let preferredPeripheralNum = UserDefaults.preferredPeripheralNum
		let firmwareVersion = UserDefaults.firmwareVersion
		let lastFirmwareAPIUpdate = UserDefaults.lastFirmwareAPIUpdate

		func restore() {
			UserDefaults.preferredPeripheralId = preferredPeripheralId
			UserDefaults.preferredPeripheralNum = preferredPeripheralNum
			UserDefaults.firmwareVersion = firmwareVersion
			UserDefaults.lastFirmwareAPIUpdate = lastFirmwareAPIUpdate
		}
	}

	private func makeManager(_ transport: ScriptedTransport) -> AccessoryManager {
		// The firmware-update notifier would otherwise refresh from the network in Step 7.
		UserDefaults.lastFirmwareAPIUpdate = Date()
		let manager = AccessoryManager(transports: [transport])
		manager.isSwitchingDevices = true
		manager.context = PersistenceController.shared.context
		manager.appState = AppState(router: Router())
		return manager
	}

	private func uniqueNodeNum() -> UInt32 {
		UInt32.random(in: 0x5000_0000...0x5FFF_FFFF)
	}

	/// Polls `condition` for up to two seconds; the tests then check the outcome themselves.
	private func waitUntil(_ condition: () async -> Bool) async throws {
		for _ in 0..<200 {
			if await condition() { return }
			try await Task.sleep(for: .milliseconds(10))
		}
	}

	private func device() -> Device {
		Device(id: UUID(), name: "Scripted", transportType: .tcp, identifier: "scripted-\(UUID().uuidString).local:4403")
	}

	@Test("A connect runs heartbeat, config, heartbeat, node DB, then sets the time, and ends connected")
	func happyPath() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let nodeNum = uniqueNodeNum()
		let radio = ScriptedRadio(nodeNum: nodeNum, dumpNodes: [nodeNum &+ 1, nodeNum &+ 2])
		let transport = ScriptedTransport(radio: radio)
		let manager = makeManager(transport)
		let radioDevice = device()

		try await manager.connect(to: radioDevice)

		let sent = await radio.sent.map(describe)
		#expect(Array(sent.prefix(5)) == [.heartbeat, .wantConfig(69420), .heartbeat, .wantConfig(69421), .setTime])
		#expect(transport.connectAttempts == 1)

		#expect(manager.state == .subscribed)
		#expect(manager.isConnected)
		#expect(!manager.isConnecting)
		#expect(manager.activeDeviceNum == Int64(nodeNum))
		#expect(manager.activeConnection?.device.id == radioDevice.id)
		#expect(manager.activeConnection?.device.longName == "Scripted Radio")
		#expect(manager.activeConnection?.device.shortName == "SCR")
		#expect(manager.activeConnection?.device.firmwareVersion == "2.7.15.567b8ea")
		#expect(manager.connectionStepper == nil)
		#expect(!manager.firmwareUpdateRequired)
		#expect(manager.allowDisconnect)
		#expect(manager.expectedNodeDBSize == 3)

		// What the flow records about the radio.
		#expect(UserDefaults.preferredPeripheralId == radioDevice.id.uuidString)
		#expect(UserDefaults.preferredPeripheralNum == Int(nodeNum))
		#expect(UserDefaults.firmwareVersion == "2.7.15")
		let myNodeNum = Int64(nodeNum)
		let myInfo = try PersistenceController.shared.context.fetch(FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == myNodeNum })).first
		#expect(myInfo?.peripheralId == radioDevice.id.uuidString)
		#expect(myInfo?.channels.count == 1, "the primary channel, with the disabled slots dropped")

		try await manager.disconnect()
	}

	@Test("Firmware below the minimum keeps the connection, behind the update gate")
	func oldFirmwareKeepsConnection() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), firmwareVersion: "2.3.0.abcdef0")
		let manager = makeManager(ScriptedTransport(radio: radio))

		try await manager.connect(to: device())

		#expect(manager.firmwareUpdateRequired)
		#expect(manager.isConnected)
		#expect(manager.state == .subscribed)
		#expect(UserDefaults.firmwareVersion == "2.3.0")
		try await manager.disconnect()
	}

	@Test("Disconnect tears everything down and returns to discovering")
	func disconnectTearsDown() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())
		// The connection's own state is on its session (T069); check the one that was closed.
		let session = try #require(manager.activeConnection)
		#expect(session.eventTask != nil)

		try await manager.disconnect()

		#expect(manager.activeConnection == nil)
		#expect(manager.activeDeviceNum == nil)
		#expect(manager.state == .discovering)
		#expect(!manager.isConnected)
		#expect(!manager.allowDisconnect)
		#expect(session.eventTask == nil)
		#expect(session.heartbeatTimer == nil)
		#expect(session.firstDatabaseNodeInfoContinuation == nil)
		#expect(session.automaticConfigRefresh == nil)
		#expect(manager.locationTask == nil)
		#expect(await radio.disconnects == 1)
	}

	@Test("A transport that keeps failing is tried twice, then the connect gives up")
	func transportFailureRetries() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let transport = ScriptedTransport(radio: radio, failure: AccessoryError.connectionFailed("Refused"))
		let manager = makeManager(transport)

		try? await manager.connect(to: device())

		#expect(transport.connectAttempts == 2)
		#expect(manager.activeConnection == nil)
		#expect(!manager.isConnected)
		#expect(manager.lastConnectionError != nil)
		#expect(manager.connectionStepper == nil)
	}

	@Test("A lost bond stops the connect at once and suspends automatic reconnects")
	func lostBondStopsRetries() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let transport = ScriptedTransport(radio: radio, failure: AccessoryError.bondLost)
		let manager = makeManager(transport)

		try? await manager.connect(to: device())

		#expect(transport.connectAttempts == 1)
		#expect(manager.activeConnection == nil)
		#expect(manager.autoReconnectSuspendedForSession)
		#expect(!manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
		if case AccessoryError.bondLost = manager.lastConnectionError ?? AccessoryError.timeout {
		} else {
			Issue.record("lastConnectionError is \(String(describing: manager.lastConnectionError)), expected bondLost")
		}
	}

	@Test("A second connect while one radio is connected is refused")
	func secondConnectRefused() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		await #expect(throws: AccessoryError.self) {
			try await manager.connect(to: device())
		}
		#expect(manager.isConnected)
		try await manager.disconnect()
	}

	@Test("The node DB dump lands in the store, with this radio's view of each node")
	func nodeDumpStored() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let nodeNum = uniqueNodeNum()
		let others: [UInt32] = [nodeNum &+ 11, nodeNum &+ 12, nodeNum &+ 13]
		let radio = ScriptedRadio(nodeNum: nodeNum, dumpNodes: others)
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		let context = PersistenceController.shared.context
		let radioNum = Int64(nodeNum)
		for num in others.map(Int64.init) {
			let node = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
			#expect(node?.user?.longName == "Node \(num)")
			let observations = try context.fetch(FetchDescriptor<NodeObservationEntity>(predicate: #Predicate { $0.radioNum == radioNum && $0.nodeNum == num }))
			#expect(observations.count == 1, "one observation of node \(num) by the radio")
		}
		try await manager.disconnect()
	}

	@Test("A blank timezone on the radio is filled in with the phone's")
	func blankTimezoneFilled() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), timezone: "")
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())
		try await waitUntil {
			await radio.sent.map(describe).contains { if case .setTimezone = $0 { return true } else { return false } }
		}

		let timezones = await radio.sent.map(describe).compactMap { item -> String? in
			if case .setTimezone(let tz) = item { return tz } else { return nil }
		}
		#expect(timezones == [TimeZone.current.posixDescription])
		try await manager.disconnect()
	}

	@Test("With canned messages on, the app asks the radio for them")
	func cannedMessagesRequested() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum(), cannedMessages: true)
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		#expect(await radio.sent.map(describe).contains(.cannedMessagesRequest))
		try await manager.disconnect()
	}

	@Test("A transport that needs heartbeats gets the periodic heartbeat and its response timeout")
	func periodicHeartbeat() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio, requiresPeriodicHeartbeat: true))
		try await manager.connect(to: device())

		let session = try #require(manager.activeConnection)
		#expect(session.heartbeatTimer != nil)
		#expect(session.heartbeatResponseTimer != nil, "firmware 2.7.4 and later answers heartbeats")
		try await manager.disconnect()
		#expect(session.heartbeatTimer == nil)
		#expect(session.heartbeatResponseTimer == nil)
	}

	@Test("An error from the link tears the connection down and keeps automatic reconnects on")
	func linkErrorTearsDown() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		await radio.emit(.error(AccessoryError.disconnected("Link lost")))
		try await waitUntil { manager.activeConnection == nil && manager.state == .discovering }

		#expect(manager.activeConnection == nil)
		#expect(!manager.isConnected)
		#expect(manager.state == .discovering)
		#expect(manager.lastConnectionError != nil)
		#expect(manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
	}

	@Test("A disconnect reported by the link tears down and turns automatic reconnects off")
	func linkDisconnectTearsDown() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())

		await radio.emit(.disconnected(shouldReconnect: false))
		try await waitUntil { manager.activeConnection == nil && manager.state == .discovering }

		#expect(manager.activeConnection == nil)
		#expect(manager.state == .discovering)
		#expect(!manager.shouldAutomaticallyConnectToPreferredPeripheralAfterError)
	}

	@Test("A reboot while connected fetches the config again")
	func rebootRefreshesConfig() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radio = ScriptedRadio(nodeNum: uniqueNodeNum())
		let manager = makeManager(ScriptedTransport(radio: radio))
		try await manager.connect(to: device())
		let before = await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count

		await radio.emit(.rebooted(true))
		try await waitUntil { await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count > before }

		#expect(await radio.sent.map(describe).filter { $0 == .wantConfig(69420) }.count == before + 1)
		#expect(manager.isConnected)
		try await manager.disconnect()
	}

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
}
