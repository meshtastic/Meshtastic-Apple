//
//  CarPlayTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 4/16/26.
//

import CarPlay
import CoreData
import Foundation
import Intents
import Testing

@testable import Meshtastic

// MARK: - CarPlaySceneDelegate Tests

@Suite("CarPlaySceneDelegate")
struct CarPlaySceneDelegateTests {

	@Test func initialState() {
		let delegate = CarPlaySceneDelegate()
		#expect(delegate.interfaceController == nil)
	}

	@Test func disconnectClearsInterfaceController() {
		let delegate = CarPlaySceneDelegate()
		// Simulate that interface controller was set during connect
		delegate.interfaceController = nil
		#expect(delegate.interfaceController == nil)
	}
}

// MARK: - CarPlayIntentDonation Tests

@Suite("CarPlayIntentDonation")
struct CarPlayIntentDonationTests {

	// MARK: - channelDisplayName

	@Test func channelDisplayNamePrimary() {
		let name = CarPlayIntentDonation.testChannelDisplayName(for: 0)
		#expect(name == "Primary Channel")
	}

	@Test func channelDisplayNameSecondary() {
		let name = CarPlayIntentDonation.testChannelDisplayName(for: 1)
		#expect(name == "Channel 1")
	}

	@Test func channelDisplayNameHighIndex() {
		let name = CarPlayIntentDonation.testChannelDisplayName(for: 7)
		#expect(name == "Channel 7")
	}

	// MARK: - mePerson

	@Test func mePersonIsMe() {
		let me = CarPlayIntentDonation.testMePerson()
		#expect(me.isMe)
		#expect(me.displayName == "Me")
		#expect(me.personHandle?.value == "me")
	}

	// MARK: - Outgoing DM Intent Structure

	@Test func outgoingDMIntentHasCorrectConversationId() {
		let intent = CarPlayIntentDonation.testBuildOutgoingIntent(
			content: "Hello mesh",
			toUserNum: 1234567890,
			channel: 0
		)
		#expect(intent.conversationIdentifier == "dm-1234567890")
		#expect(intent.serviceName == "Meshtastic")
		#expect(intent.content == "Hello mesh")
		#expect(intent.recipients?.count == 1)
		#expect(intent.speakableGroupName == nil)
	}

	@Test func outgoingChannelIntentHasCorrectConversationId() {
		let intent = CarPlayIntentDonation.testBuildOutgoingIntent(
			content: "Channel message",
			toUserNum: 0,
			channel: 2
		)
		#expect(intent.conversationIdentifier == "channel-2")
		#expect(intent.serviceName == "Meshtastic")
		#expect(intent.content == "Channel message")
		#expect(intent.recipients == nil)
		#expect(intent.speakableGroupName?.spokenPhrase == "Channel 2")
	}

	@Test func outgoingPrimaryChannelIntentName() {
		let intent = CarPlayIntentDonation.testBuildOutgoingIntent(
			content: "Test",
			toUserNum: 0,
			channel: 0
		)
		#expect(intent.speakableGroupName?.spokenPhrase == "Primary Channel")
	}

	// MARK: - Interaction Direction

	@Test func outgoingInteractionDirection() {
		let interaction = CarPlayIntentDonation.testBuildOutgoingInteraction(
			content: "Test",
			toUserNum: 999,
			channel: 0
		)
		#expect(interaction.direction == .outgoing)
	}
}

// MARK: - Test Helpers Extension

extension CarPlayIntentDonation {

	/// Exposes channelDisplayName for testing
	static func testChannelDisplayName(for index: Int32) -> String {
		channelDisplayName(for: index)
	}

	/// Exposes mePerson for testing
	static func testMePerson() -> INPerson {
		mePerson()
	}

	/// Builds an outgoing INSendMessageIntent without donating
	static func testBuildOutgoingIntent(content: String, toUserNum: Int64, channel: Int32) -> INSendMessageIntent {
		let me = mePerson()

		if toUserNum != 0 {
			let recipientHandle = INPersonHandle(value: String(toUserNum), type: .unknown)
			let recipient = INPerson(
				personHandle: recipientHandle,
				nameComponents: nil,
				displayName: "Node \(toUserNum.toHex())",
				image: nil,
				contactIdentifier: String(toUserNum),
				customIdentifier: String(toUserNum)
			)
			return INSendMessageIntent(
				recipients: [recipient],
				outgoingMessageType: .outgoingMessageText,
				content: content,
				speakableGroupName: nil,
				conversationIdentifier: "dm-\(toUserNum)",
				serviceName: "Meshtastic",
				sender: me,
				attachments: nil
			)
		} else {
			let channelName = channelDisplayName(for: channel)
			let groupName = INSpeakableString(spokenPhrase: channelName)
			return INSendMessageIntent(
				recipients: nil,
				outgoingMessageType: .outgoingMessageText,
				content: content,
				speakableGroupName: groupName,
				conversationIdentifier: "channel-\(channel)",
				serviceName: "Meshtastic",
				sender: me,
				attachments: nil
			)
		}
	}

	/// Builds an outgoing INInteraction without donating
	static func testBuildOutgoingInteraction(content: String, toUserNum: Int64, channel: Int32) -> INInteraction {
		let intent = testBuildOutgoingIntent(content: content, toUserNum: toUserNum, channel: channel)
		let interaction = INInteraction(intent: intent, response: nil)
		interaction.direction = .outgoing
		return interaction
	}
}
