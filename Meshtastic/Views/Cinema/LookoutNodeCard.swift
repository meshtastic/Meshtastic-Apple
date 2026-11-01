//
//  LookoutNodeCard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/1/26.
//
#if os(visionOS)
import SwiftData
import SwiftUI

/// The card beside a marker out the lookout's windows, so a node can be looked at without turning
/// round to the screen: how far and which way it is, its live readings, and buttons to show it on
/// the 3D map or the screen. For a marker that stands for several nodes, it lists them first.
struct LookoutNodeCard: View {
	/// The marker's nodes, nearest first.
	let labels: [LookoutLabel]
	/// The node picked from a marker's list; ignored when the marker is one node.
	@Binding var chosen: Int64?
	let onShowOnMap: (Int64) -> Void
	let onShowOnScreen: (Int64) -> Void
	let onClose: () -> Void

	var body: some View {
		Group {
			if labels.count == 1 {
				LookoutNodeDetail(label: labels[0], onBack: nil, onShowOnMap: onShowOnMap, onShowOnScreen: onShowOnScreen, onClose: onClose)
			} else if let chosen, let label = labels.first(where: { $0.id == chosen }) {
				LookoutNodeDetail(label: label, onBack: { self.chosen = nil }, onShowOnMap: onShowOnMap, onShowOnScreen: onShowOnScreen, onClose: onClose)
			} else {
				list
			}
		}
		.padding(20)
		.frame(width: 380, alignment: .leading)
		.glassBackgroundEffect()
	}

	private var list: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				Text("\(labels.count) Nodes", comment: "Cinema lookout: title of the card listing the nodes a marker out the window stands for")
					.font(.headline)
				Spacer(minLength: 8)
				LookoutCardCloseButton(action: onClose)
			}
			ScrollView {
				VStack(alignment: .leading, spacing: 4) {
					ForEach(labels) { label in
						Button {
							chosen = label.id
						} label: {
							HStack(spacing: 10) {
								CircleText(text: label.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: label.id))), circleSize: 36)
								Text(verbatim: label.longName)
									.lineLimit(1)
								Spacer(minLength: 8)
								Text(verbatim: LookoutNodeDetail.distance(label.distance))
									.foregroundStyle(.secondary)
							}
							.frame(maxWidth: .infinity, alignment: .leading)
						}
						.buttonStyle(.borderless)
					}
				}
			}
			.frame(maxHeight: 320)
		}
	}
}

/// One node on the lookout's card.
private struct LookoutNodeDetail: View {
	let label: LookoutLabel
	let onBack: (() -> Void)?
	let onShowOnMap: (Int64) -> Void
	let onShowOnScreen: (Int64) -> Void
	let onClose: () -> Void
	@Environment(\.modelContext) private var context
	@State private var reading: CinemaNodeReading?

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .top, spacing: 10) {
				if let onBack {
					Button(action: onBack) {
						Image(systemName: "chevron.backward")
					}
					.buttonBorderShape(.circle)
					.accessibilityLabel(String(localized: "Back to the list", comment: "Cinema lookout: button on a node's card that goes back to the list of nodes the marker stands for"))
				}
				CircleText(text: label.shortName, color: Color(UIColor(hex: UInt32(truncatingIfNeeded: label.id))), circleSize: 40)
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: label.longName)
						.font(.headline)
					Text(verbatim: "\(Self.distance(label.distance)) · \(Int(label.bearing.rounded()) % 360)°")
						.font(.subheadline)
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 8)
				LookoutCardCloseButton(action: onClose)
			}
			if let altitude = label.altitude {
				Label {
					Text(verbatim: Measurement(value: altitude, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))))
				} icon: {
					Image(systemName: "mountain.2")
				}
				.font(.subheadline)
				.accessibilityLabel(Text("Altitude", comment: "Cinema lookout: VoiceOver label for the node's altitude on its card"))
			}
			if let reading {
				CinemaNodeReadings(reading: reading)
			}
			HStack(spacing: 10) {
				Button {
					onShowOnMap(label.id)
				} label: {
					Label(String(localized: "Show on Map", comment: "Cinema lookout: button on a node's card that centers the 3D map on the node"), systemImage: "map")
				}
				Button {
					onShowOnScreen(label.id)
				} label: {
					Label(String(localized: "Show on Screen", comment: "Cinema lookout: button on a node's card that opens the node's details on the cinema's front screen"), systemImage: "tv")
				}
			}
			.font(.subheadline)
		}
		.task(id: label.id) {
			while !Task.isCancelled {
				reading = CinemaNodeReading(nodeNum: label.id, context: context)
				try? await Task.sleep(for: .seconds(CinemaNodeReading.refresh))
			}
		}
	}

	static func distance(_ meters: Double) -> String {
		Measurement(value: meters, unit: UnitLength.meters)
			.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
	}
}

private struct LookoutCardCloseButton: View {
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			Image(systemName: "xmark")
		}
		.buttonBorderShape(.circle)
		.accessibilityLabel(String(localized: "Close", comment: "Cinema lookout: button that closes a node's card beside its marker out the window"))
	}
}
#endif
