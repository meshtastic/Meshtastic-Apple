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
	
	var largeFont: Font = .footnote
	var smallFont: Font = .caption2
	
	@ObservedObject var locationsHandler: LocationsHandler = LocationsHandler.shared
	var body: some View {
		
		if let newLocation = locationsHandler.locationsArray.last {
		let horizontalAccuracy = Measurement(value: newLocation.horizontalAccuracy, unit: UnitLength.meters)
		let verticalAccuracy = Measurement(value: newLocation.verticalAccuracy, unit: UnitLength.meters)
		let altitiude = Measurement(value: newLocation.altitude, unit: UnitLength.meters)
		let speed = Measurement(value: newLocation.speed, unit: UnitSpeed.kilometersPerHour)
		let speedAccuracy = Measurement(value: newLocation.speedAccuracy, unit: UnitSpeed.metersPerSecond)
		let courseAccuracy = Measurement(value: newLocation.courseAccuracy, unit:  UnitAngle.degrees)

			Label("Coordinate \(String(format: "%.5f", newLocation.coordinate.latitude)), \(String(format: "%.5f", newLocation.coordinate.longitude))", systemImage: "mappin")
				.font(largeFont)
				.textSelection(.enabled)
			HStack {
				Label("Accuracy \(horizontalAccuracy.formatted())", systemImage: "scope")
					.font(largeFont)
				Label("Sats Estimate \(LocationsHandler.satsInView)", systemImage: "sparkles")
					.font(largeFont)
				
			}
			HStack {
				if newLocation.verticalAccuracy > 0 {
					Label("Altitude \(altitiude.formatted())", systemImage: "mountain.2")
						.font(largeFont)
				}
				Label("Accuracy \(verticalAccuracy.formatted())", systemImage: "lines.measurement.vertical")
					.font(smallFont)
			}
			HStack {
				let degrees = Angle.degrees(newLocation.course)
				Label {
					let heading = Measurement(value: degrees.degrees, unit: UnitAngle.degrees)
					Text("Heading: \(heading.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))))")
				} icon: {
					Image(systemName: "location.north")
						.symbolRenderingMode(.hierarchical)
						.rotationEffect(degrees)
				}
				.font(largeFont)
				Label("Accuracy \(courseAccuracy.formatted(.measurement(width: .narrow, numberFormatStyle: .number.precision(.fractionLength(0)))))", systemImage: "safari")
					.font(smallFont)
			}
			HStack {
				Label("Speed \(speed.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))", systemImage: "speedometer")
					.font(largeFont)
				Label("Accuracy \(speedAccuracy.formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(0)))))", systemImage: "gauge.with.dots.needle.bottom.50percent.badge.plus")
					.font(smallFont)
			}
		}
	}
}
