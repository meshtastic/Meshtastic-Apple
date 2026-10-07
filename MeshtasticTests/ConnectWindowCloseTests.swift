//
//  ConnectWindowCloseTests.swift
//  MeshtasticTests
//
//  Feature 021, review V40-1: the Mac's Connect window closes once a radio's connect has finished,
//  when the radios known already include it, so a radio choice the new radio makes needed (W-15)
//  shows there rather than being skipped.
//

import Combine
import Foundation
import Testing
@testable import Meshtastic

@MainActor
@Suite("When a connect counts as finished", .serialized, .timeLimit(.minutes(1)))
struct ConnectWindowCloseTests {
	@Test("A radio counts as finished connecting only once the radios known include it")
	func knownRadiosIncludeIt() async throws {
		let saved = ConnectFlowSupport.SavedDefaults()
		defer { saved.restore() }
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let secondNum = firstNum &+ 0x100
		let secondDevice = ConnectFlowSupport.device()
		let transport = ScriptedTransport(radio: ScriptedRadio(nodeNum: firstNum), radiosByIdentifier: [secondDevice.identifier: ScriptedRadio(nodeNum: secondNum)])
		let manager = ConnectFlowSupport.makeManager(transport)
		try await manager.connect(to: ConnectFlowSupport.device())

		// The radios known the first time the second radio counts as finished, as the Connect
		// window sees it on a redraw.
		var knownWhenFinished: [Int64]?
		let subscription = manager.objectWillChange.sink { _ in
			if knownWhenFinished == nil, manager.hasFinishedConnecting(secondDevice.id) {
				knownWhenFinished = manager.knownRadios.map(\.nodeNum)
			}
		}
		defer { subscription.cancel() }
		try await manager.connectAdditionalRadio(secondDevice)
		if knownWhenFinished == nil, manager.hasFinishedConnecting(secondDevice.id) {
			knownWhenFinished = manager.knownRadios.map(\.nodeNum)
		}

		#expect(knownWhenFinished?.contains(Int64(secondNum)) == true, "not during its node download")
		await manager.disconnectAdditionalRadio(secondDevice.id, byUser: true)
		try await manager.disconnect()
	}
}
