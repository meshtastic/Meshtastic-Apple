//
//  Config+PacketSignaturePolicy.swift
//  Meshtastic
//
//  Display accessors for the firmware packet authenticity policy (design#121, protobufs#983).
//
//  The labels and summaries are byte-identical to the Android/Desktop strings in
//  `PacketAuthenticitySetting.kt` (Meshtastic-Android#6178) so the two clients describe the same
//  device setting the same way.
//
//  Terminology note: these say "authenticated"/"authentication" rather than "signed" because Strict
//  accepts a packet authenticated *either* by a verified XEdDSA signature *or* by successful PKI
//  decryption. "Signed" would wrongly imply authenticated PKI direct messages are rejected.
//

import Foundation
import MeshtasticProtobufs

extension Config.SecurityConfig.PacketSignaturePolicy {
	/// The policies offered by the picker, weakest to strongest. `.UNRECOGNIZED` is never offered —
	/// `pickerOptions(includingCurrent:)` appends it only when a device is already reporting it.
	static let packetAuthenticityOptions: [Self] = [.compatible, .balanced, .strict]

	/// Picker contents, guaranteed to contain `current`.
	///
	/// SwiftUI pickers render incorrectly when the bound selection has no matching tag, so a device
	/// on newer firmware reporting a policy this app version does not know must still be listed.
	static func pickerOptions(includingCurrent current: Self) -> [Self] {
		packetAuthenticityOptions.contains(current)
			? packetAuthenticityOptions
			: packetAuthenticityOptions + [current]
	}

	var packetAuthenticityTitle: String {
		switch self {
		case .compatible:
			return String(localized: "Compatible — Accept unsigned", comment: "Compatible packet authenticity policy option.")
		case .balanced:
			return String(localized: "Balanced — Prefer authenticated", comment: "Balanced packet authenticity policy option.")
		case .strict:
			return String(localized: "Strict — Require authentication", comment: "Strict packet authenticity policy option.")
		case .UNRECOGNIZED:
			return String(localized: "Unknown policy", comment: "Fallback title for an unrecognized packet authenticity policy.")
		}
	}

	var packetAuthenticityDescription: String {
		switch self {
		case .compatible:
			return String(
				localized: "Authenticate packets when possible, but accept unsigned traffic for maximum compatibility.",
				comment: "Description of the Compatible packet authenticity policy."
			)
		case .balanced:
			return String(
				localized: "Recommended. Reject unsigned downgrade attempts from nodes known to sign.",
				comment: "Description of the Balanced packet authenticity policy."
			)
		case .strict:
			return String(
				localized: "Only show and process cryptographically authenticated mesh packets. Older nodes and oversized packets may disappear.",
				comment: "Description of the Strict packet authenticity policy."
			)
		case .UNRECOGNIZED:
			return String(
				localized: "This device reported a packet authenticity policy that this app version does not recognize.",
				comment: "Description shown for an unrecognized packet authenticity policy."
			)
		}
	}
}
