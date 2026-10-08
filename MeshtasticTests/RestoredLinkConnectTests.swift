//
//  RestoredLinkConnectTests.swift
//  MeshtasticTests
//
//  Feature 021: a radio whose link iOS kept connected through a restore of the app connects
//  asking only for its config, as `main` does for its restored radio (#2584), whether it's the
//  first radio or one alongside.
//

import Foundation
import Testing
@testable import Meshtastic

@MainActor
@Suite("A link kept through a restore", .serialized, .timeLimit(.minutes(1)))
struct RestoredLinkConnectTests {
	@Test("Every radio on a kept link asks for its config and not its node database, the first one or one alongside")
	func asksOnlyForConfig() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let first = ScriptedRadio(nodeNum: firstNum, keptByRestore: true)
		let second = ScriptedRadio(nodeNum: firstNum &+ 0x100, keptByRestore: true)
		let secondDevice = ConnectFlowSupport.device()
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second]))
		try await manager.connect(to: ConnectFlowSupport.device())
		try await manager.connectAdditionalRadio(secondDevice)

		#expect(manager.isConnected)
		#expect(manager.additionalRadios[secondDevice.id] != nil)
		for radio in [first, second] {
			let sent = await radio.sent.map(describe)
			#expect(sent.contains(.wantConfig(69420)), "its config")
			#expect(!sent.contains(.wantConfig(69421)), "not its node database")
		}
		await manager.disconnectAdditionalRadio(secondDevice.id, byUser: true)
		try await manager.disconnect()
	}

	@Test("A radio restored alongside starts connecting as soon as the first radio's restore starts, not after it")
	func restoredAlongsideConnectsAtOnce() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let second = ScriptedRadio(nodeNum: firstNum &+ 0x100, keptByRestore: true)
		let secondDevice = ConnectFlowSupport.device()
		let firstDevice = ConnectFlowSupport.device()
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: ScriptedRadio(nodeNum: firstNum, keptByRestore: true), radiosByIdentifier: [secondDevice.identifier: second]))

		// Told before the first radio's restore has started: it waits, so it doesn't take its place.
		await manager.noteRestoredAlongside([secondDevice])
		#expect(manager.connectAttempts[secondDevice.id] == nil)

		let first = Task { try await manager.connect(to: firstDevice) }
		try await ConnectFlowSupport.waitUntil { manager.connectAttempts[secondDevice.id] != nil }
		#expect(manager.connectAttempts[secondDevice.id]?.isFirst == false, "alongside")
		#expect(manager.connectAttempts[firstDevice.id] != nil, "while the first radio's restore still runs")

		try await first.value
		try await ConnectFlowSupport.waitUntil { manager.additionalRadios[secondDevice.id] != nil && manager.connectAttempts[secondDevice.id] == nil }
		#expect(manager.additionalRadios[secondDevice.id] != nil)
		#expect(!(await second.sent.map(describe).contains(.wantConfig(69421))), "its config only, as a kept link")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		await manager.disconnectAdditionalRadio(secondDevice.id, byUser: true)
		try await manager.disconnect()
	}
}
