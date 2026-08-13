//
//  MessageEntityStatusBadgeTests.swift
//  MeshtasticTests
//

import Testing
import Foundation
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - MessageEntity Status Badge Tests
//
// Covers `MessageEntityExtension.swift`'s badge logic: `isEncryptedMessage`,
// `isStoreForwardMessage`, `isDetectionSensorMessage`, `isShowingTranslatedText`,
// `StatusBadge.label`, and `activeStatusBadges`. This is the single source of truth
// MessageText's per-badge overlays and the message rows' combined `accessibilityLabel`
// both read from — before this existed, the combined label silently dropped badges the
// overlays showed (issue #016 T003). None of it had unit coverage.

@Suite("MessageEntity Status Badges", .serialized)
struct MessageEntityStatusBadgeTests {

	@MainActor
	private func makeMessage() throws -> (ModelContext, MessageEntity) {
		let context = TestContainerProvider.shared.mainContext
		let msg = MessageEntity()
		context.insert(msg)
		return (context, msg)
	}

	/// Maps a badge to a plain tag for order/membership comparisons, without adding an
	/// Equatable conformance to `StatusBadge` from outside its declaring file.
	private func tag(_ badge: MessageEntity.StatusBadge) -> String {
		switch badge {
		case .encrypted: return "encrypted"
		case .verified: return "verified"
		case .storeForward: return "storeForward"
		case .detectionSensor: return "detectionSensor"
		case .translated: return "translated"
		}
	}

	// MARK: - isEncryptedMessage

	@Test @MainActor func isEncryptedMessage_pkiAndRealACK_trueRegardlessOfCurrentUser() throws {
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = true
		msg.realACK = true
		#expect(msg.isEncryptedMessage(isCurrentUser: true) == true)
		#expect(msg.isEncryptedMessage(isCurrentUser: false) == true)
	}

	@Test @MainActor func isEncryptedMessage_pkiAndNotCurrentUser_trueEvenWithoutRealACK() throws {
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = true
		msg.realACK = false
		#expect(msg.isEncryptedMessage(isCurrentUser: false) == true)
	}

	@Test @MainActor func isEncryptedMessage_notPki_false() throws {
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = false
		msg.realACK = true
		#expect(msg.isEncryptedMessage(isCurrentUser: false) == false)
		#expect(msg.isEncryptedMessage(isCurrentUser: true) == false)
	}

	@Test @MainActor func isEncryptedMessage_pkiCurrentUserNoRealACK_false() throws {
		// The one combination that should NOT count as encrypted-badge-worthy: a PKI DM the
		// current user sent that hasn't been confirmed delivered yet.
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = true
		msg.realACK = false
		#expect(msg.isEncryptedMessage(isCurrentUser: true) == false)
	}

	// MARK: - isStoreForwardMessage

	@Test @MainActor func isStoreForwardMessage_matchingPortNum_true() throws {
		let (_, msg) = try makeMessage()
		msg.portNum = Int32(PortNum.storeForwardApp.rawValue)
		#expect(msg.isStoreForwardMessage == true)
	}

	@Test @MainActor func isStoreForwardMessage_otherPortNum_false() throws {
		let (_, msg) = try makeMessage()
		msg.portNum = Int32(PortNum.textMessageApp.rawValue)
		#expect(msg.isStoreForwardMessage == false)
	}

	// MARK: - isDetectionSensorMessage

	@Test @MainActor func isDetectionSensorMessage_channelDestinationMatchingPortNum_true() throws {
		let (_, msg) = try makeMessage()
		msg.portNum = Int32(PortNum.detectionSensorApp.rawValue)
		#expect(msg.isDetectionSensorMessage(destination: .channel(ChannelEntity())) == true)
	}

	@Test @MainActor func isDetectionSensorMessage_userDestination_falseEvenWithMatchingPortNum() throws {
		let (_, msg) = try makeMessage()
		msg.portNum = Int32(PortNum.detectionSensorApp.rawValue)
		#expect(msg.isDetectionSensorMessage(destination: .user(UserEntity())) == false)
	}

	@Test @MainActor func isDetectionSensorMessage_channelDestinationOtherPortNum_false() throws {
		let (_, msg) = try makeMessage()
		msg.portNum = Int32(PortNum.textMessageApp.rawValue)
		#expect(msg.isDetectionSensorMessage(destination: .channel(ChannelEntity())) == false)
	}

	// MARK: - isShowingTranslatedText

	@Test @MainActor func isShowingTranslatedText_shownAndHasPayload_true() throws {
		let (_, msg) = try makeMessage()
		msg.showTranslatedMessage = true
		msg.messagePayloadTranslated = "Hola"
		#expect(msg.isShowingTranslatedText == true)
	}

	@Test @MainActor func isShowingTranslatedText_notShown_falseEvenWithPayload() throws {
		let (_, msg) = try makeMessage()
		msg.showTranslatedMessage = false
		msg.messagePayloadTranslated = "Hola"
		#expect(msg.isShowingTranslatedText == false)
	}

	@Test @MainActor func isShowingTranslatedText_shownButNoPayload_false() throws {
		let (_, msg) = try makeMessage()
		msg.showTranslatedMessage = true
		msg.messagePayloadTranslated = nil
		#expect(msg.isShowingTranslatedText == false)
	}

	// MARK: - StatusBadge.label

	@Test func statusBadgeLabels_nonEmptyAndDistinctAcrossAllCases() {
		let cases: [MessageEntity.StatusBadge] = [.encrypted, .verified, .storeForward, .detectionSensor, .translated]
		let labels = cases.map { $0.label }
		#expect(labels.allSatisfy { !$0.isEmpty })
		#expect(Set(labels).count == labels.count)
	}

	// MARK: - activeStatusBadges

	@Test @MainActor func activeStatusBadges_noFlags_empty() throws {
		let (_, msg) = try makeMessage()
		let badges = msg.activeStatusBadges(destination: .channel(ChannelEntity()), isCurrentUser: false)
		#expect(badges.isEmpty)
	}

	@Test @MainActor func activeStatusBadges_onlyStoreForward_returnsJustThatBadge() throws {
		let (_, msg) = try makeMessage()
		msg.portNum = Int32(PortNum.storeForwardApp.rawValue)
		let badges = msg.activeStatusBadges(destination: .channel(ChannelEntity()), isCurrentUser: false)
		#expect(badges.map(tag) == ["storeForward"])
	}

	@Test @MainActor func activeStatusBadges_encryptedSignedStoreForwardTranslated_allFourInOrder() throws {
		// The regression case this PR fixed, for the store-forward variant: encrypted, verified,
		// storeForward, and translated all active at once must all surface in the combined label,
		// in the exact order activeStatusBadges builds them.
		//
		// storeForward and detectionSensor both key off the single `portNum` field, so a real
		// message can never satisfy both at once (PortNum.storeForwardApp and
		// .detectionSensorApp are distinct raw values) — this case and the one below between them
		// cover all five badge kinds.
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = true
		msg.realACK = true
		msg.xeddsaSigned = true
		msg.portNum = Int32(PortNum.storeForwardApp.rawValue)
		msg.showTranslatedMessage = true
		msg.messagePayloadTranslated = "Hola"

		let badges = msg.activeStatusBadges(destination: .channel(ChannelEntity()), isCurrentUser: false)
		#expect(badges.map(tag) == ["encrypted", "verified", "storeForward", "translated"])
	}

	@Test @MainActor func activeStatusBadges_encryptedSignedDetectionSensorTranslated_allFourInOrder() throws {
		// The other half of the regression case: encrypted, verified, detectionSensor, and
		// translated all active at once, with a channel destination required for the sensor
		// badge to show at all.
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = true
		msg.realACK = true
		msg.xeddsaSigned = true
		msg.portNum = Int32(PortNum.detectionSensorApp.rawValue)
		msg.showTranslatedMessage = true
		msg.messagePayloadTranslated = "Hola"

		let badges = msg.activeStatusBadges(destination: .channel(ChannelEntity()), isCurrentUser: false)
		#expect(badges.map(tag) == ["encrypted", "verified", "detectionSensor", "translated"])
	}

	@Test @MainActor func activeStatusBadges_detectionSensorPortNumButUserDestination_sensorBadgeDoesNotLeakIn() throws {
		let (_, msg) = try makeMessage()
		msg.pkiEncrypted = true
		msg.realACK = true
		msg.portNum = Int32(PortNum.detectionSensorApp.rawValue)
		let badges = msg.activeStatusBadges(destination: .user(UserEntity()), isCurrentUser: false)
		#expect(badges.map(tag) == ["encrypted"])
	}
}
