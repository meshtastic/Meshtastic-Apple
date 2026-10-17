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

	/// Read from across the room: it floats off the wall rack, a few meters away.
	static let width: CGFloat = 560

	var body: some View {
		VStack(alignment: .leading, spacing: 22) {
			header
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
				if node.isConnectedRadio {
					tile(String(localized: "Connected"), icon: "antenna.radiowaves.left.and.right") {
						Text("Connected radio", comment: "Spatial map: the selected node is the connected radio")
					}
				} else {
					tile(String(localized: "SNR"), icon: "dot.radiowaves.left.and.right") {
						HStack(spacing: 8) {
							Circle()
								.fill(getSnrColor(snr: node.snr, preset: preset))
								.frame(width: 14, height: 14)
							Text(verbatim: String(format: "%.1f dB", node.snr))
						}
						if node.rssi != 0 {
							Text(verbatim: "RSSI \(node.rssi) dBm")
								.font(.callout)
								.foregroundStyle(.secondary)
						}
					}
					tile(String(localized: "Hops Away"), icon: "arrow.triangle.turn.up.right.diamond") {
						if node.hopsAway == 0 {
							Text("Direct")
						} else {
							Text(verbatim: "\(node.hopsAway)")
						}
					}
				}
				if let role = node.role {
					tile(String(localized: "Role"), icon: "person.crop.circle") {
						Text(role.name)
					}
				}
				tile(String(localized: "Hardware"), icon: "cpu") {
					Text(hardware)
						.lineLimit(2)
						.minimumScaleFactor(0.7)
				}
			}
			Button(action: onOpen) {
				Label(String(localized: "Open in App", comment: "Showcase card: show this node's detail screen in the main window"), systemImage: "arrow.up.forward.app")
					.font(.title3.weight(.semibold))
					.frame(maxWidth: .infinity)
					.padding(.vertical, 6)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)
		}
		.padding(30)
		.frame(width: Self.width)
		.glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
	}

	private var header: some View {
		HStack(alignment: .top, spacing: 18) {
			CircleText(text: node.shortName, color: Color(ShowcaseSceneController.nodeColor(node.id)), circleSize: 84)
			VStack(alignment: .leading, spacing: 8) {
				Text(node.longName)
					.font(.largeTitle.weight(.bold))
					.lineLimit(2)
					.minimumScaleFactor(0.6)
				Text(verbatim: "\(node.shortName) · !\(String(format: "%08x", UInt32(truncatingIfNeeded: node.id)))")
					.font(.title3.monospaced())
					.foregroundStyle(.secondary)
				HStack(spacing: 10) {
					Label(isOnline ? String(localized: "Online") : String(localized: "Offline"), systemImage: isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
						.font(.headline)
						.padding(.horizontal, 12)
						.padding(.vertical, 6)
						.background((isOnline ? Color.green : Color.orange).opacity(0.25), in: Capsule())
						.foregroundStyle(isOnline ? .green : .orange)
					if node.viaMqtt {
						Label(String(localized: "via MQTT", comment: "Spatial map: node heard over MQTT"), systemImage: "dot.radiowaves.up.forward")
							.font(.headline)
							.padding(.horizontal, 12)
							.padding(.vertical, 6)
							.background(.quaternary, in: Capsule())
					}
				}
				Text(node.lastHeard?.lastHeard ?? String(localized: "Never", comment: "Spatial map: node has never been heard"))
					.font(.title3)
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
			Button(action: onClose) {
				Image(systemName: "xmark")
					.font(.title2.weight(.semibold))
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.circle)
			.accessibilityLabel(String(localized: "Close"))
		}
	}

	/// One fact about the node: a small label over a large value.
	private func tile<Content: View>(_ title: String, icon: String, @ViewBuilder value: () -> Content) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			Label(title, systemImage: icon)
				.font(.callout.weight(.semibold))
				.foregroundStyle(.secondary)
			VStack(alignment: .leading, spacing: 4) {
				value()
			}
			.font(.title2.weight(.semibold))
		}
		.frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
		.padding(16)
		.background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
					Text("Made by \(item.vendor.name)", comment: "Showcase model card: the device's maker")
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
					Text("Product links may be affiliate links — purchases may earn Meshtastic a commission.", comment: "Affiliate disclosure shown above msh.to product links")
						.font(.caption2)
						.foregroundStyle(.secondary)
				}
			}
			Text("3D model © Meshtastic LLC. The product and its name, logos and marks belong to \(item.vendor.name).", comment: "Showcase model card: who owns the model and who owns the product; the argument is the maker")
				.font(.caption2)
				.foregroundStyle(.tertiary)
		}
		.padding(12)
		.frame(width: 300)
		.glassBackgroundEffect()
	}
}

/// The control panel by the front table: how many radios are on the rack, its pages, seated or
/// standing, and the way out.
struct ShowcaseControlPanel: View {
	let scene: ShowcaseSceneController
	@Binding var seated: Bool
	/// Whether the app's window is open; the panel can hide it or bring it back.
	let isAppShowing: Bool
	let onToggleApp: () -> Void
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
				Label(String(localized: "Meshtastic Hardware Showcase", comment: "Showcase: title of the immersive space's control panel"), systemImage: "storefront")
					.font(.headline)
					.lineLimit(1)
					.minimumScaleFactor(0.8)
				Spacer(minLength: 12)
				Button(role: .cancel, action: onLeave) {
					Label(String(localized: "Leave", comment: "Showcase: close the immersive space"), systemImage: "door.left.hand.open")
				}
			}
			HStack(spacing: 6) {
				// Every radio, past the reader's limit too, so it adds up with the "not shown" count.
				Text("\(scene.totalCount) radios", comment: "Showcase: how many radios are in the room")
				if scene.overflowCount > 0 {
					Text("· \(scene.overflowCount) not shown", comment: "Showcase: radios with no place in the room")
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				// The rack is one element to VoiceOver; this lists its radios so each can be opened.
				if !scene.nodesOnPage.isEmpty {
					Menu {
						ForEach(scene.nodesOnPage) { node in
							Button {
								scene.selected = node.id
							} label: {
								Label(node.longName, systemImage: scene.isOnline(node.id) ? "checkmark.circle.fill" : "moon.circle.fill")
							}
						}
					} label: {
						Label(String(localized: "Radios on this page", comment: "Showcase: menu listing the radios on the wall rack page that's showing; picking one opens its card"), systemImage: "list.bullet")
					}
				}
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
			HStack(spacing: 8) {
				Picker(String(localized: "Position", comment: "Showcase: whether the viewer is sitting or standing"), selection: posture) {
					Text("Seated", comment: "Showcase: the viewer is sitting in the chair").tag(Posture.seated)
					Text("Standing", comment: "Showcase: the viewer is standing").tag(Posture.standing)
				}
				.pickerStyle(.segmented)
				Button(action: onToggleApp) {
					if isAppShowing {
						Label(String(localized: "Hide App", comment: "Showcase: close the app's window while in the showcase"), systemImage: "macwindow.badge.minus")
					} else {
						Label(String(localized: "Show App", comment: "Showcase: bring back the app's window while in the showcase"), systemImage: "macwindow")
					}
				}
				.fixedSize()
			}
		}
		.padding(14)
		.frame(width: 440)
		.glassBackgroundEffect()
	}
}
#endif
