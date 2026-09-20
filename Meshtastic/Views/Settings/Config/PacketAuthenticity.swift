//
//  PacketAuthenticity.swift
//  Meshtastic
//
//  Packet authenticity policy control for the Security config screen.
//
//  Cross-client contract: design#121, protobufs#983 (Config.SecurityConfig.packet_signature_policy,
//  DeviceMetadata.has_xeddsa) and firmware#10967. The Android/Desktop equivalent is
//  `PacketAuthenticitySetting.kt` (Meshtastic-Android#6178) — the policy labels and summaries are
//  deliberately kept identical across clients. The labels themselves live in
//  `Extensions/Protobufs/Config+PacketSignaturePolicy.swift`.
//

import SwiftUI
import MeshtasticProtobufs

// MARK: - Capability

/// Tri-state XEdDSA capability reported by the connected radio's `DeviceMetadata`.
///
/// Mirrors Android's `supported: Boolean?`: absent metadata is `unknown` rather than `unsupported`,
/// so a radio that has simply not answered yet is never described as lacking the feature.
enum PacketAuthenticityCapability: Equatable {
	case supported
	case unsupported
	case unknown

	init(metadata: DeviceMetadataEntity?) {
		guard let metadata else {
			self = .unknown
			return
		}
		self = metadata.hasXeddsa ? .supported : .unsupported
	}

	/// Only a radio that positively reports XEdDSA support may have its policy changed.
	var allowsChanges: Bool { self == .supported }
}

// MARK: - Section

/// "Packet Authenticity" section of the Security config screen.
struct PacketAuthenticitySection: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	let capability: PacketAuthenticityCapability
	/// Whether the radio is reachable. Combined with `capability` this decides whether the policy
	/// can be changed.
	let isConnected: Bool
	@Binding var policy: Config.SecurityConfig.PacketSignaturePolicy

	private var canConfigure: Bool { isConnected && capability.allowsChanges }

	/// Explains the disabled control. Unsupported firmware replaces the policy summary outright, as
	/// on Android; an unreported capability keeps the summary and adds a note, because the radio may
	/// still support the feature.
	private var summary: String {
		capability == .unsupported
			? String(
				localized: "This connected device does not support packet signature verification.",
				comment: "Summary shown when the connected radio lacks XEdDSA packet signature verification."
			)
			: policy.packetAuthenticityDescription
	}

	var body: some View {
		Section(header: Text("Packet Authenticity")) {
			VStack(alignment: .leading) {
				Picker("Protection Level", selection: $policy) {
					ForEach(
						Config.SecurityConfig.PacketSignaturePolicy.pickerOptions(includingCurrent: policy),
						id: \.rawValue
					) { option in
						Text(option.packetAuthenticityTitle).tag(option)
					}
				}
				.disabled(!canConfigure)
				Text(summary)
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
			}
			if capability == .unknown {
				Label(
					String(
						localized: "This device has not reported whether it supports packet signature verification. Update its firmware to configure this setting.",
						comment: "Note shown when a radio has not reported its packet signature verification capability."
					),
					systemImage: "exclamationmark.triangle.fill"
				)
				.font(.caption)
				.foregroundStyle(.orange)
			}
		}
	}
}
