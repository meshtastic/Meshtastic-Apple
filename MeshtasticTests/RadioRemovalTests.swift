//
//  RadioRemovalTests.swift
//  MeshtasticTests
//
//  Feature 021 (D-18, T147): resetting or removing one of several radios removes only that
//  radio's data, keeps nodes another radio on the same mesh hears, and keeps the history of
//  channels another radio has.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Resetting or removing one of several radios")
@MainActor
struct RadioRemovalTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let onlyA: Int64 = 0x1111
	private let both: Int64 = 0x2222
	private let onlyB: Int64 = 0x3333

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("RadioRemovalTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		return try ModelContainer(for: schema, configurations: config)
	}

	@discardableResult
	private func makeNode(_ num: Int64, favorite: Bool = false, in context: ModelContext) -> NodeInfoEntity {
		let node = NodeInfoEntity()
		node.num = num
		node.id = num
		node.favorite = favorite
		context.insert(node)
		let user = UserEntity()
		user.num = num
		user.longName = "Node \(num)"
		user.userNode = node
		context.insert(user)
		return node
	}

	/// One of the user's radios on the US LongFast mesh (or `preset`), with `channels` by slot.
	private func makeRadio(_ num: Int64, preset: Config.LoRaConfig.ModemPreset = .longFast, channels: [Int32: String] = [:], connected: Bool = true, in context: ModelContext) {
		let node = makeNode(num, in: context)
		let lora = LoRaConfigEntity()
		lora.regionCode = Int32(Config.LoRaConfig.RegionCode.us.rawValue)
		lora.usePreset = true
		lora.modemPreset = Int32(preset.rawValue)
		context.insert(lora)
		node.loRaConfig = lora
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = num
		myInfo.myInfoNode = node
		myInfo.lastConnected = connected ? .now : nil
		context.insert(myInfo)
		let primary = ChannelEntity()
		primary.index = 0
		primary.psk = Data([1])
		primary.role = Int32(Channel.Role.primary.rawValue)
		primary.myInfoChannel = myInfo
		context.insert(primary)
		for (index, name) in channels {
			let channel = ChannelEntity()
			channel.index = index
			channel.name = name
			channel.psk = Data(repeating: 7, count: 32)
			channel.role = Int32(Channel.Role.secondary.rawValue)
			channel.myInfoChannel = myInfo
			context.insert(channel)
		}
	}

	private func observe(_ nodeNum: Int64, by radioNum: Int64, hops: Int32 = 1, in context: ModelContext) {
		let observation = NodeObservationEntity(radioNum: radioNum, nodeNum: nodeNum)
		observation.hopsAway = hops
		observation.lastHeard = .now
		context.insert(observation)
	}

	private func message(_ id: Int64, radio: Int64, to toNum: Int64 = MultiRadioBackfill.broadcastNum, slot: Int32 = 0, key: String? = nil, in context: ModelContext) {
		let message = MessageEntity()
		message.messageId = id
		message.localNodeNum = radio
		message.toNum = toNum
		message.channel = slot
		message.channelKey = key
		context.insert(message)
	}

	private func keys(of radio: Int64, in context: ModelContext) throws -> [Int32: String] {
		try MultiRadioBackfill.channelKeysByIndex(for: radio, in: context, updateStored: false)
	}

	/// A and B, with nodes heard by A only, by both and by B only, each radio's reception of a
	/// packet, and messages: A's DM, A's messages on the primary (both have it) and on "Hiking"
	/// (A only), and B's message on the primary.
	private func seed(bPreset: Config.LoRaConfig.ModemPreset = .longFast, in context: ModelContext) throws -> [Int32: String] {
		makeRadio(radioA, channels: [1: "Hiking"], in: context)
		makeRadio(radioB, preset: bPreset, in: context)
		makeNode(onlyA, favorite: false, in: context)
		makeNode(both, in: context)
		makeNode(onlyB, in: context)
		observe(onlyA, by: radioA, in: context)
		observe(both, by: radioA, hops: 0, in: context)
		observe(both, by: radioB, hops: 4, in: context)
		observe(onlyB, by: radioB, in: context)
		// A hears B's own node; B doesn't observe itself.
		observe(radioB, by: radioA, in: context)
		context.insert(PacketReceptionEntity(radioNum: radioA, fromNum: both, packetId: 1))
		context.insert(PacketReceptionEntity(radioNum: radioB, fromNum: both, packetId: 1))
		try context.save()
		let keysA = try keys(of: radioA, in: context)
		message(1, radio: radioA, to: both, in: context)
		message(2, radio: radioA, slot: 0, key: keysA[0], in: context)
		message(3, radio: radioA, slot: 1, key: keysA[1], in: context)
		message(4, radio: radioB, slot: 0, key: keysA[0], in: context)
		// Not backfilled yet: placed by A's slot 1.
		message(5, radio: radioA, slot: 1, key: nil, in: context)
		try context.save()
		return keysA
	}

	private func rows<T: PersistentModel>(_ type: T.Type, in container: ModelContainer) throws -> [T] {
		try ModelContext(container).fetch(FetchDescriptor<T>())
	}

	// MARK: - Which radios the store holds

	@Test("Stray radio rows from an older store don't make a single-radio user a multi-radio one")
	func strayRadiosDontCount() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		makeRadio(radioA, in: context)
		makeRadio(radioB, connected: false, in: context)
		try context.save()
		let packets = MeshPackets(modelContainer: container)

		#expect(await packets.storedRadios().map(\.nodeNum) == [radioA])

		// A merged backup's radio has observations, so it counts.
		observe(onlyB, by: radioB, in: context)
		try context.save()
		#expect(await packets.storedRadios().map(\.nodeNum) == [radioA, radioB])
	}

	// MARK: - Same mesh

	@Test("Radios are on the same mesh with the same region, modulation and frequency")
	func sameMesh() throws {
		let context = ModelContext(try makeContainer())
		func lora(_ preset: Config.LoRaConfig.ModemPreset = .longFast, usePreset: Bool = true, override: Float = 0, bandwidth: Int32 = 250) -> LoRaConfigEntity {
			let lora = LoRaConfigEntity()
			lora.regionCode = Int32(Config.LoRaConfig.RegionCode.us.rawValue)
			lora.usePreset = usePreset
			lora.modemPreset = Int32(preset.rawValue)
			lora.bandwidth = bandwidth
			lora.spreadFactor = 11
			lora.codingRate = 5
			lora.overrideFrequency = override
			context.insert(lora)
			return lora
		}
		let longFast = MeshNetwork(lora: lora(), primaryChannelName: nil)
		#expect(longFast != nil)
		// An empty primary name is the preset's name, so it's the same slot.
		#expect(MeshNetwork(lora: lora(), primaryChannelName: "LongFast") == longFast)
		// Another primary name hashes to another slot, another frequency.
		#expect(MeshNetwork(lora: lora(), primaryChannelName: "Family") != longFast)
		#expect(MeshNetwork(lora: lora(.mediumFast), primaryChannelName: nil) != longFast)
		// A frequency override pins the frequency, whatever the name.
		#expect(MeshNetwork(lora: lora(override: 906.875), primaryChannelName: "A") == MeshNetwork(lora: lora(override: 906.875), primaryChannelName: "B"))
		// Without a preset, the modulation is bandwidth, spreading factor and coding rate.
		#expect(MeshNetwork(lora: lora(usePreset: false), primaryChannelName: nil) != MeshNetwork(lora: lora(usePreset: false, bandwidth: 125), primaryChannelName: nil))
		#expect(MeshNetwork(lora: nil, primaryChannelName: nil) == nil)
	}

	// MARK: - Reset

	@Test("A reset on a shared mesh keeps the nodes and, unless asked, the messages")
	func resetOnSharedMesh() async throws {
		let container = try makeContainer()
		_ = try seed(in: ModelContext(container))
		let packets = MeshPackets(modelContainer: container)

		let result = await packets.removeRadioData(radioA, .reset(preserveFavorites: true, deleteMessages: false))

		#expect(result.nodes == 0)
		#expect(result.messages == 0)
		#expect(Set(try rows(NodeInfoEntity.self, in: container).map(\.num)) == [radioA, radioB, onlyA, both, onlyB])
		#expect(try rows(NodeObservationEntity.self, in: container).allSatisfy { $0.radioNum == radioB })
		#expect(try rows(PacketReceptionEntity.self, in: container).map(\.radioNum) == [radioB])
		#expect(try rows(MessageEntity.self, in: container).count == 5)
		#expect(try rows(MyInfoEntity.self, in: container).count == 2)
		// The node both heard now shows B's view.
		#expect(try rows(NodeInfoEntity.self, in: container).first { $0.num == both }?.hopsAway == 4)
	}

	@Test("A reset on a mesh of its own removes the nodes only that radio heard")
	func resetOnOwnMesh() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		_ = try seed(bPreset: .mediumFast, in: context)
		let favorite = Int64(0x4444)
		makeNode(favorite, favorite: true, in: context)
		observe(favorite, by: radioA, in: context)
		try context.save()
		let packets = MeshPackets(modelContainer: container)

		let result = await packets.removeRadioData(radioA, .reset(preserveFavorites: true, deleteMessages: false))

		#expect(result.nodes == 1)
		// Not the other radio's own node, which only A heard; the favorite is kept.
		#expect(Set(try rows(NodeInfoEntity.self, in: container).map(\.num)) == [radioA, radioB, both, onlyB, favorite])

		let again = try makeContainer()
		let againContext = ModelContext(again)
		_ = try seed(bPreset: .mediumFast, in: againContext)
		makeNode(favorite, favorite: true, in: againContext)
		observe(favorite, by: radioA, in: againContext)
		try againContext.save()
		await MeshPackets(modelContainer: again).removeRadioData(radioA, .reset(preserveFavorites: false, deleteMessages: false))
		#expect(!(try rows(NodeInfoEntity.self, in: again).contains { $0.num == favorite }))
	}

	@Test("After a reset, a node left with one old observation keeps what it showed")
	func oldSingleObservationDoesNotTakeOver() async throws {
		let container = try makeContainer()
		let context = ModelContext(container)
		_ = try seed(in: context)
		let now = Date()
		let node = try #require(try context.fetch(FetchDescriptor<NodeInfoEntity>()).first { $0.num == both })
		node.lastHeard = now
		node.hopsAway = 0
		for observation in try context.fetch(FetchDescriptor<NodeObservationEntity>()) where observation.nodeNum == both {
			observation.lastHeard = observation.radioNum == radioA ? now : now.addingTimeInterval(-90 * 86_400)
		}
		try context.save()

		await MeshPackets(modelContainer: container).removeRadioData(radioA, .reset(preserveFavorites: true, deleteMessages: false))

		let after = try #require(try rows(NodeInfoEntity.self, in: container).first { $0.num == both })
		#expect(after.lastHeard == now)
		#expect(after.hopsAway == 0, "B's months-old 4 hops don't replace it")
	}

	@Test("Deleting a reset radio's messages keeps channels another radio has")
	func resetDeletesMessages() async throws {
		let container = try makeContainer()
		_ = try seed(in: ModelContext(container))
		let packets = MeshPackets(modelContainer: container)

		let result = await packets.removeRadioData(radioA, .reset(preserveFavorites: true, deleteMessages: true))

		// The DM and both Hiking rows go; the primary keeps A's and B's messages.
		#expect(result.messages == 3)
		#expect(Set(try rows(MessageEntity.self, in: container).map(\.messageId)) == [2, 4])
	}

	// MARK: - Remove

	@Test("Removing a radio forgets it and deletes its messages")
	func removeRadio() async throws {
		let container = try makeContainer()
		_ = try seed(in: ModelContext(container))
		let packets = MeshPackets(modelContainer: container)

		await packets.removeRadioData(radioA, .remove)

		#expect(try rows(MyInfoEntity.self, in: container).map(\.myNodeNum) == [radioB])
		#expect(try rows(ChannelEntity.self, in: container).count == 1)
		#expect(Set(try rows(MessageEntity.self, in: container).map(\.messageId)) == [2, 4])
		// Nobody else hears A, so its own node goes; the rest stay (shared mesh).
		#expect(Set(try rows(NodeInfoEntity.self, in: container).map(\.num)) == [radioB, onlyA, both, onlyB])
		#expect(await packets.storedRadios().map(\.nodeNum) == [radioB])
	}
}
