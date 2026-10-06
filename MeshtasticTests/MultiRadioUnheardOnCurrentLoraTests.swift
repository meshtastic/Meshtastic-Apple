//
//  MultiRadioUnheardOnCurrentLoraTests.swift
//  MeshtasticTests
//
//  main's #2575 stores NodeInfo.heard_on_current_lora on the shared node rows, from the one
//  connected radio. Feature 021: only the only radio connected answers it, once the stored
//  answers are its own, and a second radio puts every answer back to unknown, so no window shows
//  another radio's answers. The unheard notice offers only nodes the window's radio had (review
//  V35). Scripted radios as in `MultiRadioConnectFlowTests`.
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

	private func node(_ num: UInt32) -> NodeInfoEntity? {
		let context = ModelContext(PersistenceController.shared.container)
		let nodeNum = Int64(num)
		return try? context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })).first
	}

	/// A node in the shared store with an answer no connected radio gave: one left by a radio
	/// connected on its own earlier, on a node only that radio observed.
	private func storeAnswer(_ heard: Bool, onNode num: UInt32) throws {
		let context = ModelContext(PersistenceController.shared.container)
		let node = NodeInfoEntity()
		node.id = Int64(num)
		node.num = Int64(num)
		node.heardOnCurrentLora = heard
		context.insert(node)
		try context.save()
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
		try await ConnectFlowSupport.waitUntil { manager.nodeDatabaseSavedAt != nil || !manager.reportsHeardOnCurrentLora }
		return Radios(manager: manager, firstNum: firstNum, secondNum: secondNum, secondDevice: secondDevice)
	}

	@Test("The only radio's answers are stored, as on main; a second radio puts every answer back to unknown")
	func secondRadioClearsTheAnswers() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager
		let heardByFirst = radios.firstNum &+ 1
		let onlyAnOfflineRadio = radios.firstNum &+ 0x200

		#expect(manager.heardOnCurrentLoraSession === manager.activeConnection)
		#expect(HeardOnCurrentLoraAnswers.radioNum() == Int64(radios.firstNum), "claimed when it connected on its own")
		#expect(manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)))
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.secondNum)))
		#expect(manager.nodeDatabaseSavedAt != nil)
		// The scripted dump leaves the field at its default, false: not heard on these settings.
		try await ConnectFlowSupport.waitUntil { node(heardByFirst)?.heardOnCurrentLora == false }
		#expect(node(heardByFirst)?.heardOnCurrentLora == false)
		try storeAnswer(false, onNode: onlyAnOfflineRadio)

		try await manager.connectAdditionalRadio(radios.secondDevice)
		#expect(manager.soleConnectedSession == nil)
		#expect(manager.heardOnCurrentLoraSession == nil)
		#expect(!manager.reportsHeardOnCurrentLora)
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)), "no window offers the notice")
		#expect(manager.nodeDatabaseSavedAt == nil)
		#expect(HeardOnCurrentLoraAnswers.radioNum() == 0, "no radio's answers are kept")
		try await ConnectFlowSupport.waitUntil {
			node(heardByFirst)?.heardOnCurrentLora == nil && node(onlyAnOfflineRadio)?.heardOnCurrentLora == nil
		}
		#expect(node(heardByFirst)?.heardOnCurrentLora == nil, "the first radio's answer doesn't stand for the second's")
		#expect(node(radios.secondNum &+ 1)?.heardOnCurrentLora == nil, "the second radio's answers aren't stored")
		#expect(node(onlyAnOfflineRadio)?.heardOnCurrentLora == nil, "nor a radio's that isn't connected (review V35-2)")
		manager.additionalRadioReconnects.values.forEach { $0.cancel() }
		try await manager.disconnect()
	}

	@Test("A LoRa change asks for the node database again only from the only radio connected")
	func loraChangeRefreshOnlyForTheOnlyRadio() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager

		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: Int64(radios.secondNum))
		#expect(!manager.awaitingNodeDatabaseAfterLoRaChange, "not the radio whose answers are kept")
		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: Int64(radios.firstNum))
		#expect(manager.awaitingNodeDatabaseAfterLoRaChange, "the one radio, as on main")

		try await manager.connectAdditionalRadio(radios.secondDevice)
		#expect(!manager.awaitingNodeDatabaseAfterLoRaChange, "a second radio stands the wait down")
		manager.refreshNodeDatabaseAfterLoRaChange(forRadio: Int64(radios.firstNum))
		#expect(!manager.awaitingNodeDatabaseAfterLoRaChange)
	}

	@Test("A radio whose firmware doesn't send the field answers nothing, alone or not")
	func olderFirmwareAnswersNothing() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: "2.7.15.567b8ea")
		let manager = radios.manager

		#expect(manager.soleConnectedSession === manager.activeConnection)
		#expect(manager.heardOnCurrentLoraSession == nil)
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)))
		#expect(node(radios.firstNum &+ 1)?.heardOnCurrentLora == nil)
		#expect(HeardOnCurrentLoraAnswers.radioNum() == Int64(radios.firstNum), "it still takes the answers over, so its window shows none of another radio's")
	}

	@Test("Another radio connected on its own doesn't take the answers of the radio that was")
	func anotherRadioAloneClearsTheAnswers() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radios = try await connectFirst(firmware: reportingFirmware)
		let manager = radios.manager
		let heardByFirst = radios.firstNum &+ 1
		try await ConnectFlowSupport.waitUntil { node(heardByFirst)?.heardOnCurrentLora == false }

		try await manager.disconnect()
		#expect(node(heardByFirst)?.heardOnCurrentLora == false, "kept while nothing else connects, as on main")
		#expect(HeardOnCurrentLoraAnswers.radioNum() == Int64(radios.firstNum))

		try await manager.connect(to: radios.secondDevice)
		try await ConnectFlowSupport.waitUntil { manager.nodeDatabaseSavedAt != nil }
		#expect(HeardOnCurrentLoraAnswers.radioNum() == Int64(radios.secondNum))
		#expect(manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.secondNum)))
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radios.firstNum)))
		#expect(node(heardByFirst)?.heardOnCurrentLora == nil, "the first radio's answer isn't the second's")
		#expect(node(radios.secondNum &+ 1)?.heardOnCurrentLora == false, "the second radio's own answers are stored")
		try await manager.disconnect()
	}

	@Test("A radio on its own answers once the stored answers are its own; claiming them clears another's")
	func answersNeedTheClaim() async throws {
		let saved = SavedDefaults()
		defer { saved.restore() }
		let radioNum = ConnectFlowSupport.uniqueNodeNum()
		let leftOver = radioNum &+ 0x200
		var device = ConnectFlowSupport.device()
		device.num = Int64(radioNum)
		device.firmwareVersion = reportingFirmware
		let radio = ScriptedRadio(nodeNum: radioNum, firmwareVersion: reportingFirmware)
		let manager = ConnectFlowSupport.makeManager(ScriptedTransport(radio: radio))
		let session = RadioSession(device: device, connection: radio)
		manager.activeConnection = session
		HeardOnCurrentLoraAnswers.set(Int64(radioNum &+ 0x300))
		try storeAnswer(false, onNode: leftOver)

		#expect(manager.heardOnCurrentLoraSession == nil, "the stored answers are another radio's")
		#expect(!manager.reportsHeardOnCurrentLora(forRadio: Int64(radioNum)), "so its window offers nothing by them")

		await manager.claimHeardOnCurrentLora(for: session)
		#expect(HeardOnCurrentLoraAnswers.radioNum() == Int64(radioNum))
		#expect(manager.heardOnCurrentLoraSession === session)
		#expect(manager.reportsHeardOnCurrentLora(forRadio: Int64(radioNum)))
		#expect(node(leftOver)?.heardOnCurrentLora == nil, "the other radio's answers go first")
	}

	@Test("A renumbered radio keeps its answers")
	func renumberKeepsTheAnswers() throws {
		let store = try #require(UserDefaults(suiteName: "MultiRadioUnheardOnCurrentLoraTests.renumber"))
		store.removePersistentDomain(forName: "MultiRadioUnheardOnCurrentLoraTests.renumber")
		HeardOnCurrentLoraAnswers.recordIfNeeded(in: store)
		#expect(HeardOnCurrentLoraAnswers.radioNum(in: store) == PreferredRadio.nodeNum, "a store from before 021 holds the preferred radio's")
		HeardOnCurrentLoraAnswers.set(0x0A0A, in: store)
		HeardOnCurrentLoraAnswers.recordIfNeeded(in: store)
		#expect(HeardOnCurrentLoraAnswers.radioNum(in: store) == 0x0A0A, "recorded once")
		HeardOnCurrentLoraAnswers.renumber(from: 0x0B0B, to: 0x0C0C, in: store)
		#expect(HeardOnCurrentLoraAnswers.radioNum(in: store) == 0x0A0A, "another radio's renumber leaves it")
		HeardOnCurrentLoraAnswers.renumber(from: 0x0A0A, to: 0x0D0D, in: store)
		#expect(HeardOnCurrentLoraAnswers.radioNum(in: store) == 0x0D0D)
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
		#expect(left.first?.heardOnCurrentLora == nil, "its answer was A's")
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

	@Test("A node several radios observed loses its marker when the radio whose answers are kept hears it")
	func aggregatedNodeHeardNowIsMarkedHeard() async throws {
		let container = try isolatedContainer("UnheardAggregated")
		let radioA: Int64 = 0x0A0A, radioB: Int64 = 0x0B0B, num: Int64 = 0x7E57_0406
		let setup = ModelContext(container)
		for radio in [radioA, radioB] {
			insertRadio(radio, in: setup)
			setup.insert(NodeObservationEntity(radioNum: radio, nodeNum: num))
		}
		insertNode(num, in: setup).heardOnCurrentLora = false
		try setup.save()

		let packets = MeshPackets(modelContainer: container)
		var packet = MeshPacket()
		packet.from = UInt32(num)
		packet.rxTime = UInt32(Date().timeIntervalSince1970)
		packet.rxRssi = -90
		await packets.updateAnyPacketFrom(packet: packet, activeDeviceNum: radioA, reportsHeardOnCurrentLora: true)
		await packets.flushDebouncedSaves()

		let stored = try ModelContext(container).fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })).first
		#expect(stored?.heardOnCurrentLora == true, "Remove Them's re-check must see it was heard")
	}
}
