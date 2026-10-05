//
//  IncomingMessageReloadTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/3/26.
//
import Foundation
import MeshtasticProtobufs
import Testing
@testable import Meshtastic

@Suite("Incoming message reload", .serialized)
struct IncomingMessageReloadTests {

	private final class PostCounter: @unchecked Sendable {
		var count = 0
	}

	/// An open conversation reloads on .meshMessagesDidChange. A new text message has to post it
	/// as soon as it is saved, not on whatever save happens next.
	@Test @MainActor func incomingTextMessage_postsReloadRightAway() async throws {
		let counter = PostCounter()
		let observer = NotificationCenter.default.addObserver(
			forName: .meshMessagesDidChange, object: nil, queue: .main
		) { _ in counter.count += 1 }
		defer { NotificationCenter.default.removeObserver(observer) }

		var data = DataMessage()
		data.portnum = .textMessageApp
		data.payload = Data("hello".utf8)
		var packet = MeshPacket()
		packet.id = 0x00C0_0301
		packet.from = 0xC01
		packet.to = Constants.maximumNodeNum
		packet.decoded = data

		let mp = MeshPackets(modelContainer: sharedModelContainer)
		await mp.textMessageAppPacket(packet: packet, wantRangeTestPackets: true, connectedNode: 0x01, appState: nil)

		for _ in 0..<20 where counter.count == 0 {
			try await Task.sleep(for: .milliseconds(50))
		}
		#expect(counter.count > 0)
	}
}
