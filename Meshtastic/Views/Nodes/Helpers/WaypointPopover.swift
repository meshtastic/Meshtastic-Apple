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
		VStack (alignment: .leading) {
			HStack  {
				CircleText(text: String(UnicodeScalar(Int(waypoint.icon)) ?? "📍"), color: Color.orange)
				Text(waypoint.name ?? "?")
					.font(.title3)
				if waypoint.locked > 0 {
					Image(systemName: "lock.fill" )
						.font(.title2)
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
					Divider()
				}
				/// Coordinate
				Label {
					Text("Coordinates: \(String(format: "%.6f", waypoint.coordinate.latitude)), \(String(format: "%.6f", waypoint.coordinate.longitude))")
						//.font(.footnote)
						.textSelection(.enabled)
						.foregroundColor(.primary)
				} icon: {
					Image(systemName: "mappin.and.ellipse")
						.symbolRenderingMode(.hierarchical)
						.frame(width: 35)
				}
				.padding(.bottom, 5)
				Divider()
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
				Divider()
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
					Divider()
				}
				/// Expires
				if waypoint.expire != nil {
					Label {
						Text("Expires: \(waypoint.expire?.formatted() ?? "?")")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "clock.badge.xmark")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
					Divider()
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
					Divider()
				}
			}
			#if targetEnvironment(macCatalyst)
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
		.presentationDetents([.fraction(0.3), .medium])
		.tag(waypoint.id)
	}
}
