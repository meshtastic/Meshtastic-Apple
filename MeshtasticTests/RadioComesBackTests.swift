//
//  RadioComesBackTests.swift
//  MeshtasticTests
//
//  Feature 021, review V45: a radio that dropped comes back as `main`'s radio does, when discovery
//  sees it, and discovery goes on while it waits.
//

import Foundation
import Testing
@testable import Meshtastic

/// Set once a task has ended.
@MainActor
private final class Ended {
	private(set) var isSet = false
	func set() { isSet = true }
}

@MainActor
@Suite("A radio coming back after a drop", .serialized, .timeLimit(.minutes(1)))
struct RadioComesBackTests {
	/// The first radio connected, and another alongside it. Radios other tests left remembered in
	/// the shared store aren't waited for.
	private func connectTwoRadios() async throws -> (manager: AccessoryManager, second: Device) {
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let second = ConnectFlowSupport.device()
		let transport = ScriptedTransport(radio: ScriptedRadio(nodeNum: firstNum), radiosByIdentifier: [
			second.identifier: ScriptedRadio(nodeNum: firstNum &+ 0x100)
		])
		let manager = ConnectFlowSupport.makeManager(transport)
		try await manager.connect(to: ConnectFlowSupport.device())
		try await manager.connectAdditionalRadio(second)
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.additionalRadioReconnects.removeAll()
		// Their ends run before the test goes on.
		try await Task.sleep(for: .milliseconds(50))
		return (manager, second)
	}

	private func cleanUp(_ manager: AccessoryManager, second: Device) async throws {
		manager.isSwitchingDevices = true
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.stopDiscovery()
		await manager.disconnectAdditionalRadio(second.id, byUser: true)
		try await manager.disconnect()
	}

	@Test("A radio alongside that dropped connects when discovery sees it, not before")
	func connectsWhenSeen() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let (manager, second) = try await connectTwoRadios()
		await manager.disconnectAdditionalRadio(second.id)
		manager.scheduleAdditionalRadioReconnect(second)
		try await Task.sleep(for: .milliseconds(300))
		#expect(manager.additionalRadios[second.id] == nil, "not seen: not connected")
		#expect(manager.connectAttempts[second.id] == nil, "nor tried")

		manager.radioSeen(second.id)
		try await ConnectFlowSupport.waitUntil { manager.additionalRadios[second.id] != nil && manager.connectAttempts[second.id] == nil }
		#expect(manager.additionalRadios[second.id] != nil)
		#expect(manager.additionalRadioReconnects[second.id] == nil, "its wait is over")
		try await cleanUp(manager, second: second)
	}

	@Test("A radio's wait ends when the radio connects as the first radio another way, rather than staying suspended")
	func waitEndsWhenConnectedAsFirst() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let radio = ConnectFlowSupport.device()
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: ConnectFlowSupport.uniqueNodeNum())))
		manager.scheduleAdditionalRadioReconnect(radio)
		let wait = try #require(manager.additionalRadioReconnects[radio.id])
		let ended = Ended()
		Task { await wait.value; ended.set() }

		// The user connects it, as the first radio, not through its wait.
		try await manager.connect(to: radio)
		try await ConnectFlowSupport.waitUntil { ended.isSet }
		#expect(ended.isSet, "its wait ended")
		#expect(manager.radioSightings[radio.id] == nil)
		try await manager.disconnect()
	}

	@Test("A new wait for a radio ends an earlier one left without its entry")
	func newWaitEndsAnOrphan() async throws {
		let manager = AccessoryManager(transports: [])
		let radio = ConnectFlowSupport.device()
		manager.scheduleAdditionalRadioReconnect(radio)
		let old = try #require(manager.additionalRadioReconnects[radio.id])
		manager.additionalRadioReconnects.removeValue(forKey: radio.id)
		let ended = Ended()
		Task { await old.value; ended.set() }

		manager.scheduleAdditionalRadioReconnect(radio)
		try await ConnectFlowSupport.waitUntil { ended.isSet }
		#expect(ended.isSet, "the earlier wait ended")
		#expect(manager.additionalRadioReconnects[radio.id] != nil, "the new one goes on")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		manager.stopDiscovery()
	}

	@Test("After a launch the one window shows the radio that connected first until the one used last is back, then that one")
	func windowWaitsForTheRadioUsedLast() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let (manager, second) = try await connectTwoRadios()
		// The radio used last is on its way back; the first radio is connected.
		await manager.disconnectAdditionalRadio(second.id)
		manager.scheduleAdditionalRadioReconnect(second)
		#expect(manager.oneWindowRadio(stored: nil, waitingFor: second.id) == .firstRadio, "the radio that connected, meanwhile")
		#expect(manager.oneWindowRadio(stored: second.id, waitingFor: second.id) == .firstRadio, "also when it was picked")
		#expect(manager.oneWindowRadio(stored: second.id, waitingFor: nil) == RadioWindow(deviceId: second.id), "a pick since: the picked radio, coming back")

		manager.radioSeen(second.id)
		try await ConnectFlowSupport.waitUntil { manager.additionalRadios[second.id] != nil && manager.connectAttempts[second.id] == nil }
		#expect(manager.oneWindowRadio(stored: second.id, waitingFor: second.id) == RadioWindow(deviceId: second.id), "back: shown")

		// One the user disconnected isn't coming back: it's shown off, as before (W-02).
		await manager.disconnectAdditionalRadio(second.id, byUser: true)
		#expect(!manager.isComingBack(second.id))
		#expect(manager.oneWindowRadio(stored: second.id, waitingFor: second.id) == RadioWindow(deviceId: second.id))
		try await cleanUp(manager, second: second)
	}

	@Test("Discovery goes on while a radio waits to come back, and stops once it's back")
	func scanningWhileWaiting() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let (manager, second) = try await connectTwoRadios()
		await manager.disconnectAdditionalRadio(second.id)
		manager.isSwitchingDevices = false
		manager.scheduleAdditionalRadioReconnect(second)
		#expect(manager.discoveryTask != nil, "started for it")
		manager.stopDiscoveryWhenUnneeded()
		#expect(manager.discoveryTask != nil, "it still waits")

		manager.radioSeen(second.id)
		try await ConnectFlowSupport.waitUntil { manager.additionalRadioReconnects[second.id] == nil && manager.connectAttempts[second.id] == nil }
		#expect(manager.additionalRadios[second.id] != nil)
		#expect(manager.discoveryTask == nil, "nothing waits any more")
		try await cleanUp(manager, second: second)
	}
}
