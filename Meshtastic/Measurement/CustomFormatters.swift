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

/// Formatter for the frequency-override fields, shared by LoRa and Licensed Operator.
///
/// `TextField(value:formatter:)` writes the RE-PARSED display string back into its
/// binding, and that binding is what gets saved — so rounding here corrupted the
/// stored frequency rather than merely drawing it short. Six fraction digits is
/// headroom for a lossless round trip, not a claim about resolution: the field is a
/// 32-bit `Float`, whose spacing is about 61 Hz at 915 MHz and 244 Hz at 2.4 GHz, so
/// five digits is the most that carries information on any Meshtastic band. Because
/// `minimumFractionDigits` is 0, trailing zeros are stripped and no phantom digit is
/// ever shown — 915 renders as "915", not "915.000000".
///
/// Grouping is off so a decimal comma is never sat next to a grouping period (a
/// de_DE user saw "2.412" for 2412 MHz). Note this also makes `number(from:)` reject
/// a pasted grouping separator.
///
/// Deliberately a computed property: each caller gets its own instance, so a view or
/// a test can set `locale` without reaching into shared state. Do not turn this into
/// a stored `let` to save the allocation.
var frequencyOverrideFormatter: NumberFormatter {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.usesGroupingSeparator = false
	formatter.minimumFractionDigits = 0
	formatter.maximumFractionDigits = 6
	return formatter
}
