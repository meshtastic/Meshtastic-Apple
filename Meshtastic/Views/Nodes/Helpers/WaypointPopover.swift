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
							.font(.footnote)
							.multilineTextAlignment(.leading)
							.fixedSize(horizontal: false, vertical: true)
					} icon: {
						Image(systemName: "doc.plaintext")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Created
				Label {
					Text("Created: \(waypoint.created?.formatted() ?? "?")")
						.foregroundColor(.primary)
						.font(.footnote)
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
							.font(.footnote)
					} icon: {
						Image(systemName: "clock.arrow.circlepath")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Updated
				if waypoint.expire != nil {
					Label {
						Text("Expires: \(waypoint.expire?.formatted() ?? "?")")
							.foregroundColor(.primary)
							.font(.footnote)
					} icon: {
						Image(systemName: "clock.badge.xmark")
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
							.font(.footnote)
					} icon: {
						Image(systemName: "lines.measurement.horizontal")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
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
		.tag(waypoint.id)
	}
}
