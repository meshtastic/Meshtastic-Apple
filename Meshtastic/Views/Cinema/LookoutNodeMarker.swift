//
//  LookoutNodeMarker.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import CoreLocation
import SwiftUI

/// A node as seen from the lookout: where it sits by bearing and distance from the cab.
struct LookoutLabel: Identifiable, Equatable, Sendable {
	let id: Int64
	let shortName: String
	let longName: String
	/// Meters from the cab, over the ground.
	let distance: Double
	/// True bearing from the cab, degrees.
	let bearing: Double
	/// The node's ground above the eye in meters, before the Earth's curve is taken off.
	let rise: Double
	/// The node's ground above sea level in meters, when it's known.
	let altitude: Double?
	let isRadio: Bool
}

/// A node's chip, hung over where the node is out the lookout's windows. When nodes are too close
/// together to tell apart, the nearest one's chip stands for them all, with how many there are.
/// Selecting it opens the node's card beside it.
struct LookoutNodeMarker: View {
	let labels: [LookoutLabel]
	let onTap: () -> Void

	/// The marker's points, square so it's as tall as it is wide.
	static let size: CGFloat = 112

	var body: some View {
		let lead = labels[0]
		Button(action: onTap) {
			NodeChip(shortName: lead.shortName, colorSeed: UInt32(truncatingIfNeeded: lead.id), size: 84)
				.overlay {
					if lead.isRadio {
						Circle().strokeBorder(Color.accentColor, lineWidth: 6)
					}
				}
				.frame(width: Self.size, height: Self.size)
				.overlay(alignment: .topTrailing) {
					if labels.count > 1 {
						Text(verbatim: "\(labels.count)")
							.font(.system(size: 30, weight: .bold))
							.monospacedDigit()
							.padding(.horizontal, 8)
							.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
					}
				}
		}
		.buttonStyle(.plain)
		.hoverEffect(.highlight)
		.accessibilityLabel(accessibilityText)
	}

	private var accessibilityText: Text {
		let lead = labels[0]
		if labels.count > 1 {
			return Text("\(labels.count) nodes near \(lead.longName), \(Int(lead.distance.rounded())) meters, bearing \(Int(lead.bearing.rounded())) degrees", comment: "Cinema lookout: VoiceOver label for a marker out the window that stands for several nodes close together")
		}
		return Text("\(lead.longName), \(Int(lead.distance.rounded())) meters, bearing \(Int(lead.bearing.rounded())) degrees", comment: "Cinema lookout: VoiceOver label for a node's marker out the window")
	}
}
#endif
