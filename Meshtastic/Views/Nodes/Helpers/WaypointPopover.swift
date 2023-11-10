//
//  WaypointPopover.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen on 9/19/23.
//

import SwiftUI
import MapKit

struct WaypointPopover: View {
	@Environment(\.dismiss) private var dismiss
	var waypoint: WaypointEntity
	let distanceFormatter = MKDistanceFormatter()
	var body: some View {
		VStack {
			HStack  {
				CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange, circleSize: 65)
				Spacer()
				Text(waypoint.name ?? "?")
					.font(.largeTitle)
				Spacer()
				if waypoint.locked > 0 {
					Image(systemName: "lock.fill" )
						.font(.largeTitle)
				} else {
					// Edit Button
				}
			}
			Divider()
			VStack (alignment: .leading) {
				// Description
				if (waypoint.longDescription ?? "").count > 0 {
					Label {
						Text(waypoint.longDescription ?? "")
							.foregroundColor(.primary)
							.multilineTextAlignment(.leading)
							.fixedSize(horizontal: false, vertical: true)
					} icon: {
						Image(systemName: "doc.plaintext")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Coordinate
				Label {
					Text("Coordinates: \(String(format: "%.6f", waypoint.coordinate.latitude)), \(String(format: "%.6f", waypoint.coordinate.longitude))")
						.textSelection(.enabled)
						.foregroundColor(.primary)
				} icon: {
					Image(systemName: "mappin.and.ellipse")
						.symbolRenderingMode(.hierarchical)
						.frame(width: 35)
				}
				.padding(.bottom, 5)
				/// Created
				Label {
					Text("Created: \(waypoint.created?.formatted() ?? "?")")
						.foregroundColor(.primary)
				} icon: {
					Image(systemName: "clock.badge.checkmark")
						.symbolRenderingMode(.hierarchical)
						.frame(width: 35)
				}
				.padding(.bottom, 5)
				/// Updated
				if waypoint.lastUpdated != nil {
					Label {
						Text("Updated: \(waypoint.lastUpdated?.formatted() ?? "?")")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "clock.arrow.circlepath")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Expires
				if waypoint.expire != nil {
					Label {
						Text("Expires: \(waypoint.expire?.formatted() ?? "?")")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "hourglass.bottomhalf.filled")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Distance
				if LocationHelper.currentLocation.distance(from: LocationHelper.DefaultLocation) > 0.0 {
					let metersAway = waypoint.coordinate.distance(from: LocationHelper.currentLocation)
					Label {
						Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway)))")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "lines.measurement.horizontal")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
			}
			.padding(.top)
			#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding()
			#endif
		}
		.presentationDetents([.fraction(0.5), .fraction(0.65)])
		.tag(waypoint.id)
	}
}
