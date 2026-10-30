//
//  LookoutNodeLabel.swift
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
	let isRadio: Bool
}

/// A node's chip, name and distance, hung over where the node is out the lookout's windows.
/// Tapping it centers the 3D map on the node and opens its details on the screen.
struct LookoutNodeLabel: View {
	let label: LookoutLabel
	let onTap: () -> Void

	var body: some View {
		Button(action: onTap) {
			VStack(spacing: 2) {
				HStack(spacing: 10) {
					NodeChip(shortName: label.shortName, colorSeed: UInt32(truncatingIfNeeded: label.id), size: 72)
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: label.longName)
							.font(.system(size: 36, weight: .semibold))
							.lineLimit(1)
						Text(verbatim: Measurement(value: label.distance, unit: UnitLength.meters)
							.formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1)))))
							.font(.system(size: 28))
							.foregroundStyle(.secondary)
					}
				}
				.padding(.horizontal, 20)
				.padding(.vertical, 12)
				.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
				// Points at the spot on the ground.
				Image(systemName: "arrowtriangle.down.fill")
					.font(.system(size: 22))
					.foregroundStyle(label.isRadio ? Color.accentColor : Color.primary)
			}
		}
		.buttonStyle(.plain)
		.hoverEffect(.highlight)
		.accessibilityLabel(Text("\(label.longName), \(Int(label.distance.rounded())) meters, bearing \(Int(label.bearing.rounded())) degrees", comment: "Cinema lookout: VoiceOver label for a node's marker out the window"))
	}
}
#endif
