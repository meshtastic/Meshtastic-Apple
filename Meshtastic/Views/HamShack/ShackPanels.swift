//
//  ShackPanels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
#if os(visionOS)
import SwiftUI

/// The card for a tapped radio. Reads only the snapshot, never SwiftData.
struct ShackNodeCard: View {
	let node: ShackNodeSnapshot
	let isOnline: Bool
	let preset: ModemPresets
	let onOpen: () -> Void
	let onClose: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				CircleText(text: node.shortName, color: Color(ShackSceneController.nodeColor(node.id)), circleSize: 36)
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
				Label(String(localized: "Open in App", comment: "Ham shack card: show this node's detail screen in the main window"), systemImage: "arrow.up.forward.app")
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
		return String(localized: "Unknown hardware", comment: "Ham shack card: the node hasn't said what hardware it is")
	}
}

/// The panel by the desk: how many radios are in the room, the rack's pages, seated or standing,
/// and the way out.
struct ShackControlPanel: View {
	let scene: ShackSceneController
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
				Label(String(localized: "Ham Shack", comment: "Ham shack: title of the immersive space's control panel"), systemImage: "radio")
					.font(.headline)
				Spacer(minLength: 12)
				Button(role: .cancel, action: onLeave) {
					Label(String(localized: "Leave", comment: "Ham shack: close the immersive space"), systemImage: "door.left.hand.open")
				}
			}
			HStack(spacing: 6) {
				Text("\(scene.nodesByNum.count) radios", comment: "Ham shack: how many radios are in the room")
				if scene.overflowCount > 0 {
					Text("· \(scene.overflowCount) not shown", comment: "Ham shack: radios with no place in the room")
						.foregroundStyle(.secondary)
				}
				if !scene.hasConnectedRadio {
					Text("· No radio connected", comment: "Ham shack: the desk has no connected radio on it")
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
					.accessibilityLabel(String(localized: "Previous rack page", comment: "Ham shack: show the previous page of the wall rack"))
					Text("Rack page \(scene.page + 1) of \(scene.rackPageCount)", comment: "Ham shack: which page of the wall rack is showing")
						.font(.caption)
						.monospacedDigit()
						.frame(maxWidth: .infinity)
					Button {
						scene.setPage(scene.page + 1)
					} label: {
						Image(systemName: "chevron.right")
					}
					.disabled(scene.page >= scene.rackPageCount - 1)
					.accessibilityLabel(String(localized: "Next rack page", comment: "Ham shack: show the next page of the wall rack"))
				}
			}
			Picker(String(localized: "Position", comment: "Ham shack: whether the viewer is sitting or standing"), selection: posture) {
				Text("Seated", comment: "Ham shack: the viewer is sitting in the chair").tag(Posture.seated)
				Text("Standing", comment: "Ham shack: the viewer is standing").tag(Posture.standing)
			}
			.pickerStyle(.segmented)
		}
		.padding(14)
		.frame(width: 340)
		.glassBackgroundEffect()
	}
}
#endif
