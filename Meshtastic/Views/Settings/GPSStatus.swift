//
//  GPSStatus.swift
//  Meshtastic
//
//  Copyright(c) by Garth Vander Houwen 12/22/23.
//

import SwiftUI
import CoreLocation

@available(iOS 17.0, macOS 14.0, *)
struct GPSStatus: View {
	
	@ObservedObject var locationsHandler: LocationsHandler = LocationsHandler.shared
	var body: some View {
		let horizontalAccuracy = Measurement(value: locationsHandler.lastLocation.horizontalAccuracy, unit: UnitLength.meters)
		let verticalAccuracy = Measurement(value: locationsHandler.lastLocation.verticalAccuracy, unit: UnitLength.meters)
		let altitiude = Measurement(value: locationsHandler.lastLocation.altitude, unit: UnitLength.meters)
		let speed = Measurement(value: locationsHandler.lastLocation.speed, unit: UnitSpeed.kilometersPerHour)
		let speedAccuracy = Measurement(value: locationsHandler.lastLocation.speedAccuracy, unit: UnitSpeed.metersPerSecond)
		let courseAccuracy = Measurement(value: locationsHandler.lastLocation.courseAccuracy, unit:  UnitAngle.degrees)
		Label("Coordinate \(String(format: "%.5f", locationsHandler.lastLocation.coordinate.latitude)), \(String(format: "%.5f", LocationsHandler.shared.lastLocation.coordinate.longitude))", systemImage: "mappin")
			.font(.footnote)
			.textSelection(.enabled)
		HStack {
			Label("Accuracy \(horizontalAccuracy.formatted())", systemImage: "scope")
				.font(.footnote)
			Label("Sats Estimate \(LocationsHandler.satsInView)", systemImage: "sparkles")
				.font(.footnote)
		}
		HStack {
			if locationsHandler.lastLocation.verticalAccuracy > 0 {
				Label("Altitude \(altitiude.formatted())", systemImage: "mountain.2")
					.font(.footnote)
			}
			Label("Accuracy \(verticalAccuracy.formatted())", systemImage: "lines.measurement.vertical")
				.font(.caption2)
		}
		HStack {
			let degrees = Angle.degrees(LocationsHandler.shared.lastLocation.course)
			Label {
				let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
				Text("Heading: \(heading.formatted())")
			} icon: {
				Image(systemName: "location.north")
					.symbolRenderingMode(.hierarchical)
					.rotationEffect(degrees)
			}
			.font(.footnote)
			Label("Accuracy \(courseAccuracy.formatted())", systemImage: "safari")
				.font(.caption2)
		}
		HStack {
			Label("Speed \(speed.formatted())", systemImage: "speedometer")
				.font(.footnote)
			Label("Accuracy \(speedAccuracy.formatted())", systemImage: "gauge.with.dots.needle.bottom.50percent.badge.plus")
				.font(.caption2)
		}
	}
}
