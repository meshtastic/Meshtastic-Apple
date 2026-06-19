// AckCrossContextRefreshTests.swift
// MeshtasticTests
//
// Verifies the central assumption behind the "instant delivery indicator" fix:
// a delivery ACK is written by MeshPackets' OWN ModelContext (it is a @ModelActor),
// but the message lists read through the view's main @Environment ModelContext.
// The fix only works if a fresh fetch on the main context — what loadMessages() does —
// sees the ACK fields the actor committed on its separate context.
//
// This test drives the real routingPacket() path on a second context sharing the
// shared test container, then refetches on the main context and asserts the ACK is
// visible. If this fails, the in-place reload cannot surface the ACK and the fix
// needs an object-dropping fallback (e.g. an .id() rebuild) instead.

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("ACK cross-context refresh")
struct AckCrossContextRefreshTests {

	@MainActor
	private func fetchMessage(_ messageId: Int64, _ context: ModelContext) throws -> MessageEntity? {
		var descriptor = FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == messageId })
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first
	}

	/// Builds a routing-ACK MeshPacket (errorReason == .none) for the given sent-message id,
	/// mirroring how the app constructs MeshPacket/DataMessage protobufs.
	private func makeRoutingAck(requestID: UInt32, to: Int64, from: Int64) throws -> MeshPacket {
		var routing = Routing()
		routing.errorReason = .none

		var data = DataMessage()
		data.portnum = .routingApp
		data.requestID = requestID
		data.payload = try routing.serializedData()

		var packet = MeshPacket()
		packet.to = UInt32(truncatingIfNeeded: to)
		packet.from = UInt32(truncatingIfNeeded: from)   // to != from → counts as a real ACK from the recipient
		packet.decoded = data
		packet.rxSnr = 5.0
		packet.rxTime = UInt32(Date().timeIntervalSince1970)
		packet.relayNode = 0
		return packet
	}

	@Test @MainActor
	func routingAck_isVisibleToMainContextRefetch() async throws {
		let container = sharedModelContainer
		let context = container.mainContext

		let messageId: Int64 = 0x7FAC_0001
		let connectedNodeNum: Int64 = 0x1111_1111
		let remoteNodeNum: Int64 = 0x2222_2222

		// Clean any residue from a prior run on the shared (process-lifetime) container.
		if let stale = try fetchMessage(messageId, context) {
			context.delete(stale)
			try context.save()
		}

		// A sent DM awaiting an ACK: toUser set, not yet acknowledged.
		let recipient = try createUser(num: remoteNodeNum, context: context)
		let message = MessageEntity()
		message.messageId = messageId
		message.toUser = recipient
		message.messagePayload = "ping"
		message.messageTimestamp = Int32(Date().timeIntervalSince1970)
		message.receivedACK = false
		message.realACK = false
		context.insert(message)
		try context.save()

		// Simulate the open conversation holding the fetched object in its @State array.
		let held = try fetchMessage(messageId, context)
		#expect(held?.receivedACK == false)

		// Drive the REAL routing-ACK path on a separate ModelContext, exactly as production
		// does (MeshPackets is a @ModelActor with its own context on the same container).
		let actor = MeshPackets(modelContainer: container)
		let packet = try makeRoutingAck(requestID: UInt32(messageId), to: connectedNodeNum, from: remoteNodeNum)
		await actor.routingPacket(packet: packet, connectedNodeNum: connectedNodeNum, appState: nil)

		// THE CRUX — what loadMessages() does: a fresh fetch on the view's main context.
		let refetched = try fetchMessage(messageId, context)
		#expect(refetched?.receivedACK == true,
			"main-context refetch must see the ACK the actor context committed — the fix depends on this")
		#expect(refetched?.realACK == true)
		#expect(refetched?.ackError == Int32(RoutingError.none.rawValue))

		// Informational: does the originally-held instance also reflect the change (the pure
		// @Bindable live path)? Printed, not asserted — the fix reloads via fetch regardless.
		print("ℹ️ held instance after ACK: receivedACK=\(held?.receivedACK == true), realACK=\(held?.realACK == true)")

		// Cleanup so reruns on the shared container start clean.
		if let toDelete = try fetchMessage(messageId, context) {
			context.delete(toDelete)
			try context.save()
		}
	}
}
