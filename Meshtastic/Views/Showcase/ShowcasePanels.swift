//
//  ShowcasePanels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import SwiftUI

/// The card for a tapped radio. Reads only the snapshot, never SwiftData.
struct ShowcaseNodeCard: View {
	let node: ShowcaseNodeSnapshot
	let isOnline: Bool
	let preset: ModemPresets
	let onOpen: () -> Void
	let onClose: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				CircleText(text: node.shortName, color: Color(ShowcaseSceneController.nodeColor(node.id)), circleSize: 36)
				VStack(alignment: .leading, spacing: 2) {
					Text(node.longName)
						.font(.headline)
						.lineLimit(1)
					HStack(spacing: 4) {
						Image(systemName: isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
							.foregroundStyle(isOnline ? .green : .orange)
						Text(node.lastHeard?.lastHeard ?? String(localized: "Never", comment: "Spatial map: node has never been heard"))
							.foregroundStyle(.secondary)
					}
					.font(.caption)
				}
				Spacer(minLength: 0)
				Button(action: onClose) {
					Image(systemName: "xmark")
				}
				.buttonStyle(.borderless)
				.accessibilityLabel(String(localized: "Close"))
			}
			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
				if let role = node.role {
					GridRow {
						Image(systemName: "person.crop.circle")
						Text(role.name)
					}
				}
				GridRow {
					Image(systemName: "cpu")
					Text(hardware)
				}
				if node.isConnectedRadio {
					GridRow {
						Image(systemName: "antenna.radiowaves.left.and.right")
						Text("Connected radio", comment: "Spatial map: the selected node is the connected radio")
					}
				} else {
					GridRow {
						Image(systemName: "arrow.triangle.turn.up.right.diamond")
						Text("\(node.hopsAway) hops away", comment: "Spatial map: hops from the connected radio")
					}
					GridRow {
						Image(systemName: "dot.radiowaves.left.and.right")
						HStack(spacing: 6) {
							Text(verbatim: String(format: "SNR %.1f dB", node.snr))
							if node.rssi != 0 {
								Text(verbatim: "RSSI \(node.rssi) dBm")
							}
							Circle()
								.fill(getSnrColor(snr: node.snr, preset: preset))
								.frame(width: 8, height: 8)
						}
					}
				}
				if node.viaMqtt {
					GridRow {
						Image(systemName: "dot.radiowaves.up.forward")
						Text("via MQTT", comment: "Spatial map: node heard over MQTT")
					}
				}
			}
			.font(.caption)
			.foregroundStyle(.secondary)
			Button(action: onOpen) {
				Label(String(localized: "Open in App", comment: "Showcase card: show this node's detail screen in the main window"), systemImage: "arrow.up.forward.app")
			}
			.font(.caption)
			.buttonStyle(.bordered)
		}
		.padding(12)
		.frame(width: 280)
		.glassBackgroundEffect()
	}

	private var hardware: String {
		if let name = node.hardwareName, !name.isEmpty, name != "UNSET" { return name }
		if let model = node.hwModel, !model.isEmpty, model != "UNSET" { return model }
		return String(localized: "Unknown hardware", comment: "Showcase card: the node hasn't said what hardware it is")
	}
}

/// The card for a model on a display table: what it is, who makes it, and where to buy one. The model is
/// an example of the device, not a node on the mesh.
struct ShowcaseModelCard: View {
	struct Link: Identifiable, Equatable {
		let id: String
		let title: String
		/// The maker's own store rather than a reseller.
		let isVendor: Bool
		let url: URL
	}

	let item: ShowcaseItem
	let links: [Link]
	let onClose: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 10) {
				VStack(alignment: .leading, spacing: 2) {
					Text(item.title)
						.font(.headline)
					Text("Made by \(item.vendor.rawValue)", comment: "Showcase model card: the device's maker")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				Button(action: onClose) {
					Image(systemName: "xmark")
				}
				.buttonStyle(.borderless)
				.accessibilityLabel(String(localized: "Close"))
			}
			if item.deviceNames.count > 1 {
				Text("Also: \(item.deviceNames.dropFirst().formatted(.list(type: .and)))", comment: "Showcase model card: other devices drawn with the same model; the argument is a list of device names")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Label(String(localized: "Pinch and hold to pick it up. It's real size.", comment: "Showcase model card: how to hold the model"), systemImage: "hand.pinch")
				.font(.caption)
			if !links.isEmpty {
				VStack(alignment: .leading, spacing: 6) {
					Text("Where to buy", comment: "Showcase model card: heading for the purchase links")
						.font(.caption.weight(.semibold))
					ForEach(links) { link in
						SwiftUI.Link(destination: link.url) {
							Label(link.title, systemImage: link.isVendor ? "checkmark.seal" : "cart")
								.frame(maxWidth: .infinity, alignment: .leading)
						}
						.font(.caption)
						.buttonStyle(.bordered)
					}
					Text("Product links may be affiliate links — purchases may earn Meshtastic a commission.")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			Text("3D model © Meshtastic LLC. The product and its name, logos and marks belong to \(item.vendor.rawValue).", comment: "Showcase model card: who owns the model and who owns the product; the argument is the maker")
				.font(.caption2)
				.foregroundStyle(.tertiary)
		}
		.padding(12)
		.frame(width: 300)
		.glassBackgroundEffect()
	}
}

/// The small card standing in front of a model on a display table, like a store's: the device's
/// name and what the catalog says it runs on. Drawn at `size`, in meters, so it fits its spot.
struct ShowcasePlacard: View {
	let item: ShowcaseItem
	let size: SIMD2<Float>
	@Environment(\.physicalMetrics) private var metrics

	private var specs: [String] {
		var specs = item.architectures
		if item.hasMui { specs.append("MUI") }
		if item.hasInkHud { specs.append("InkHUD") }
		return specs
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(item.title)
				.font(.system(size: 13, weight: .semibold))
				.lineLimit(2)
				.minimumScaleFactor(0.7)
			Spacer(minLength: 0)
			if !specs.isEmpty {
				Text(specs.joined(separator: " · "))
					.font(.system(size: 10, weight: .medium))
					.foregroundStyle(Color.black.opacity(0.6))
					.lineLimit(1)
					.minimumScaleFactor(0.6)
			}
		}
		.foregroundStyle(Color.black.opacity(0.85))
		.padding(8)
		.frame(
			width: metrics.convert(CGFloat(size.x), from: .meters),
			height: metrics.convert(CGFloat(size.y), from: .meters),
			alignment: .topLeading
		)
		.background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 6))
		.accessibilityElement(children: .combine)
	}
}

/// The control panel by the front table: how many radios are on the rack, its pages, seated or
/// standing, and the way out.
struct ShowcaseControlPanel: View {
	let scene: ShowcaseSceneController
	@Binding var seated: Bool
	let onLeave: () -> Void

	private enum Posture: Hashable {
		case seated, standing
	}

	private var posture: Binding<Posture> {
		Binding(get: { seated ? .seated : .standing }, set: { seated = $0 == .seated })
	}

	var body: some View {
		VStack(spacing: 10) {
			HStack {
				Label(String(localized: "Hardware Showcase", comment: "Showcase: title of the immersive space's control panel"), systemImage: "radio")
					.font(.headline)
				Spacer(minLength: 12)
				Button(role: .cancel, action: onLeave) {
					Label(String(localized: "Leave", comment: "Showcase: close the immersive space"), systemImage: "door.left.hand.open")
				}
			}
			HStack(spacing: 6) {
				Text("\(scene.nodesByNum.count) radios", comment: "Showcase: how many radios are in the room")
				if scene.overflowCount > 0 {
					Text("· \(scene.overflowCount) not shown", comment: "Showcase: radios with no place in the room")
						.foregroundStyle(.secondary)
				}
				if !scene.hasConnectedRadio {
					Text("· No radio connected", comment: "Showcase: no radio is connected, so none stands on the front table")
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
			}
			.font(.caption)
			if scene.rackPageCount > 1 {
				HStack {
					Button {
						scene.setPage(scene.page - 1)
					} label: {
						Image(systemName: "chevron.left")
					}
					.disabled(scene.page == 0)
					.accessibilityLabel(String(localized: "Previous rack page", comment: "Showcase: show the previous page of the wall rack"))
					Text("Rack page \(scene.page + 1) of \(scene.rackPageCount)", comment: "Showcase: which page of the wall rack is showing")
						.font(.caption)
						.monospacedDigit()
						.frame(maxWidth: .infinity)
					Button {
						scene.setPage(scene.page + 1)
					} label: {
						Image(systemName: "chevron.right")
					}
					.disabled(scene.page >= scene.rackPageCount - 1)
					.accessibilityLabel(String(localized: "Next rack page", comment: "Showcase: show the next page of the wall rack"))
				}
			}
			Picker(String(localized: "Position", comment: "Showcase: whether the viewer is sitting or standing"), selection: posture) {
				Text("Seated", comment: "Showcase: the viewer is sitting in the chair").tag(Posture.seated)
				Text("Standing", comment: "Showcase: the viewer is standing").tag(Posture.standing)
			}
			.pickerStyle(.segmented)
		}
		.padding(14)
		.frame(width: 340)
		.glassBackgroundEffect()
	}
}
#endif
