//
//  Measurement.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/17/23.
//

import Foundation
import Charts

extension Measurement where UnitType == UnitAngle {
	func reciprocal() -> Measurement {
		var recip = self.converted(to: .degrees)
		recip.value = (recip.value + 180).truncatingRemainder(dividingBy: 360)
		return recip.converted(to: self.unit)
	}
}

struct PlottableMeasurement<UnitType: Unit> {
	var measurement: Measurement<UnitType>
}

extension PlottableMeasurement: Plottable where UnitType == UnitLength {
	var primitivePlottable: Double {
		self.measurement.converted(to: .meters).value
	}

	init?(primitivePlottable: Double) {
		self.init(
			measurement: Measurement(
				value: primitivePlottable,
				unit: .meters
			)
		)
	}
}
