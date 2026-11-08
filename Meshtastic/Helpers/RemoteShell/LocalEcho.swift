//
//  LocalEcho.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/8/26.
//

import Foundation

/// Predicts the node's echo of typed characters so typing feels immediate over a slow link.
///
/// Nothing is drawn on a line until the node has echoed one character typed on it, so a prompt
/// that doesn't echo (a password prompt) never shows what was typed. After that, each typed
/// character is drawn at once, marked unconfirmed, and dropped when the node's echo arrives. An
/// echo that doesn't match drops every prediction until the line confirms again. A prediction
/// the node never echoes turns prediction off until the next Enter.
struct LocalEcho {
	struct Prediction: Equatable {
		let character: Character
		/// When it went out; nil while it is still waiting to be sent.
		var sentAt: Date?
	}

	private(set) var predictions: [Prediction] = []
	/// Whether the node has echoed a character typed on the current line.
	private(set) var confirmedOnLine = false
	/// Set when a prediction timed out; cleared by Enter.
	private(set) var disabledUntilEnter = false

	private var escape = EscapeSkipper()

	/// A line that reads as a password, passphrase or PIN prompt.
	static func isSecretPrompt(_ line: String) -> Bool {
		line.range(of: #"(password|passphrase|passcode|\bpin\b)[^:]*:\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
	}

	mutating func typed(_ character: Character) {
		predictions.append(Prediction(character: character, sentAt: nil))
	}

	/// Unsent predictions removed again before they went out.
	mutating func removeUnsent() {
		if let last = predictions.last, last.sentAt == nil {
			predictions.removeLast()
		}
	}

	mutating func markSent(now: Date) {
		for index in predictions.indices where predictions[index].sentAt == nil {
			predictions[index].sentAt = now
		}
	}

	/// Backspace sent to the node.
	mutating func backspace() {
		if !predictions.isEmpty {
			predictions.removeLast()
		}
	}

	mutating func enter() {
		predictions = []
		confirmedOnLine = false
		disabledUntilEnter = false
	}

	/// Any other control key or escape sequence: its effect can't be predicted.
	mutating func control() {
		predictions = []
	}

	mutating func received(_ data: Data) {
		for byte in data {
			guard let printable = escape.printable(byte) else { continue }
			guard let first = predictions.first, first.sentAt != nil else { continue }
			if first.character == printable {
				predictions.removeFirst()
				confirmedOnLine = true
			} else {
				predictions = []
				confirmedOnLine = false
			}
		}
	}

	mutating func expire(now: Date, roundTrip: TimeInterval?) {
		let limit = min(max(3 * (roundTrip ?? 1.5), 4), 20)
		guard let sentAt = predictions.first?.sentAt, now.timeIntervalSince(sentAt) > limit else { return }
		predictions = []
		disabledUntilEnter = true
	}

	/// The predictions to draw after the cursor, split into sent and still unsent.
	func visible(atSecretPrompt: Bool) -> (sent: String, unsent: String) {
		guard confirmedOnLine, !disabledUntilEnter, !atSecretPrompt else { return ("", "") }
		let sent = String(predictions.filter { $0.sentAt != nil }.map(\.character))
		let unsent = String(predictions.filter { $0.sentAt == nil }.map(\.character))
		return (sent, unsent)
	}
}

/// Picks printable ASCII out of terminal output, skipping control characters and escape
/// sequences, so echoes can be compared with what was typed.
struct EscapeSkipper {
	private enum State { case ground, escape, csi, osc }
	private var state = State.ground

	mutating func printable(_ byte: UInt8) -> Character? {
		switch state {
		case .ground:
			if byte == 0x1B {
				state = .escape
				return nil
			}
			return (0x20...0x7E).contains(byte) ? Character(Unicode.Scalar(byte)) : nil
		case .escape:
			state = byte == 0x5B ? .csi : byte == 0x5D ? .osc : .ground
		case .csi:
			if (0x40...0x7E).contains(byte) { state = .ground }
		case .osc:
			if byte == 0x07 || byte == 0x1B { state = .ground }
		}
		return nil
	}
}
