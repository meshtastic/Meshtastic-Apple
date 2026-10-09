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

	@Test("During the preferred radio's head start another radio waits, and joins the preferred radio when it connects")
	func waitsForThePreferredRadio() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let preferred = ConnectFlowSupport.device()
		let other = ConnectFlowSupport.device()
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: firstNum), radiosByIdentifier: [
			other.identifier: ScriptedRadio(nodeNum: firstNum &+ 0x100)
		]))
		manager.isSwitchingDevices = false
		manager.firstPlaceHeadStart = .milliseconds(500)
		manager.devices = [other]
		manager.startDiscovery()
		manager.scheduleAdditionalRadioReconnect(other)
		try await Task.sleep(for: .milliseconds(200))
		#expect(manager.connectAttempts[other.id] == nil, "it waits for the preferred radio")

		// The preferred radio connects within its head start.
		try await manager.connect(to: preferred)
		try await ConnectFlowSupport.waitUntil { manager.additionalRadios[other.id] != nil && manager.connectAttempts[other.id] == nil }
		#expect(manager.activeConnection?.device.id == preferred.id, "the preferred radio is first")
		#expect(manager.additionalRadios[other.id] != nil, "the other joined it")
		try await cleanUp(manager, second: other)
	}

	@Test("With no preferred radio set, there's no head start to wait for")
	func noPreferredRadioNoHeadStart() {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let manager = AccessoryManager(transports: [])
		PreferredRadio.peripheralId = UUID().uuidString
		manager.startDiscovery()
		#expect(manager.firstPlaceOpensAt != nil, "the preferred radio's head start")
		manager.stopDiscovery()

		PreferredRadio.peripheralId = ""
		manager.startDiscovery()
		#expect(manager.firstPlaceOpensAt == nil)
		manager.stopDiscovery()
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
