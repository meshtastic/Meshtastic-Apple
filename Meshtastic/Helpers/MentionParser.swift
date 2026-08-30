// MentionParser.swift
// Meshtastic

import Foundation
import SwiftData

/// Parses and resolves `@!<hex-id>` mention tokens embedded in message text.
///
/// ## Wire format
/// A mention is stored as `@!<hex-id>` where `<hex-id>` is the node's 32-bit numeric ID
/// encoded as exactly 8 lowercase hex digits (e.g. `@!deadbeef`). This matches the
/// cross-platform contract shared with Android and Web clients.
///
/// ## Example
/// ```
/// // Raw payload stored on the wire
/// "Hello @!deadbeef, how are you?"
///
/// // After resolveMentions(in:context:):
/// "Hello [@Alice](meshtastic:///nodes?nodenum=3735928559), how are you?"
/// ```
enum MentionParser {

	/// Pattern matching a mention token: `@!` followed by exactly 8 lowercase hex digits.
	/// The trailing lookahead rejects longer runs (`@!deadbeef00` is not a mention of
	/// `@!deadbeef` — the wire format is exactly 8 digits).
	private static let mentionRegex = try! NSRegularExpression(pattern: "@!([0-9a-f]{8})(?![0-9a-f])")

	/// Returns all mention ranges found in `text`, paired with the 8-char hex node ID.
	static func mentionRanges(in text: String) -> [(range: Range<String.Index>, hexId: String)] {
		let nsRange = NSRange(text.startIndex..., in: text)
		let matches = mentionRegex.matches(in: text, range: nsRange)
		return matches.compactMap { match -> (Range<String.Index>, String)? in
			guard
				let fullRange = Range(match.range, in: text),
				let captureRange = Range(match.range(at: 1), in: text)
			else { return nil }
			return (fullRange, String(text[captureRange]))
		}
	}

	/// Converts an 8-char lowercase hex string to the corresponding Int64 node number, or `nil`
	/// if the string is not valid hex.
	static func nodeNum(from hexId: String) -> Int64? {
		guard let value = UInt32(hexId, radix: 16) else { return nil }
		return Int64(value)
	}

	/// Detects the in-progress mention being composed at the end of `text`.
	///
	/// Returns the partial query string (the characters typed after `@`) if the caret
	/// appears to be inside an unresolved mention trigger (i.e., `@` not followed by `!`
	/// and not interrupted by whitespace). Returns `nil` when no active trigger is found.
	///
	/// Examples:
	/// - `"Hello @"` → `""`
	/// - `"Hello @Al"` → `"Al"`
	/// - `"Hello @!deadbeef"` → `nil` (already resolved)
	/// - `"Hello @Alice world"` → `nil` (space ended the trigger)
	static func activeMentionQuery(in text: String) -> String? {
		guard let atRange = text.range(of: "@", options: .backwards) else { return nil }
		let afterAt = text[atRange.upperBound...]
		// Already resolved — starts with "!"
		guard !afterAt.hasPrefix("!") else { return nil }
		// Mention ended by whitespace
		guard !afterAt.contains(where: { $0.isWhitespace }) else { return nil }
		return String(afterAt)
	}

	/// Replaces the active in-progress mention trigger at the end of `text` with the
	/// resolved token `@!<hexId>` (e.g. `@!deadbeef`) for the chosen node.
	///
	/// If no active trigger is found (see `activeMentionQuery`) the text is returned unchanged.
	static func insertMentionToken(into text: String, user: UserEntity) -> String {
		guard let atRange = text.range(of: "@", options: .backwards) else { return text }
		let afterAt = text[atRange.upperBound...]
		guard !afterAt.hasPrefix("!"), !afterAt.contains(where: { $0.isWhitespace }) else {
			return text
		}
		let token = "@" + user.num.toHex()   // e.g. "@!deadbeef"
		return String(text[..<atRange.lowerBound]) + token
	}

	/// Returns `true` when `text` contains a mention of the node identified by `nodeNum`.
	///
	/// Used by the notification layer to detect self-mentions in channel broadcasts.
	/// Goes through the bounded token parse rather than a substring search so a longer
	/// hex run (`@!deadbeef00`) can't register as a mention of `@!deadbeef`.
	static func containsMention(of nodeNum: Int64, in text: String) -> Bool {
		mentionRanges(in: text).contains { self.nodeNum(from: $0.hexId) == nodeNum }
	}

	/// Replaces all `@!<hex>` mention tokens in `text` with markdown links of the form
	/// `[@DisplayName](meshtastic:///nodes?nodenum=<num>)`.
	///
	/// The display name is resolved live from the SwiftData `context` so name changes are
	/// reflected immediately without re-sending the message. Tokens for unknown nodes fall
	/// back to `@!<hexId>` unchanged.
	///
	/// Processes tokens in reverse order to preserve string indices after replacement.
	static func resolveMentions(in text: String, context: ModelContext) -> String {
		let ranges = mentionRanges(in: text)
		guard !ranges.isEmpty else { return text }

		var result = text
		for (range, hexId) in ranges.reversed() {
			guard let num = nodeNum(from: hexId) else { continue }
			let displayName = escapeMarkdown(resolveDisplayName(nodeNum: num, context: context))
			let link = "[@\(displayName)](meshtastic:///nodes?nodenum=\(num))"
			result.replaceSubrange(range, with: link)
		}
		return result
	}

	// MARK: - Private helpers

	/// Display names come from mesh data and can contain markdown control characters
	/// (`]`, `(`, `*`, `\`, …) that would break or restructure the generated link when the
	/// message is parsed as markdown. Backslash-escape every ASCII punctuation character —
	/// all of them are valid CommonMark escapes and render as the literal character.
	private static func escapeMarkdown(_ name: String) -> String {
		var escaped = ""
		escaped.reserveCapacity(name.count)
		for character in name {
			if let ascii = character.asciiValue,
			   (33...47).contains(ascii) || (58...64).contains(ascii)
				|| (91...96).contains(ascii) || (123...126).contains(ascii) {
				escaped.append("\\")
			}
			escaped.append(character)
		}
		return escaped
	}

	private static func resolveDisplayName(nodeNum: Int64, context: ModelContext) -> String {
		var descriptor = FetchDescriptor<UserEntity>(
			predicate: #Predicate<UserEntity> { $0.num == nodeNum }
		)
		descriptor.fetchLimit = 1
		if let user = (try? context.fetch(descriptor))?.first {
			if let name = user.longName, !name.isEmpty { return name }
			if let name = user.shortName, !name.isEmpty { return name }
		}
		return "!\(String(format: "%08x", UInt32(bitPattern: Int32(truncatingIfNeeded: nodeNum))))"
	}
}
