//
//  PositionPopover.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/17/23.
//

import SwiftUI
import MapKit

struct PositionPopover: View {
	var position: PositionEntity
	let distanceFormatter = MKDistanceFormatter()
	var body: some View {
		VStack {
			HStack  {
				CircleText(text: position.nodePosition?.user?.shortName ?? "?", color: Color(UIColor(hex: UInt32(position.nodePosition?.user?.num ?? 0))))
				Text(position.nodePosition?.user?.longName ?? "Unknown")
					.font(.title3)
				let degrees = Angle.degrees(Double(position.heading))
			}
			Divider()
			VStack (alignment: .leading) {
				/// Time
				Label {
					Text(position.time?.formatted() ?? "Unknown")
						.foregroundColor(.primary)
				} icon: {
					Image(systemName: "clock.badge.checkmark")
						.symbolRenderingMode(.hierarchical)
						.frame(width: 35)
				}
				.padding(.bottom, 5)
				/// Coordinate
				Label {
					Text("\(String(format: "%.6f", position.coordinate.latitude)), \(String(format: "%.6f", position.coordinate.longitude))")
						.font(.footnote)
						.textSelection(.enabled)
						.foregroundColor(.primary)
				} icon: {
					Image(systemName: "mappin.and.ellipse")
						.symbolRenderingMode(.hierarchical)
						.frame(width: 35)
				}
				.padding(.bottom, 5)
				/// Altitude
				Label {
					Text("Altitude: \(distanceFormatter.string(fromDistance: Double(position.altitude)))")
						.foregroundColor(.primary)
				} icon: {
					Image(systemName: "mountain.2.fill")
						.symbolRenderingMode(.hierarchical)
						.frame(width: 35)
				}
				.padding(.bottom, 5)
				let pf = PositionFlags(rawValue: Int(position.nodePosition?.metadata?.positionFlags ?? 3))
				/// Sats in view
				if pf.contains(.Satsinview) {
					Label {
						Text("Sats in view: \(String(position.satsInView))")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "sparkles")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Sequence Number
				if pf.contains(.SeqNo) {
					Label {
						Text("Sequence: \(String(position.seqNo))")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "number")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Heading
				if pf.contains(.Heading) {
					let degrees = Angle.degrees(Double(position.heading))
					Label {
						let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
						Text("Heading: \(heading.formatted())")
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "location.north")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
							.rotationEffect(degrees)
					}
					.padding(.bottom, 5)
				}
				/// Speed
				if pf.contains(.Speed) {
					let formatter = MeasurementFormatter()
					Label {
						Text("Speed: \(formatter.string(from: Measurement(value: Double(position.speed), unit: UnitSpeed.kilometersPerHour)))")
					//		.font(.footnote)
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "gauge.with.dots.needle.33percent")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
					.padding(.bottom, 5)
				}
				/// Distance
				if LocationHelper.currentLocation.distance(from: LocationHelper.DefaultLocation) > 0.0 {
					let metersAway = position.coordinate.distance(from: LocationHelper.currentLocation)
					Label {
						Text("distance".localized + ": \(distanceFormatter.string(fromDistance: Double(metersAway)))")
					//		.font(.footnote)
							.foregroundColor(.primary)
					} icon: {
						Image(systemName: "lines.measurement.horizontal")
							.symbolRenderingMode(.hierarchical)
							.frame(width: 35)
					}
				}
			}
		}
	}
}
