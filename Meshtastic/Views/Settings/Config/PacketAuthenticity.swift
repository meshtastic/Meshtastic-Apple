//
//  PacketAuthenticity.swift
//  Meshtastic
//
//  Packet authenticity policy control for the Security config screen.
//
//  Cross-client contract: design#121, protobufs#983 (Config.SecurityConfig.packet_signature_policy,
//  DeviceMetadata.has_xeddsa) and firmware#10967. The Android/Desktop equivalent is
//  `PacketAuthenticitySetting.kt` (Meshtastic-Android#6178) — the policy labels, summaries and the
//  Strict confirmation copy are deliberately kept identical across clients. The labels themselves
//  live in `Extensions/Protobufs/Config+PacketSignaturePolicy.swift`.
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

// MARK: - Selection state machine

/// Holds the policy shown by the picker and the pending Strict confirmation.
///
/// Selecting Strict does **not** commit; it raises `pendingStrict` so the caller can confirm first.
/// Re-selecting the policy already in force commits without prompting, matching Android.
struct PacketAuthenticitySelectionState: Equatable {
	private(set) var selected: Config.SecurityConfig.PacketSignaturePolicy
	private(set) var pendingStrict = false

	init(selected: Config.SecurityConfig.PacketSignaturePolicy = .compatible) {
		self.selected = selected
	}

	/// Requests `policy`. Commits immediately unless this is a move *into* Strict.
	mutating func propose(_ policy: Config.SecurityConfig.PacketSignaturePolicy) {
		guard policy == .strict, selected != .strict else {
			selected = policy
			pendingStrict = false
			return
		}
		pendingStrict = true
	}

	mutating func confirmStrict() {
		guard pendingStrict else { return }
		selected = .strict
		pendingStrict = false
	}

	mutating func cancelStrict() {
		pendingStrict = false
	}
}

// MARK: - Security config wiring

extension SecurityConfig {
	/// Kept in an extension rather than the main `SecurityConfig` body, which is already at
	/// SwiftLint's `type_body_length` ceiling.
	var packetAuthenticityCapability: PacketAuthenticityCapability {
		PacketAuthenticityCapability(metadata: node?.metadata)
	}

	var packetAuthenticitySection: some View {
		PacketAuthenticitySection(
			capability: packetAuthenticityCapability,
			isConnected: accessoryManager.isConnected,
			selection: $packetAuthenticitySelection
		)
	}

	/// The policy the radio last reported, defaulting to Compatible — the protobuf zero value — so an
	/// unconfigured node and an absent field agree.
	var storedPacketAuthenticitySelection: PacketAuthenticitySelectionState {
		PacketAuthenticitySelectionState(selected: node?.securityConfig?.storedPacketSignaturePolicy ?? .compatible)
	}

	/// Flags the Save button when the chosen policy differs from what the radio reported.
	func packetAuthenticityDidChange(to policy: Config.SecurityConfig.PacketSignaturePolicy) {
		if policy != storedPacketAuthenticitySelection.selected { hasChanges = true }
	}
}

// MARK: - Section

/// "Packet Authenticity" section of the Security config screen.
struct PacketAuthenticitySection: View {
	private var idiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }

	let capability: PacketAuthenticityCapability
	/// Whether the radio is reachable. Combined with `capability` this decides whether the policy
	/// can be changed, and a loss of either dismisses a pending Strict confirmation.
	let isConnected: Bool
	@Binding var selection: PacketAuthenticitySelectionState

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
			: selection.selected.packetAuthenticityDescription
	}

	private var strictConfirmationBinding: Binding<Bool> {
		Binding(
			get: { selection.pendingStrict },
			set: { if !$0 { selection.cancelStrict() } }
		)
	}

	var body: some View {
		Section(header: Text("Packet Authenticity")) {
			VStack(alignment: .leading) {
				Picker(
					"Protection Level",
					selection: Binding(
						get: { selection.selected },
						set: { selection.propose($0) }
					)
				) {
					ForEach(
						Config.SecurityConfig.PacketSignaturePolicy.pickerOptions(includingCurrent: selection.selected),
						id: \.rawValue
					) { policy in
						Text(policy.packetAuthenticityTitle).tag(policy)
					}
				}
				.disabled(!canConfigure)
				Text(summary)
					.foregroundStyle(.secondary)
					.font(idiom == .phone ? .caption : .callout)
			}
			// Attached inside the Section rather than to it: wrapping a Section in modifiers makes
			// Form treat it as ModifiedContent and drop the section header.
			.onChange(of: canConfigure) { _, stillConfigurable in
				// Losing the connection or the capability mid-prompt must dismiss the confirmation
				// without committing Strict — a stale prompt could otherwise write a policy the
				// radio never offered.
				if !stillConfigurable { selection.cancelStrict() }
			}
			.alert(
				String(localized: "Enable Strict authentication?", comment: "Strict packet authenticity confirmation title."),
				isPresented: strictConfirmationBinding
			) {
				Button("Cancel", role: .cancel) {
					selection.cancelStrict()
				}
				Button(
					String(localized: "Enable Strict", comment: "Confirms enabling the Strict packet authenticity policy."),
					role: .destructive
				) {
					// Re-check: the alert can outlive the connection or capability it was raised under.
					if canConfigure {
						selection.confirmStrict()
					} else {
						selection.cancelStrict()
					}
				}
			} message: {
				Text(String(
					localized: "Strict ignores every remote mesh packet that is not cryptographically authenticated. Older firmware, licensed or ham nodes without PKI keys, and oversized packets may disappear. PKI-authenticated direct messages remain available.",
					comment: "Warning shown before enabling the Strict packet authenticity policy."
				))
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
