//
//  SendMessageIntentDestinationTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/26/26.
//

import Foundation
import Intents
import Testing

@testable import Meshtastic

/// Replying to a channel thread in CarPlay asked who the reply was for. Siri hands
/// a channel reply back without a speakable group name, keeping the channel only in
/// the conversation identifier. `handle(intent:)` read that; the resolvers did not,
/// so they asked for a recipient the handler would then ignore.
@Suite("Send message intent destination")
struct SendMessageIntentDestinationTests {

	private typealias Handler = SendMessageIntentHandler

	@Test func aChannelReplyWithoutAGroupNameIsStillAddressedToTheChannel() {
		#expect(Handler.destination(
			speakableGroupName: nil,
			conversationIdentifier: "channel-2",
			hasRecipients: false) == .channel(2))
	}

	@Test func theRecipientsSiriAttachesToAChannelReplyDoNotChangeWhereItGoes() {
		// A reply carries the thread's sender. Routing by it is how a channel reply
		// used to go out as a DM to whoever spoke last.
		#expect(Handler.destination(
			speakableGroupName: nil,
			conversationIdentifier: "channel-0",
			hasRecipients: true) == .channel(0))
	}

	@Test func aNamedChannelWins() {
		#expect(Handler.destination(
			speakableGroupName: "Primary Channel",
			conversationIdentifier: "channel-3",
			hasRecipients: true) == .namedChannel("Primary Channel"))
	}

	@Test func aDirectMessageConversationIsNotAChannel() {
		#expect(Handler.destination(
			speakableGroupName: nil,
			conversationIdentifier: "dm-123456",
			hasRecipients: true) == .recipients)
	}

	@Test func nothingToAddressIsUnknown() {
		#expect(Handler.destination(
			speakableGroupName: nil,
			conversationIdentifier: nil,
			hasRecipients: false) == .unknown)
		#expect(Handler.destination(
			speakableGroupName: nil,
			conversationIdentifier: "dm-123456",
			hasRecipients: false) == .unknown)
	}

	@Test func anOutOfRangeChannelIsNotTreatedAsAChannel() {
		// `channelIndex(fromHandleOrName:)` rejects anything outside 0...7, so a
		// malformed identifier must not resolve to a channel here either.
		#expect(Handler.destination(
			speakableGroupName: nil,
			conversationIdentifier: "channel-2147483648",
			hasRecipients: true) == .recipients)
	}

	@Test func aChannelReplyIsNotAskedWhoItIsFor() async {
		let intent = INSendMessageIntent(
			recipients: nil,
			outgoingMessageType: .outgoingMessageText,
			content: "on my way",
			speakableGroupName: nil,
			conversationIdentifier: "channel-1",
			serviceName: "Meshtastic",
			sender: nil,
			attachments: nil
		)

		let resolved = await Handler().resolveRecipients(for: intent)

		#expect(resolved.isEmpty, "a channel needs no recipient; one result here is the prompt")
	}

	@Test func aMessageWithNoDestinationStillAsksWhoItIsFor() async {
		let intent = INSendMessageIntent(
			recipients: nil,
			outgoingMessageType: .outgoingMessageText,
			content: "hello",
			speakableGroupName: nil,
			conversationIdentifier: nil,
			serviceName: "Meshtastic",
			sender: nil,
			attachments: nil
		)

		let resolved = await Handler().resolveRecipients(for: intent)

		#expect(resolved.count == 1, "with nothing to address, asking is correct")
	}
}
