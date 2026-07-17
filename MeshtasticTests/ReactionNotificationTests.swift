//
//  ReactionNotificationTests.swift
//  MeshtasticTests
//
//  Coverage for issue #2039: receiving a tapback/reaction should surface a local
//  notification (it previously produced none), *except* for a "phantom" tapback whose
//  replyID doesn't match a locally-known message — that is stored but must not notify,
//  matching Android's guard (MeshDataHandlerImpl.rememberReaction).
//
//  These exercise `MeshPackets.reactionNotificationBody(replyID:emoji:senderName:context:)`
//  directly against an in-memory SwiftData context, so both the phantom guard and the
//  iMessage-style body formatting are locked in without spinning up the whole packet path.
//

import Testing
import Foundation
import SwiftData
@testable import Meshtastic

@Suite("Reaction notifications (#2039)")
@MainActor
struct ReactionNotificationTests {

	private var context: ModelContext { TestContainerProvider.shared.mainContext }

	/// Insert an original (reacted-to) message with a unique id and the given payload.
	@discardableResult
	private func insertOriginal(id: Int64, payload: String?) -> MessageEntity {
		let msg = MessageEntity()
		context.insert(msg)
		msg.messageId = id
		msg.messagePayload = payload
		msg.isEmoji = false
		try? context.save()
		return msg
	}

	private func body(replyID: Int64, emoji: String?, sender: String = "Bob") -> String? {
		MeshPackets.reactionNotificationBody(
			replyID: replyID,
			emoji: emoji,
			senderName: sender,
			context: context
		)
	}

	// MARK: - Phantom-tapback guard (the core of the fix)

	@Test func phantomTapback_unknownReplyID_returnsNil() {
		// No message with id 990001 exists in the store.
		#expect(body(replyID: 990_001, emoji: "👍") == nil)
	}

	@Test func replyIDZero_returnsNil() {
		// replyID == 0 means "not a reply/reaction to anything" — never notify.
		#expect(body(replyID: 0, emoji: "👍") == nil)
	}

	@Test func negativeReplyID_returnsNil() {
		#expect(body(replyID: -5, emoji: "👍") == nil)
	}

	// MARK: - Found original -> formatted iMessage-style body

	// The body is formatted through `String.localizedStringWithFormat` with a template from
	// `Localizable.xcstrings`, so the surrounding "reacted"/"to" words are locale-dependent.
	// Assert only on the locale-stable interpolated pieces (sender, emoji, quoted original text)
	// so these don't break when the test host runs under a non-English locale.

	@Test func knownReplyID_formatsBody() {
		insertOriginal(id: 990_010, payload: "See you soon")
		let result = body(replyID: 990_010, emoji: "👍", sender: "Alice")
		#expect(result != nil)
		#expect(result?.contains("Alice") == true)
		#expect(result?.contains("👍") == true)
		#expect(result?.contains("See you soon") == true)
	}

	@Test func knownReplyID_emptyEmoji_fallsBackToHeart() {
		insertOriginal(id: 990_020, payload: "Hello there")
		let result = body(replyID: 990_020, emoji: "")
		#expect(result != nil)
		#expect(result?.contains("❤️") == true)
		#expect(result?.contains("Hello there") == true)
	}

	@Test func knownReplyID_nilEmoji_fallsBackToHeart() {
		insertOriginal(id: 990_030, payload: "Hello there")
		let result = body(replyID: 990_030, emoji: nil)
		#expect(result != nil)
		#expect(result?.contains("❤️") == true)
		#expect(result?.contains("Hello there") == true)
	}

	@Test func knownReplyID_nilOriginalPayload_stillNotifies() {
		// The original message exists (so it's NOT a phantom tapback) but has no text.
		// We still surface a notification; the quoted text is simply empty.
		insertOriginal(id: 990_040, payload: nil)
		let result = body(replyID: 990_040, emoji: "🎉", sender: "Carol")
		#expect(result != nil)
		#expect(result?.contains("Carol") == true)
		#expect(result?.contains("🎉") == true)
	}
}
