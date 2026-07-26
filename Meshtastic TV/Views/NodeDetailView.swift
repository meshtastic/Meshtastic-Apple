//
//  NodeDetailView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Minimal node detail. No distance-to-me / bearing (no device GPS on tvOS).
//  Rows are individually focusable so the Siri Remote can scroll the panel —
//  tvOS only scrolls a container to reveal a *focused* element, and read-only
//  key/value rows are otherwise unreachable below the fold.
//

import SwiftUI

struct NodeDetailView: View {
	let node: MeshNode
	// Font sizes via @ScaledMetric so they track Dynamic Type (mirrors the iOS
	// NodeListItemCompact); the values are the tvOS-tuned defaults.
	@ScaledMetric(relativeTo: .title) private var nameFont: CGFloat = 34
	@ScaledMetric(relativeTo: .caption) private var sectionFont: CGFloat = 20

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
				header

				section("Identity") {
					DetailRow("Name", node.displayName)
					if !node.shortName.isEmpty {
						DetailRow("Short", node.shortName)
					}
					DetailRow("Node", String(format: "!%08x", node.num))
					if let role = node.nodeRole {
						DetailRow("Role", role.name)
					}
					if let hwModel = node.hwModel {
						DetailRow("Hardware", hwModel)
					}
				}

				section("Status") {
					if let battery = node.batteryLevel {
						DetailRow("Battery", "\(battery)%")
					}
					if let snr = node.snr {
						DetailRow("SNR", String(format: "%.1f dB", snr))
					}
					if let lastHeard = node.lastHeard {
						DetailRow("Last heard", lastHeard.formatted(.relative(presentation: .named)))
					}
				}

				if let latitude = node.latitude, let longitude = node.longitude {
					section("Position") {
						DetailRow("Latitude", String(format: "%.5f", latitude))
						DetailRow("Longitude", String(format: "%.5f", longitude))
					}
				}
			}
			.padding(TVTheme.screenPadding)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.navigationTitle(node.displayName)
	}

	private var header: some View {
		HStack(spacing: 20) {
			CircleText(
				text: node.shortName.isEmpty ? "?" : node.shortName,
				color: Color(UIColor(hex: node.num)),
				circleSize: TVTheme.detailAvatarSize
			)
			Text(node.displayName)
				.font(.system(size: nameFont, weight: .bold, design: .rounded))
				.lineLimit(2)
		}
	}

	private func section<Content: View>(
		_ title: String,
		@ViewBuilder content: () -> Content
	) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(title.uppercased())
				.font(.system(size: sectionFont, weight: .semibold))
				.foregroundStyle(.secondary)
				.padding(.horizontal, 24)
				.padding(.bottom, 4)
			content()
		}
	}
}

/// A focusable key/value row. Being focusable is what lets the Siri Remote scroll
/// the panel — tvOS won't reveal content below the fold unless something down
/// there can take focus — and the highlight gives the usual "you are here" feedback.
private struct DetailRow: View {
	let label: String
	let value: String
	@FocusState private var focused: Bool
	@ScaledMetric(relativeTo: .body) private var valueFont: CGFloat = 26

	init(_ label: String, _ value: String) {
		self.label = label
		self.value = value
	}

	var body: some View {
		HStack(spacing: 24) {
			Text(label)
				.foregroundStyle(focused ? .primary : .secondary)
			Spacer(minLength: 24)
			Text(value)
				.fontWeight(.medium)
				.multilineTextAlignment(.trailing)
		}
		.font(.system(size: valueFont))
		.padding(.vertical, 14)
		.padding(.horizontal, 24)
		.background(
			RoundedRectangle(cornerRadius: TVTheme.rowCornerRadius, style: .continuous)
				.fill(focused ? Color.white.opacity(0.14) : Color.clear)
		)
		.focusable()
		.focused($focused)
		.animation(.easeInOut(duration: 0.15), value: focused)
	}
}
