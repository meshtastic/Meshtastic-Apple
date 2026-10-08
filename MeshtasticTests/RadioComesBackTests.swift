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
