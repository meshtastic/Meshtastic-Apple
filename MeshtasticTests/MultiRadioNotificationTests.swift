//
//  MultiRadioNotificationTests.swift
//  MeshtasticTests
//
//  Feature 021 (T158): a channel message heard by several of the user's radios is handled by
//  whichever delivers it first, so channel mute and @mentions must not depend on which that was.
//

import Foundation
import MeshtasticProtobufs
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Multi-radio notifications", .serialized)
@MainActor
struct MultiRadioNotificationTests {

	private let radioA: Int64 = 0x0A0A_0A0A
	private let radioB: Int64 = 0x0B0B_0B0B
	private let sender: Int64 = 0x0000_0D01

	private func makeContainer() throws -> ModelContainer {
		let schema = Schema(versionedSchema: MeshtasticSchema.current)
		let config = ModelConfiguration("MultiRadioNotificationTests-\(UUID().uuidString)", schema: schema, isStoredInMemoryOnly: true, allowsSave: true)
		return try ModelContainer(for: schema, configurations: config)
	}

	/// Radios A and B, both with the channel "Family" (same key) in slot 0; A's is muted when asked.
	private func seed(_ container: ModelContainer, mutedOnA: Bool) throws {
		let context = ModelContext(container)
		for (radio, muted) in [(radioA, mutedOnA), (radioB, false)] {
			let channel = ChannelEntity()
			channel.index = 0
			channel.name = "Family"
			channel.channelKey = "c1:family"
			channel.mute = muted
			context.insert(channel)
			let myInfo = MyInfoEntity()
			myInfo.myNodeNum = radio
			myInfo.channels = [channel]
			context.insert(myInfo)
		}
		let user = UserEntity()
		user.num = sender
		user.longName = "Sender"
		context.insert(user)
		try context.save()
	}

	private func packet(id: UInt32, text: String) -> MeshPacket {
		var data = DataMessage()
		data.portnum = .textMessageApp
		data.payload = Data(text.utf8)
		var packet = MeshPacket()
		packet.id = id
		packet.from = UInt32(sender)
		packet.to = Constants.maximumNodeNum
		packet.decoded = data
		return packet
	}

	private func deliver(_ packet: MeshPacket, through radio: Int64, in container: ModelContainer) async -> [MeshNotification] {
		let scheduled = MainActorBox<[MeshNotification]>([])
		let packets = MeshPackets(modelContainer: container)
		await packets.replaceNotificationScheduler { @MainActor @Sendable notifications in
			scheduled.value.append(contentsOf: notifications)
		}
		let noAppState: AppState? = nil
		await packets.textMessageAppPacket(packet: packet, wantRangeTestPackets: false, connectedNode: radio, appState: noAppState)
		try? await Task.sleep(for: .milliseconds(100))
		return scheduled.value
	}

	@Test("A channel muted on one radio stays quiet when another radio delivers its message")
	func muteHoldsAcrossRadios() async throws {
		let previous = UserDefaults.channelMessageNotifications
		UserDefaults.channelMessageNotifications = true
		defer { UserDefaults.channelMessageNotifications = previous }
		let container = try makeContainer()
		try seed(container, mutedOnA: true)

		#expect(await deliver(packet(id: 0x7001, text: "dinner"), through: radioB, in: container).isEmpty)

		// The companion: unmuted everywhere, it notifies.
		let unmuted = try makeContainer()
		try seed(unmuted, mutedOnA: false)
		#expect(await deliver(packet(id: 0x7002, text: "dinner"), through: radioB, in: unmuted).count == 1)
	}

	@Test("A mention of one of the user's radios notifies whichever radio delivers it")
	func mentionOfAnyRadio() async throws {
		let previous = UserDefaults.channelMessageNotifications
		UserDefaults.channelMessageNotifications = false
		defer { UserDefaults.channelMessageNotifications = previous }
		let container = try makeContainer()
		try seed(container, mutedOnA: false)

		let mention = "hi @!\(String(format: "%08x", radioA))"
		#expect(await deliver(packet(id: 0x7003, text: mention), through: radioB, in: container).count == 1)
		#expect(await deliver(packet(id: 0x7004, text: "no mention"), through: radioB, in: container).isEmpty)
	}
}
