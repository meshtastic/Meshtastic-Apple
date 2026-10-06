//
//  MultiRadioUnheardOnCurrentLoraTests.swift
//  MeshtasticTests
//
//  main's #2575 stores NodeInfo.heard_on_current_lora on the shared node rows, from the one
//  connected radio. Feature 021: each radio answers for its own LoRa settings, so its answers are
//  kept on its own observations and each window shows its radio's. The unheard notice offers only
//  nodes the window's radio had (review V35), and Remove Them keeps a node another of the user's
//  radios still has (D-18). Scripted radios as in `MultiRadioConnectFlowTests`.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@MainActor
@Suite("Unheard on current LoRa with several radios", .serialized, .timeLimit(.minutes(1)))
struct MultiRadioUnheardOnCurrentLoraTests {

	private typealias SavedDefaults = ConnectFlowSupport.SavedDefaults
	/// Firmware that sends NodeInfo.heard_on_current_lora (2.8.1+).
	private let reportingFirmware = "2.8.1.abcdef0"

	/// Radio `radioNum`'s answer for node `num` in the shared store; nil without an observation.
	private func answer(_ num: UInt32, by radioNum: UInt32) -> Bool? {
		RadioLoraAnswers.answer(of: Int64(num), radioNum: Int64(radioNum), container: PersistenceController.shared.container)?.heard
	}

	/// A store of its own, for tests that read every node or observation in it.
	private func isolatedContainer(_ name: String) throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		return try ModelContainer(for: schema, configurations: ModelConfiguration("\(name)-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true))
	}

	private func insertNode(_ num: Int64, favorite: Bool = false, in context: ModelContext) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.id = num
		node.num = num
		node.favorite = favorite
		context.insert(node)
		return node
	}

	private func insertRadio(_ num: Int64, in context: ModelContext) {
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = num
		context.insert(myInfo)
	}

	private struct Radios {
		let manager: AccessoryManager
		let firstNum: UInt32
		let secondNum: UInt32
		let secondDevice: Device
	}

	/// The first radio connected and its node database saved; the second one ready to connect.
	private func connectFirst(firmware: String) async throws -> Radios {
		let firstNum = ConnectFlowSupport.uniqueNodeNum()
		let secondNum = firstNum &+ 0x300
		let first = ScriptedRadio(nodeNum: firstNum, firmwareVersion: firmware, dumpNodes: [firstNum &+ 1])
		let second = ScriptedRadio(nodeNum: secondNum, firmwareVersion: reportingFirmware, dumpNodes: [secondNum &+ 1])
		let secondDevice = ConnectFlowSupport.device()
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: first, radiosByIdentifier: [secondDevice.identifier: second]))
		try await manager.connect(to: ConnectFlowSupport.device())
		try await ConnectFlowSupport.waitUntil { manager.nodeDatabaseSavedAt[Int64(firstNum)] != nil }
		return Radios(manager: manager, firstNum: firstNum, secondNum: secondNum, secondDevice: secondDevice)
	}

	// MARK: Each radio's own answers

	@Test("Two radios connected keep their own answers, side by side")
	func eachRadioKeepsItsOwnAnswers() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager
		let firstNum = Int64(radios.firstNum), secondNum = Int64(radios.secondNum)
		// The scripted dump leaves the field at its default, false: not heard on these settings.
		try await ConnectFlowSupport.waitUntil { answer(radios.firstNum &+ 1, by: radios.firstNum) == false }

		try await manager.connectAdditionalRadio(radios.secondDevice)
		try await ConnectFlowSupport.waitUntil { manager.nodeDatabaseSavedAt[secondNum] != nil }
		#expect(manager.reportsHeardOnCurrentLora(forRadio: firstNum), "a second radio doesn't stand the first one's answers down")
		#expect(manager.reportsHeardOnCurrentLora(forRadio: secondNum))
		#expect(manager.nodeDatabaseSavedAt[firstNum] != nil)
		#expect(answer(radios.firstNum &+ 1, by: radios.firstNum) == false, "the first radio's answer is kept")
		#expect(answer(radios.secondNum &+ 1, by: radios.secondNum) == false, "the second radio's is stored too")
		let container = PersistenceController.shared.container
		#expect(RadioLoraAnswers.unheardNodeNums(ofRadio: firstNum, container: container).contains(firstNum &+ 1))
		#expect(!RadioLoraAnswers.unheardNodeNums(ofRadio: firstNum, container: container).contains(secondNum &+ 1), "only the window's radio's answers")

		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
		#expect(manager.nodeDatabaseSavedAt[firstNum] == nil, "a disconnected radio's download state goes")
		#expect(answer(radios.firstNum &+ 1, by: radios.firstNum) == false, "its answers stay with its observations, as on main")
	}

	@Test("A LoRa change asks the changed radio for its node database again, whichever it is")
	func loraChangeRefreshForEachRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager
		let firstNum = Int64(radios.firstNum), secondNum = Int64(radios.secondNum)

		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: secondNum)
		#expect(manager.radiosAwaitingNodeDatabaseAfterLoRaChange.isEmpty, "not connected")
		try await manager.connectAdditionalRadio(radios.secondDevice)
		try await ConnectFlowSupport.waitUntil { manager.nodeDatabaseSavedAt[secondNum] != nil }

		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: secondNum)
		#expect(manager.radiosAwaitingNodeDatabaseAfterLoRaChange == [secondNum], "only the radio that changed waits")
		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: firstNum)
		#expect(manager.radiosAwaitingNodeDatabaseAfterLoRaChange == [firstNum, secondNum])
		try await ConnectFlowSupport.waitUntil { manager.radiosAwaitingNodeDatabaseAfterLoRaChange.isEmpty }
		#expect(manager.nodeDatabaseSavedAt[firstNum] != nil && manager.nodeDatabaseSavedAt[secondNum] != nil, "each asked again and saved")

		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("A radio whose firmware doesn't send the field answers nothing")
	func olderFirmwareAnswersNothing() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: "2.7.15.567b8ea")
		let manager = radios.manager

		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)))
		#expect(answer(radios.firstNum &+ 1, by: radios.firstNum) == nil)
		try await manager.disconnect()
	}

	@Test("A and B heard C on LongFast; A moves to LongTurbo: only A's window marks C, and Remove Them there keeps C for B")
	func presetChangeOnOneRadio() async throws {
		let container = try isolatedContainer("UnheardPresetChange")
		let setup = ModelContext(container)
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B, nodeC: Int64 = 0x7E57_0410
		insertRadio(radioA, in: setup)
		insertRadio(radioB, in: setup)
		try setup.save()
		let packets = MeshPackets(modelContainer: container)
		func report(_ heard: Bool, by radio: Int64) async {
			var info = NodeInfo()
			info.num = UInt32(nodeC)
			info.heardOnCurrentLora = heard
			_ = await packets.nodeInfoPacket(nodeInfo: info, channel: 0, connectedNodeNum: radio, reportsHeardOnCurrentLora: true)
			await packets.flushDebouncedSaves()
		}
		func unheard(by radio: Int64) -> Set<Int64> {
			RadioLoraAnswers.unheardNodeNums(ofRadio: radio, container: container)
		}

		// A is on LongTurbo now and hasn't heard C there; B, still on LongFast, has.
		await report(false, by: radioA)
		await report(true, by: radioB)
		#expect(unheard(by: radioA) == [nodeC], "A's window marks C")
		#expect(unheard(by: radioB).isEmpty, "B's doesn't")

		// Remove Them in A's window: A drops C, and C stays in the app for B.
		#expect(try await packets.removeUnheardNode(nodeC, ofRadio: radioA))
		#expect(unheard(by: radioA).isEmpty)
		#expect(RadioLoraAnswers.answer(of: nodeC, radioNum: radioB, container: container)?.heard == true, "B's list keeps C, unmarked")

		// B moves to LongTurbo too and hasn't heard C there: main's rules, C goes.
		await report(false, by: radioB)
		#expect(unheard(by: radioB) == [nodeC], "now B's window marks it")
		#expect(try await packets.removeUnheardNode(nodeC, ofRadio: radioB) == false)
		let left = try ModelContext(container).fetchCount(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeC }))
		#expect(left == 0, "no radio has it any more")
	}

	@Test("A download's missing nodes lose that radio's answer only")
	func markAbsentIsPerRadio() async throws {
		let container = try isolatedContainer("UnheardMarkAbsent")
		let setup = ModelContext(container)
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B, kept: Int64 = 0x7E57_0411, dropped: Int64 = 0x7E57_0412
		for num in [kept, dropped] {
			_ = insertNode(num, in: setup)
			for radio in [radioA, radioB] {
				let observation = NodeObservationEntity(radioNum: radio, nodeNum: num)
				observation.heardOnCurrentLora = false
				setup.insert(observation)
			}
		}
		try setup.save()

		await MeshPackets(modelContainer: container).markAbsentFromRadio(presentNums: [kept], radioNum: radioA)
		#expect(RadioLoraAnswers.answer(of: kept, radioNum: radioA, container: container)?.heard == false)
		#expect(RadioLoraAnswers.answer(of: dropped, radioNum: radioA, container: container)?.heard == nil, "A no longer has it")
		#expect(RadioLoraAnswers.answer(of: dropped, radioNum: radioB, container: container)?.heard == false, "B's answer isn't A's")
	}

	// MARK: The unheard notice (review V35-1)

	@Test("The notice offers only nodes the window's radio observed, never your other radios or what only they heard")
	func noticeOffersOnlyTheWindowsRadiosNodes() throws {
		let context = ModelContext(try isolatedContainer("UnheardCandidates"))
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B
		let droppedByA: Int64 = 0x7E57_0401, onlyB: Int64 = 0x7E57_0402, favoriteOfA: Int64 = 0x7E57_0403
		insertRadio(radioA, in: context)
		insertRadio(radioB, in: context)
		for num in [radioA, radioB, droppedByA, onlyB] {
			_ = insertNode(num, in: context)
		}
		_ = insertNode(favoriteOfA, favorite: true, in: context)
		// A heard B and the others; B heard A and a node A never did.
		for (radio, num) in [(radioA, radioB), (radioA, droppedByA), (radioA, favoriteOfA), (radioB, onlyB), (radioB, radioA)] {
			context.insert(NodeObservationEntity(radioNum: radio, nodeNum: num))
		}
		try context.save()

		let candidates = try UnheardNodesRemoval.candidates(forRadio: radioA, in: context).map(\.num)
		#expect(candidates == [droppedByA])
	}

	@Test("With one radio's data, the notice's list is main's, observed or not")
	func noticeKeepsMainsListForOneRadio() throws {
		let context = ModelContext(try isolatedContainer("UnheardCandidatesOneRadio"))
		let radioA: Int64 = 0x0A0A, olderNode: Int64 = 0x7E57_0404
		insertRadio(radioA, in: context)
		_ = insertNode(radioA, in: context)
		_ = insertNode(olderNode, in: context)
		try context.save()

		let candidates = try UnheardNodesRemoval.candidates(forRadio: radioA, in: context).map(\.num)
		#expect(candidates == [olderNode], "a row from before feature 021 has no observation yet")
	}

	@Test("Remove Them deletes a node only this radio heard, and keeps one another radio heard (D-18)")
	func removalKeepsNodesAnotherRadioHeard() async throws {
		let container = try isolatedContainer("UnheardRemoval")
		let setup = ModelContext(container)
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B
		let onlyA: Int64 = 0x7E57_0405, alsoB: Int64 = 0x7E57_0407
		insertRadio(radioA, in: setup)
		insertRadio(radioB, in: setup)
		let user = UserEntity()
		user.num = onlyA
		setup.insert(user)
		insertNode(onlyA, in: setup).user = user
		setup.insert(NodeObservationEntity(radioNum: radioA, nodeNum: onlyA))
		let shared = insertNode(alsoB, in: setup)
		shared.heardOnCurrentLora = false
		shared.hopsAway = 1
		shared.lastHeard = Date()
		for (radio, hops) in [(radioA, Int32(1)), (radioB, Int32(3))] {
			let observation = NodeObservationEntity(radioNum: radio, nodeNum: alsoB)
			observation.hopsAway = hops
			observation.lastHeard = Date()
			setup.insert(observation)
		}
		try setup.save()

		let packets = MeshPackets(modelContainer: container)
		let onlyAStayed = try await packets.removeUnheardNode(onlyA, ofRadio: radioA)
		let alsoBStayed = try await packets.removeUnheardNode(alsoB, ofRadio: radioA)
		#expect(!onlyAStayed)
		#expect(alsoBStayed)

		let context = ModelContext(container)
		let left = try context.fetch(FetchDescriptor<NodeInfoEntity>())
		#expect(left.map(\.num) == [alsoB], "the node B heard stays in the app")
		#expect(left.first?.hopsAway == 3, "it shows B's view")
		let observations = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		#expect(observations.map(\.radioNum) == [radioB], "A's part goes; left behind, it would bring A's Heard By back")
		#expect(try context.fetchCount(FetchDescriptor<UserEntity>()) == 0, "the node only A heard goes with its user")
	}

	@Test("Remove Them works from the observations as they are now, saved or not (review V36-1)")
	func removalUsesCurrentObservations() async throws {
		let container = try isolatedContainer("UnheardRemovalCurrent")
		let setup = ModelContext(container)
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B
		let kept: Int64 = 0x7E57_0408, newlyHeardByA: Int64 = 0x7E57_0409
		insertRadio(radioA, in: setup)
		insertRadio(radioB, in: setup)
		let node = insertNode(kept, in: setup)
		node.heardOnCurrentLora = false
		node.lastHeard = Date()
		for (radio, hops) in [(radioA, Int32(1)), (radioB, Int32(5))] {
			let observation = NodeObservationEntity(radioNum: radio, nodeNum: kept)
			observation.hopsAway = hops
			observation.lastHeard = Date().addingTimeInterval(-600)
			setup.insert(observation)
		}
		_ = insertNode(newlyHeardByA, in: setup)
		let heardByB = NodeObservationEntity(radioNum: radioB, nodeNum: newlyHeardByA)
		heardByB.lastHeard = Date()
		setup.insert(heardByB)
		try setup.save()

		let packets = MeshPackets(modelContainer: container)
		// B hears the kept node again, two hops away, and A hears the other node for the first
		// time. Neither is saved yet: the packet handlers' saves are debounced.
		await packets.updateAnyPacketFrom(packet: heard(from: kept, hops: 2), activeDeviceNum: radioB)
		await packets.updateAnyPacketFrom(packet: heard(from: newlyHeardByA, hops: 0), activeDeviceNum: radioA)

		let keptStayed = try await packets.removeUnheardNode(kept, ofRadio: radioA)
		let newlyHeardStayed = try await packets.removeUnheardNode(newlyHeardByA, ofRadio: radioA)
		#expect(keptStayed)
		#expect(newlyHeardStayed)

		let context = ModelContext(container)
		let stored = try context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == kept })).first
		#expect(stored?.hopsAway == 2, "B's latest, not what B had saved")
		let observations = try context.fetch(FetchDescriptor<NodeObservationEntity>())
		#expect(observations.count == 2)
		#expect(observations.allSatisfy { $0.radioNum == radioB }, "A's observations go, the unsaved one too")
	}

	/// A packet heard over LoRa just now, `hops` away.
	private func heard(from num: Int64, hops: UInt32) -> MeshPacket {
		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.rxTime = UInt32(Date().timeIntervalSince1970)
		packet.rxRssi = -90
		packet.hopStart = 3
		packet.hopLimit = 3 - hops
		return packet
	}

	// MARK: Heard now

	@Test("A node heard over LoRa loses its marker for the radio that heard it, not for the others")
	func heardNowIsPerRadio() async throws {
		let container = try isolatedContainer("UnheardHeardNow")
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B, num: Int64 = 0x7E57_0406
		let setup = ModelContext(container)
		for radio in [radioA, radioB] {
			insertRadio(radio, in: setup)
			let observation = NodeObservationEntity(radioNum: radio, nodeNum: num)
			observation.heardOnCurrentLora = false
			setup.insert(observation)
		}
		insertNode(num, in: setup).heardOnCurrentLora = false
		try setup.save()

		let packets = MeshPackets(modelContainer: container)
		await packets.updateAnyPacketFrom(packet: heard(from: num, hops: 0), activeDeviceNum: radioA, reportsHeardOnCurrentLora: true)
		await packets.flushDebouncedSaves()

		#expect(RadioLoraAnswers.answer(of: num, radioNum: radioA, container: container)?.heard == true, "Remove Them's re-check must see it was heard")
		#expect(RadioLoraAnswers.answer(of: num, radioNum: radioB, container: container)?.heard == false, "B hasn't heard it")
	}
}
