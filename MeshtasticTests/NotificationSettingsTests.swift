//
//  NotificationSettingsTests.swift
//  MeshtasticTests
//
//  Coverage for the `tapbackNotifications` and `waypointNotifications` toggles in
//  Settings.bundle. Both notification types used to fire unconditionally, so the only way
//  to stop them was to turn off notifications for the whole app.
//
//  Each toggle gets both directions: off must suppress the notification, on must still
//  deliver it. Without the "on" companion a broken gate that suppresses everything would
//  still look green.
//
//  Neither direction waits on a timer. The "on" cases await the scheduler actually being
//  called; the "off" cases await a MainActor hop enqueued after the ingest path's own — see
//  `NotificationRecorder` and `drainScheduledNotificationWork()` below.
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Notification settings", .serialized, .timeLimit(.minutes(1)))
struct NotificationSettingsTests {

	private let connectedNode: Int64 = 0x0000_0D01
	private let peerNode: Int64 = 0x0000_0D02

	// MARK: - Packet builders

	/// A tapback: a text-message packet carrying an emoji, flagged `emoji == 1`, whose
	/// `replyID` points at the message being reacted to.
	private func reactionPacket(id: UInt32, from: UInt32, to: UInt32, replyID: UInt32, emoji: String = "👍") -> MeshPacket {
		var data = DataMessage()
		data.portnum = .textMessageApp
		data.payload = Data(emoji.utf8)
		data.emoji = 1
		data.replyID = replyID

		var packet = MeshPacket()
		packet.id = id
		packet.from = from
		packet.to = to
		packet.channel = 0
		packet.decoded = data
		return packet
	}

	private func textPacket(id: UInt32, from: UInt32, to: UInt32, text: String = "hello mesh") -> MeshPacket {
		var data = DataMessage()
		data.portnum = .textMessageApp
		data.payload = Data(text.utf8)

		var packet = MeshPacket()
		packet.id = id
		packet.from = from
		packet.to = to
		packet.channel = 0
		packet.decoded = data
		return packet
	}

	private func waypointPacket(id: UInt32, from: UInt32) -> MeshPacket {
		var waypoint = Waypoint()
		waypoint.id = id
		waypoint.name = "Trailhead"
		waypoint.description_p = "Meet here"
		waypoint.latitudeI = 377_000_000
		waypoint.longitudeI = -1_223_000_000
		waypoint.icon = 128_205 // 📍

		var data = DataMessage()
		data.portnum = .waypointApp
		data.payload = (try? waypoint.serializedData()) ?? Data()

		var packet = MeshPacket()
		packet.id = id
		packet.from = from
		packet.to = Constants.maximumNodeNum
		packet.decoded = data
		return packet
	}

	// MARK: - Fixtures

	@MainActor
	private func makeMeshPackets(recorder: NotificationRecorder) async -> MeshPackets {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		await mp.replaceNotificationScheduler { @MainActor @Sendable notifications in
			recorder.record(notifications)
		}
		return mp
	}

	/// Deterministic completion boundary for the cases that expect *no* notification.
	///
	/// The ingest path creates its `Task { @MainActor in ... }` before returning, so that job is
	/// already queued on the MainActor by the time the `await` on the packet call resumes. A
	/// MainActor hop enqueued after it therefore runs after it: when this returns, any
	/// notification that was going to be scheduled has been. No sleeping, no timing guess.
	@MainActor
	private func drainScheduledNotificationWork() async {
		await Task { @MainActor in }.value
	}

	/// Seed both ends of a DM plus the message the tapback reacts to.
	///
	/// All three are load-bearing: the DM notification branch is gated on
	/// `fromUser != nil && toUser != nil`, and `reactionNotificationBody` returns nil for a
	/// tapback whose reacted-to message isn't stored locally (the phantom-tapback guard from
	/// #2039). Miss any of them and a "no notification" assertion passes for the wrong reason —
	/// which is also why the save is `try` rather than `try?`.
	@MainActor
	private func seedDirectMessageConversation(originalMessageId: Int64) throws {
		let ctx = ModelContext(sharedModelContainer)

		let sender = UserEntity()
		ctx.insert(sender)
		sender.num = peerNode
		sender.longName = "Peer"
		sender.shortName = "PR"
		sender.mute = false

		let receiver = UserEntity()
		ctx.insert(receiver)
		receiver.num = connectedNode
		receiver.longName = "Me"
		receiver.shortName = "ME"
		receiver.mute = false

		let original = MessageEntity()
		ctx.insert(original)
		original.messageId = originalMessageId
		original.messagePayload = "See you soon"
		original.isEmoji = false
		try ctx.save()
	}

	@MainActor
	private func seedChannelConversation(originalMessageId: Int64) throws {
		let ctx = ModelContext(sharedModelContainer)

		let sender = UserEntity()
		ctx.insert(sender)
		sender.num = peerNode
		sender.longName = "Peer"
		sender.shortName = "PR"
		sender.mute = false

		let channel = ChannelEntity()
		ctx.insert(channel)
		channel.index = 0
		channel.mute = false
		channel.name = "Primary"

		let myInfo = MyInfoEntity()
		ctx.insert(myInfo)
		myInfo.myNodeNum = connectedNode
		myInfo.channels = [channel]

		let original = MessageEntity()
		ctx.insert(original)
		original.messageId = originalMessageId
		original.messagePayload = "On my way"
		original.isEmoji = false
		try ctx.save()
	}

	// MARK: - Tapback notifications

	@Test @MainActor func tapbackNotificationsOff_directMessage_schedulesNothing() async throws {
		let previous = UserDefaults.tapbackNotifications
		UserDefaults.tapbackNotifications = false
		defer { UserDefaults.tapbackNotifications = previous }

		let recorder = NotificationRecorder()
		let mp = await makeMeshPackets(recorder: recorder)
		let originalId: Int64 = 0x00D0_0001
		let reactionId: Int64 = 0x00D0_0002
		try seedDirectMessageConversation(originalMessageId: originalId)

		await mp.textMessageAppPacket(
			packet: reactionPacket(id: UInt32(reactionId), from: UInt32(peerNode), to: UInt32(connectedNode), replyID: UInt32(originalId)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		await drainScheduledNotificationWork()
		#expect(recorder.notifications.isEmpty, "tapback must not notify when the setting is off")
		// The reaction is still stored — the toggle silences the notification, nothing else.
		let ctx = ModelContext(sharedModelContainer)
		let stored = try ctx.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == reactionId }))
		#expect(stored.first?.isEmoji == true, "the reaction itself must still be saved")
	}

	@Test @MainActor func tapbackNotificationsOn_directMessage_stillNotifies() async throws {
		let previous = UserDefaults.tapbackNotifications
		UserDefaults.tapbackNotifications = true
		defer { UserDefaults.tapbackNotifications = previous }

		let recorder = NotificationRecorder()
		let mp = await makeMeshPackets(recorder: recorder)
		let originalId: Int64 = 0x00D0_0011
		let reactionId: Int64 = 0x00D0_0012
		try seedDirectMessageConversation(originalMessageId: originalId)

		await mp.textMessageAppPacket(
			packet: reactionPacket(id: UInt32(reactionId), from: UInt32(peerNode), to: UInt32(connectedNode), replyID: UInt32(originalId)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		await recorder.waitForNextNotification()
		#expect(recorder.notifications.count == 1)
		// The reacted-to text proves this is the reaction body, not a plain message notification.
		#expect(recorder.notifications.first?.content.contains("👍") == true)
		#expect(recorder.notifications.first?.content.contains("See you soon") == true)
		// Tapback actions must target the original message, not the reaction packet.
		#expect(recorder.notifications.first?.replyMessageId == originalId)
	}

	@Test @MainActor func tapbackNotificationsOff_channelMessage_schedulesNothing() async throws {
		let previousTapback = UserDefaults.tapbackNotifications
		let previousChannel = UserDefaults.channelMessageNotifications
		UserDefaults.tapbackNotifications = false
		UserDefaults.channelMessageNotifications = true
		defer {
			UserDefaults.tapbackNotifications = previousTapback
			UserDefaults.channelMessageNotifications = previousChannel
		}

		let recorder = NotificationRecorder()
		let mp = await makeMeshPackets(recorder: recorder)
		let originalId: Int64 = 0x00D0_0021
		let reactionId: Int64 = 0x00D0_0022
		try seedChannelConversation(originalMessageId: originalId)

		await mp.textMessageAppPacket(
			packet: reactionPacket(id: UInt32(reactionId), from: UInt32(peerNode), to: Constants.maximumNodeNum, replyID: UInt32(originalId)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		await drainScheduledNotificationWork()
		#expect(recorder.notifications.isEmpty, "channel tapback must not notify when the setting is off")
	}

	@Test @MainActor func tapbackNotificationsOff_leavesPlainMessagesAlone() async throws {
		let previousTapback = UserDefaults.tapbackNotifications
		UserDefaults.tapbackNotifications = false
		defer { UserDefaults.tapbackNotifications = previousTapback }

		let recorder = NotificationRecorder()
		let mp = await makeMeshPackets(recorder: recorder)
		let originalId: Int64 = 0x00D0_0031
		let messageId: Int64 = 0x00D0_0032
		try seedDirectMessageConversation(originalMessageId: originalId)

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(messageId), from: UInt32(peerNode), to: UInt32(connectedNode)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		await recorder.waitForNextNotification()
		#expect(recorder.notifications.first?.content == "hello mesh", "the tapback toggle must not silence ordinary messages")
	}

	// MARK: - Waypoint notifications

	@Test @MainActor func waypointNotificationsOff_schedulesNothing() async throws {
		let previous = UserDefaults.waypointNotifications
		UserDefaults.waypointNotifications = false
		defer { UserDefaults.waypointNotifications = previous }

		let recorder = NotificationRecorder()
		let mp = await makeMeshPackets(recorder: recorder)
		let waypointId: Int64 = 0x00D0_0041

		await mp.waypointPacket(packet: waypointPacket(id: UInt32(waypointId), from: UInt32(peerNode)))

		await drainScheduledNotificationWork()
		#expect(recorder.notifications.isEmpty, "a received waypoint must not notify when the setting is off")
		// The waypoint is still stored and still shows on the map — only the alert is suppressed.
		let ctx = ModelContext(sharedModelContainer)
		let stored = try ctx.fetch(FetchDescriptor<WaypointEntity>(predicate: #Predicate { $0.id == waypointId }))
		#expect(stored.isEmpty == false, "the waypoint itself must still be saved")
	}

	@Test @MainActor func waypointNotificationsOn_stillNotifies() async {
		let previous = UserDefaults.waypointNotifications
		UserDefaults.waypointNotifications = true
		defer { UserDefaults.waypointNotifications = previous }

		let recorder = NotificationRecorder()
		let mp = await makeMeshPackets(recorder: recorder)
		let waypointId: Int64 = 0x00D0_0051

		await mp.waypointPacket(packet: waypointPacket(id: UInt32(waypointId), from: UInt32(peerNode)))

		await recorder.waitForNextNotification()
		#expect(recorder.notifications.count == 1)
		#expect(recorder.notifications.first?.target == "map")
		#expect(recorder.notifications.first?.path == "meshtastic:///map?waypointid=\(waypointId)")
	}

	// MARK: - Defaults

	/// Both toggles default to on, matching today's behavior for anyone who never opens Settings.
	/// The Settings.bundle DefaultValue only applies once the user visits the pane, so the
	/// `@UserDefault` default is what actually governs a fresh install.
	@Test func togglesDefaultToOn() async {
		let store = UserDefaults.standard
		let previousTapback = store.object(forKey: UserDefaults.Keys.tapbackNotifications.rawValue)
		let previousWaypoint = store.object(forKey: UserDefaults.Keys.waypointNotifications.rawValue)
		defer {
			store.set(previousTapback, forKey: UserDefaults.Keys.tapbackNotifications.rawValue)
			store.set(previousWaypoint, forKey: UserDefaults.Keys.waypointNotifications.rawValue)
		}

		store.removeObject(forKey: UserDefaults.Keys.tapbackNotifications.rawValue)
		store.removeObject(forKey: UserDefaults.Keys.waypointNotifications.rawValue)

		#expect(UserDefaults.tapbackNotifications == true)
		#expect(UserDefaults.waypointNotifications == true)
	}
}

// MARK: - Test helpers

/// Records what the ingest path scheduled and lets a test await the next one, so the
/// "must notify" cases wait on the real signal rather than a sleep. The suite's one-minute
/// time limit bounds the wait if a regression means the notification never arrives.
@MainActor
final class NotificationRecorder {
	private(set) var notifications: [MeshNotification] = []
	private var waiters: [CheckedContinuation<Void, Never>] = []

	func record(_ scheduled: [MeshNotification]) {
		notifications.append(contentsOf: scheduled)
		let pending = waiters
		waiters.removeAll()
		for waiter in pending { waiter.resume() }
	}

	/// Returns as soon as at least one notification has been recorded — immediately if one
	/// already arrived before the caller got here.
	func waitForNextNotification() async {
		guard notifications.isEmpty else { return }
		await withCheckedContinuation { waiters.append($0) }
	}
}
