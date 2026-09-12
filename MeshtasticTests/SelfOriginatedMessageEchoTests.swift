// SelfOriginatedMessageEchoTests.swift
// MeshtasticTests
//
// Repro for: sending a message to the mesh produces a notification for your own message.
//
// The radio can hand the phone a TEXT_MESSAGE_APP packet whose `from` is the connected node
// (our own rebroadcast heard back, an S&F echo, a second client on the same radio). Ingestion
// has no self-node guard, so it re-ingests the message we already stored at send time and
// schedules a notification for it.
//
// MessageEntity.messageId is @Attribute(.unique), so the echo *upserts* onto the sent row rather
// than duplicating it — which is why the symptom is a phantom notification (and a reset
// read/ACK state) rather than a doubled message bubble.
//
// Android guards this in MeshDataHandlerImpl.rememberDataPacket:
//   - findPacketsWithId(dataPacket.id) -> skip duplicates outright
//   - read = fromLocal || isFiltered   -> self-originated is never unread

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("Self-originated message echo")
struct SelfOriginatedMessageEchoTests {

	private let connectedNode: Int64 = 0x0000_0C01
	private let peerNode: Int64 = 0x0000_0C02

	private func textPacket(id: UInt32, from: UInt32, to: UInt32, channel: UInt32 = 0) -> MeshPacket {
		var data = DataMessage()
		data.portnum = .textMessageApp
		data.payload = Data("hello mesh".utf8)

		var packet = MeshPacket()
		packet.id = id
		packet.from = from
		packet.to = to
		packet.channel = channel
		packet.decoded = data
		return packet
	}

	private func detectionSensorPacket(id: UInt32, from: UInt32, to: UInt32) -> MeshPacket {
		var data = DataMessage()
		data.portnum = .detectionSensorApp
		data.payload = Data("motion detected".utf8)

		var packet = MeshPacket()
		packet.id = id
		packet.from = from
		packet.to = to
		packet.channel = 0
		packet.decoded = data
		return packet
	}

	@MainActor
	private func messages(withId id: Int64) -> [MessageEntity] {
		let ctx = ModelContext(sharedModelContainer)
		return (try? ctx.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == id }))) ?? []
	}

	/// Helper: build a MeshPackets instance with a notification-capturing scheduler.
	///
	/// Tests using this then `Task.sleep` briefly before asserting, because the production code
	/// schedules from inside a detached `Task { @MainActor in ... }` and there is no completion
	/// signal to await. If this suite ever flakes in CI, that sleep is the first thing to suspect:
	/// replace it with polling against a deadline rather than lengthening the sleep.
	@MainActor
	private func makeMeshPackets(scheduledNotifications: MainActorBox<[MeshNotification]>) async -> MeshPackets {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let box = scheduledNotifications
		await mp.replaceNotificationScheduler { @MainActor @Sendable notifications in
			box.value.append(contentsOf: notifications)
		}
		return mp
	}

	@MainActor
	private func makeMeshPackets(notificationRecorder: NotificationRecorder) async -> MeshPackets {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		await mp.replaceNotificationScheduler { @MainActor @Sendable notifications in
			notificationRecorder.record(notifications)
		}
		return mp
	}

	// MARK: - Existing repro tests

	/// The exact user-reported symptom: a broadcast we originated comes back from the radio and is
	/// ingested as an *unread inbound* message, which is the state that drives the notification.
	///
	/// Deliberately policy-neutral between the two candidate fixes — drop the packet outright, or
	/// ingest it read-and-silent the way Android's `read = fromLocal` rule does. Either satisfies
	/// this; only today's behavior (ingested, unread) fails it.
	@Test @MainActor func selfOriginatedBroadcast_isNeverIngestedUnread() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00C0_0001

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(connectedNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		#expect(messages(withId: id).first?.read != false, "a packet from our own node must never land as an unread inbound message")
	}

	/// The second half of the symptom: because messageId is unique, re-ingesting our own sent
	/// message upserts the row we wrote in sendMessage() and resets the fields that path set —
	/// `read = true` becomes false (bumping the unread badge) and `receivedACK` is cleared
	/// (dropping the delivered indicator).
	@Test @MainActor func selfOriginatedEcho_doesNotClobberSentMessageState() async {
		let ctx = ModelContext(sharedModelContainer)
		let id: Int64 = 0x00C0_0002

		// Stand in for what sendMessage() persists when the user hits send.
		let sent = MessageEntity()
		ctx.insert(sent)
		sent.messageId = id
		sent.messagePayload = "hello mesh"
		sent.read = true
		sent.receivedACK = true
		try? ctx.save()

		let mp = MeshPackets(modelContainer: sharedModelContainer)
		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(connectedNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		let after = messages(withId: id).first
		#expect(after?.read == true, "echo of our own message must not mark it unread")
		#expect(after?.receivedACK == true, "echo of our own message must not clear its ACK state")
	}

	// MARK: - Store-and-forward replay of self-originated message

	/// A message we sent that was never stored locally (e.g. store-and-forward history replay
	/// from a router, or a second client on the same radio) should be ingested (it's new data),
	/// but must land read and schedule no notification.
	@Test @MainActor func storeAndForwardReplayOfSelfMessage_ingestedReadAndSilent() async {
		let notifications = MainActorBox<[MeshNotification]>([])
		let mp = await makeMeshPackets(scheduledNotifications: notifications)
		let id: Int64 = 0x00C0_0010
		let noAppState: AppState? = nil

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(connectedNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: noAppState
		)

		// Should be ingested (we had no prior row for this id).
		let stored = messages(withId: id)
		#expect(!stored.isEmpty, "a never-stored self-message should be ingested")
		#expect(stored.first?.read == true, "self-originated message must land as read")

		// Give the Task that schedules notifications a chance to run.
		try? await Task.sleep(for: .milliseconds(50))
		#expect(notifications.value.isEmpty, "self-originated message must not schedule a notification")
	}

	// MARK: - Channel branch (the reported scenario)

	/// The user's actual repro: a broadcast to the mesh, echoed back by the radio, notified them
	/// of their own message. That runs the *channel* branch, which only reaches its notification
	/// site when a MyInfoEntity with a matching unmuted channel exists. The setup below is
	/// load-bearing — without it the branch returns early and any "no notification" assertion is
	/// vacuous. Verified by mutation: deleting the isFromSelf guard turns this red.
	@Test @MainActor func selfOriginatedBroadcast_schedulesNoChannelNotification() async {
		let previousValue = UserDefaults.channelMessageNotifications
		UserDefaults.channelMessageNotifications = true
		defer { UserDefaults.channelMessageNotifications = previousValue }

		let notifications = MainActorBox<[MeshNotification]>([])
		let mp = await makeMeshPackets(scheduledNotifications: notifications)
		let id: Int64 = 0x00C0_0060
		let noAppState: AppState? = nil

		let ctx = ModelContext(sharedModelContainer)
		let me = UserEntity()
		ctx.insert(me)
		me.num = connectedNode
		me.longName = "Me"
		me.shortName = "ME"
		me.mute = false

		let channel = ChannelEntity()
		ctx.insert(channel)
		channel.index = 0
		channel.mute = false
		channel.name = "Primary"

		let myInfo = MyInfoEntity()
		ctx.insert(myInfo)
		myInfo.myNodeNum = connectedNode
		myInfo.channels = [channel]
		try? ctx.save()

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(connectedNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: noAppState
		)

		try? await Task.sleep(for: .milliseconds(100))
		#expect(notifications.value.isEmpty, "a broadcast we sent must never notify us about ourselves")
		#expect(messages(withId: id).first?.read == true, "self-originated broadcast must land as read")
	}

	/// Companion guard: the same channel setup, but the broadcast comes from a peer. This must
	/// still notify, or the fix has silenced legitimate channel traffic.
	@Test @MainActor func peerBroadcast_stillSchedulesChannelNotification() async {
		let previousValue = UserDefaults.channelMessageNotifications
		UserDefaults.channelMessageNotifications = true
		defer { UserDefaults.channelMessageNotifications = previousValue }

		let notifications = MainActorBox<[MeshNotification]>([])
		let mp = await makeMeshPackets(scheduledNotifications: notifications)
		let id: Int64 = 0x00C0_0070
		let noAppState: AppState? = nil

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
		try? ctx.save()

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(peerNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: noAppState
		)

		try? await Task.sleep(for: .milliseconds(100))
		#expect(!notifications.value.isEmpty, "a peer's channel broadcast must still notify")
		#expect(messages(withId: id).first?.read != true, "a peer's channel broadcast must land unread")
	}

	// MARK: - Peer duplicate dedupe

	/// A duplicate inbound message from a peer (same packet id delivered twice by the radio)
	/// should produce only one row, and the second delivery must not reset read/receivedACK.
	@Test @MainActor func duplicatePeerMessage_onlyOneRowAndNoStateReset() async {
		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00C0_0020

		// First delivery.
		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(peerNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		// Simulate user reading the message.
		let ctx = ModelContext(sharedModelContainer)
		if let msg = (try? ctx.fetch(FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == id })))?.first {
			msg.read = true
			msg.receivedACK = true
			try? ctx.save()
		}

		// Second delivery (radio echo / duplicate).
		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(peerNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		let rows = messages(withId: id)
		#expect(rows.count == 1, "duplicate packet must not create a second row")
		#expect(rows.first?.read == true, "duplicate must not reset read state")
		#expect(rows.first?.receivedACK == true, "duplicate must not reset ACK state")
	}

	// MARK: - Detection sensor + enableDetectionNotifications interaction

	/// A detection-sensor message with enableDetectionNotifications disabled must stay
	/// read == true regardless of sender. Proves the self-originated guard ORs into the
	/// detection-sensor guard rather than overwriting it.
	@Test @MainActor func detectionSensorWithNotificationsDisabled_staysRead() async {
		// Ensure detection notifications are off.
		let previousValue = UserDefaults.enableDetectionNotifications
		UserDefaults.enableDetectionNotifications = false
		defer { UserDefaults.enableDetectionNotifications = previousValue }

		let mp = MeshPackets(modelContainer: sharedModelContainer)
		let id: Int64 = 0x00C0_0030

		await mp.textMessageAppPacket(
			packet: detectionSensorPacket(id: UInt32(id), from: UInt32(peerNode), to: Constants.maximumNodeNum),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		let stored = messages(withId: id)
		#expect(stored.first?.read == true, "detection-sensor with notifications disabled must be read")
	}

	/// Detection-sensor packets are intentionally omitted from Direct Messages and live in the
	/// sender node's Detection Sensor Log. When their notifications are enabled, opening one must
	/// therefore select that node rather than navigating to an empty DM conversation.
	@Test @MainActor func directDetectionSensor_notificationOpensSenderNode() async throws {
		let previousValue = UserDefaults.enableDetectionNotifications
		UserDefaults.enableDetectionNotifications = true
		defer { UserDefaults.enableDetectionNotifications = previousValue }

		let notificationRecorder = NotificationRecorder()
		let mp = await makeMeshPackets(notificationRecorder: notificationRecorder)
		let id: Int64 = 0x00C0_0031

		let ctx = ModelContext(sharedModelContainer)
		let sender = UserEntity()
		ctx.insert(sender)
		sender.num = peerNode
		sender.longName = "Sensor"
		sender.shortName = "SN"
		sender.mute = false

		let receiver = UserEntity()
		ctx.insert(receiver)
		receiver.num = connectedNode
		receiver.longName = "Me"
		receiver.shortName = "ME"
		try ctx.save()

		await mp.textMessageAppPacket(
			packet: detectionSensorPacket(id: UInt32(id), from: UInt32(peerNode), to: UInt32(connectedNode)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: nil
		)

		await notificationRecorder.waitForNextNotification()
		#expect(notificationRecorder.notifications.first?.path == "meshtastic:///nodes?nodenum=\(peerNode)")
	}

	// MARK: - Self-originated DM

	/// A self-originated DM (not just broadcast) should schedule no notification.
	///
	/// Both UserEntity rows are created deliberately: the DM notification branch is gated on
	/// `fromUser != nil && toUser != nil`, so without them the branch is never entered and the
	/// "no notification" assertion would pass for the wrong reason — vacuously, and dependent on
	/// whichever sibling test happened to seed the shared container first.
	@Test @MainActor func selfOriginatedDM_schedulesNoNotification() async {
		let notifications = MainActorBox<[MeshNotification]>([])
		let mp = await makeMeshPackets(scheduledNotifications: notifications)
		let id: Int64 = 0x00C0_0040
		let noAppState: AppState? = nil

		let ctx = ModelContext(sharedModelContainer)
		let me = UserEntity()
		ctx.insert(me)
		me.num = connectedNode
		me.longName = "Me"
		me.shortName = "ME"
		me.mute = false

		let recipient = UserEntity()
		ctx.insert(recipient)
		recipient.num = peerNode
		recipient.longName = "Peer"
		recipient.shortName = "PR"
		try? ctx.save()

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(connectedNode), to: UInt32(peerNode)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: noAppState
		)

		try? await Task.sleep(for: .milliseconds(50))
		#expect(notifications.value.isEmpty, "self-originated DM must not schedule a notification")

		let stored = messages(withId: id)
		#expect(stored.first?.read == true, "self-originated DM must land as read")
	}

	// MARK: - Normal peer message DOES notify

	/// The most important test: a normal inbound DM from a peer must still create an
	/// unread message and schedule a notification. The self-guard must not silence real traffic.
	/// Uses a DM (not broadcast) so the notification path only needs fromUser + toUser,
	/// avoiding the MyInfoEntity/channel setup the channel branch requires.
	@Test @MainActor func normalPeerDM_isUnreadAndNotifies() async {
		let notificationRecorder = NotificationRecorder()
		let mp = await makeMeshPackets(notificationRecorder: notificationRecorder)
		let id: Int64 = 0x00C0_0050
		let noAppState: AppState? = nil

		// The DM notification path requires both fromUser and toUser to be set.
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
		try? ctx.save()

		await mp.textMessageAppPacket(
			packet: textPacket(id: UInt32(id), from: UInt32(peerNode), to: UInt32(connectedNode)),
			wantRangeTestPackets: true,
			connectedNode: connectedNode,
			appState: noAppState
		)

		let stored = messages(withId: id)
		#expect(stored.first?.read != true, "peer DM must land unread")

		await notificationRecorder.waitForNextNotification()
		#expect(!notificationRecorder.notifications.isEmpty, "peer DM must schedule a notification")
		#expect(notificationRecorder.notifications.first?.path == "meshtastic:///messages?userNum=\(peerNode)&messageId=\(id)")
	}
}

// MARK: - Test helpers

/// Simple @MainActor-isolated box so the notification scheduler closure and the test body
/// can share mutable state without data races.
@MainActor
final class MainActorBox<T> {
	var value: T
	init(_ value: T) { self.value = value }
}

/// Alias to disambiguate from Foundation.Notification.
typealias MeshNotification = Meshtastic.Notification
