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
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 10) {
				CircleText(text: node.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: node.id))), circleSize: 36)
				VStack(alignment: .leading, spacing: 2) {
					Text(node.longName)
						.font(.headline)
						.lineLimit(1)
					HStack(spacing: 4) {
						Image(systemName: node.isOnline ? "checkmark.circle.fill" : "moon.circle.fill")
							.foregroundStyle(node.isOnline ? .green : .orange)
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
			}
			Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
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
							Circle()
								.fill(getSnrColor(snr: node.snr, preset: preset))
								.frame(width: 8, height: 8)
						}
					}
				}
				if let altitude = node.altitude {
					GridRow {
						Image(systemName: "mountain.2")
						Text(Measurement(value: altitude, unit: UnitLength.meters), format: .measurement(width: .abbreviated, usage: .asProvided))
					}
				}
				GridRow {
					Image(systemName: node.isPrecise ? "location" : "location.slash")
					Text(verbatim: String(format: "%.5f, %.5f", node.coordinate.latitude, node.coordinate.longitude))
						+ Text(node.isPrecise ? "" : " ~")
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
			HStack {
				Button(action: onCenter) {
					Label(String(localized: "Center", comment: "Spatial map: slide the map to put this node in the middle"), systemImage: "scope")
				}
				Button(action: onOpenNode) {
					Label(String(localized: "Node Detail", comment: "Spatial map: open the node's detail screen"), systemImage: "arrow.up.forward.app")
				}
			}
			.font(.caption)
			.buttonStyle(.bordered)
			if let onCoverage {
				coverageMenu(onCoverage)
					.font(.caption)
					.buttonStyle(.bordered)
			}
		}
		.padding(12)
		.frame(width: 270)
		.glassBackgroundEffect()
	}

	/// On its own row: the button row has no room for a third button.
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
