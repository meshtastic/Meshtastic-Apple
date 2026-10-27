//
//  SpatialNodeDetailPanel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import CoreLocation
import SwiftUI

/// The node's newest coverage estimate as the card shows it.
enum SpatialCoverageCardState: Equatable {
	case none
	case shown(Date)
	case hidden(Date)
}

enum SpatialCoverageAction {
	/// Open the estimate form for the node in the main window.
	case estimate
	case show
	case hide
}

/// The card tethered to the selected node. Reads only the snapshot, never SwiftData.
struct SpatialNodeDetailPanel: View {
	let node: SpatialNodeSnapshot
	let preset: ModemPresets
	var coverage: SpatialCoverageCardState = .none
	let onOpenNode: () -> Void
	let onCenter: () -> Void
	var onCoverage: ((SpatialCoverageAction) -> Void)?
	let onClose: () -> Void

	var body: some View {
		// Laid out like the cinema's model card. Its colors are fixed rather than left to the glass:
		// over the bright map the glass goes light gray and the text loses its contrast.
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .top, spacing: 10) {
				CircleText(text: node.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: node.id))), circleSize: 48)
				VStack(alignment: .leading, spacing: 2) {
					Text(node.longName)
						.font(.title3.weight(.semibold))
					Text(subtitle)
						.font(.subheadline)
						.foregroundStyle(.white.opacity(0.6))
				}
				Spacer(minLength: 8)
				Button(action: onClose) {
					Image(systemName: "xmark")
						.frame(width: 44, height: 44)
				}
				.buttonStyle(CardButtonStyle(shape: .circle))
				.accessibilityLabel(String(localized: "Close", comment: "Spatial map card: close the selected node's card"))
			}
			readings
			// One row: the card grows to fit the buttons rather than wrapping them.
			HStack(spacing: 8) {
				Button(action: onCenter) {
					Label(String(localized: "Center", comment: "Spatial map: slide the map to put this node in the middle"), systemImage: "scope")
				}
				Button(action: onOpenNode) {
					Label(String(localized: "Node Detail", comment: "Spatial map: open the node's detail screen"), systemImage: "arrow.up.forward.app")
				}
				if let onCoverage {
					coverageMenu(onCoverage)
				}
			}
			.buttonStyle(CardButtonStyle(shape: .rounded))
			.lineLimit(1)
			.fixedSize()
		}
		.foregroundStyle(.white)
		.padding(16)
		.frame(minWidth: 300, alignment: .leading)
		.fixedSize()
		.background(Color(white: 0.11).opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
		.glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
	}

	/// What the node is: the connected radio, or its role.
	private var subtitle: String {
		if node.isConnectedRadio {
			return String(localized: "Connected radio", comment: "Spatial map: the selected node is the connected radio")
		}
		return node.role?.name ?? String(localized: "Node", comment: "Spatial map card: subtitle when the node's role isn't known")
	}

	private var readings: some View {
		Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
			GridRow {
				label(String(localized: "Heard", comment: "Spatial map card: label for when the node was last heard"), systemImage: "clock")
				HStack(spacing: 6) {
					Text(node.lastHeard?.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)) ?? String(localized: "Never", comment: "Spatial map: node has never been heard"))
					// A shape as well as a color, so it reads without telling green from orange.
					Image(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
						.foregroundStyle(node.isOnline ? .green : .orange)
						.accessibilityLabel(node.isOnline
							? String(localized: "Online", comment: "Spatial map card: VoiceOver label for the node's online status")
							: String(localized: "Offline", comment: "Spatial map card: VoiceOver label for the node's offline status"))
				}
			}
			if !node.isConnectedRadio {
				GridRow {
					label(String(localized: "Hops", comment: "Spatial map card: label for how many hops away the node is"), systemImage: "point.3.connected.trianglepath.dotted")
					if node.viaMqtt {
						Text("via MQTT", comment: "Spatial map: node heard over MQTT")
					} else if node.hopsAway == 0 {
						Text("Direct", comment: "Spatial map card: the node is heard directly, no hops")
					} else {
						Text(verbatim: "\(node.hopsAway)")
					}
				}
				GridRow {
					label(String(localized: "Signal", comment: "Spatial map card: label for the node's signal"), systemImage: "cellularbars")
					HStack(spacing: 6) {
						Text(verbatim: String(format: "%.1f dB SNR", node.snr))
						Circle()
							.fill(getSnrColor(snr: node.snr, preset: preset))
							.frame(width: 8, height: 8)
					}
				}
			}
			if let altitude = node.altitude {
				GridRow {
					label(String(localized: "Altitude", comment: "Spatial map card: label for the node's altitude"), systemImage: "mountain.2")
					Text(Measurement(value: altitude, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided))
				}
			}
			GridRow {
				label(String(localized: "Position", comment: "Spatial map card: label for the node's coordinates"), systemImage: node.isPrecise ? "location" : "location.slash")
				Text(verbatim: String(format: "%.5f, %.5f", node.coordinate.latitude, node.coordinate.longitude))
					+ Text(node.isPrecise ? "" : " ~")
			}
		}
		.font(.subheadline)
	}

	private func label(_ title: String, systemImage: String) -> some View {
		Label(title, systemImage: systemImage)
			.foregroundStyle(.white.opacity(0.6))
	}

	/// The card's buttons, in fixed colors like the rest of it: a dark platter, white label, and at
	/// least 44 points each way to hit.
	private struct CardButtonStyle: ButtonStyle {
		enum Shape {
			case circle, rounded
		}
		let shape: Shape

		func makeBody(configuration: Configuration) -> some View {
			let label = configuration.label
				.font(.subheadline.weight(.medium))
				.foregroundStyle(.white)
			Group {
				switch shape {
				case .circle:
					label
						.frame(minWidth: 44, minHeight: 44)
						.background(Color(white: configuration.isPressed ? 0.35 : 0.24), in: Circle())
						.contentShape(.hoverEffect, Circle())
				case .rounded:
					label
						.padding(.horizontal, 12)
						.frame(minWidth: 44, minHeight: 44)
						.background(Color(white: configuration.isPressed ? 0.35 : 0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
						.contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 12, style: .continuous))
				}
			}
			.hoverEffect()
		}
	}

	private func coverageMenu(_ action: @escaping (SpatialCoverageAction) -> Void) -> some View {
		Menu {
			switch coverage {
			case .shown:
				Button {
					action(.hide)
				} label: {
					Label(String(localized: "Hide Coverage", comment: "Spatial map card: stop showing this node's coverage estimate"), systemImage: "eye.slash")
				}
			case .hidden:
				Button {
					action(.show)
				} label: {
					Label(String(localized: "Show Coverage", comment: "Spatial map card: show this node's coverage estimate on the terrain"), systemImage: "eye")
				}
			case .none:
				EmptyView()
			}
			Button {
				action(.estimate)
			} label: {
				if coverage == .none {
					Label(String(localized: "Estimate Coverage…", comment: "Spatial map card: open the coverage estimate form for this node"), systemImage: "antenna.radiowaves.left.and.right")
				} else {
					Label(String(localized: "Re-estimate Coverage…", comment: "Spatial map card: run a new coverage estimate for this node"), systemImage: "arrow.clockwise")
				}
			}
			if let date = estimateDate {
				Text("Estimated \(date.formatted(.relative(presentation: .named)))", comment: "Spatial map card: when this node's coverage estimate was made, e.g. Estimated 2 days ago")
			}
		} label: {
			Label(String(localized: "Coverage", comment: "Spatial map menu: which Site Planner coverage estimates to show on the terrain"), systemImage: "antenna.radiowaves.left.and.right")
		}
		.accessibilityLabel(String(localized: "Coverage estimate", comment: "VoiceOver label for the spatial map card's coverage menu"))
	}

	private var estimateDate: Date? {
		switch coverage {
		case .shown(let date), .hidden(let date): date
		case .none: nil
		}
	}
}
#endif
