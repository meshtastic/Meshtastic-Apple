//
//  CustomFormatters.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 8/4/24.
//

import Foundation

/// Custom altitude formatter that always returns the provided unit
/// Needs to be used in conjunction with logic that checks for metric and displays the right value.
public var altitudeFormatter: MeasurementFormatter {
	let formatter = MeasurementFormatter()
	formatter.unitOptions = .providedUnit
	formatter.unitStyle = .long
	formatter.numberFormatter.maximumFractionDigits = 1
	return formatter
}

var frequencyOverrideFormatter: NumberFormatter {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.usesGroupingSeparator = false
	formatter.minimumFractionDigits = 0
	formatter.maximumFractionDigits = 6
	return formatter
}
