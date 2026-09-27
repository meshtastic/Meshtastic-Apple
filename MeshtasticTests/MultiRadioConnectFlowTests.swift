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
		manager.scheduleFocusHandover(previousRadio: Int64(radios.firstNum), after: .milliseconds(10))
		try await waitUntil { manager.activeConnection != nil }

		#expect(manager.activeConnection === secondSession)
		#expect(await radios.second.disconnects == 0)
		#expect(await radios.second.sent.map(describe).filter { $0 == .wantConfig(69420) }.count == 1, "not connected again")
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
