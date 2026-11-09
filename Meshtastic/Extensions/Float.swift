//
//  Float.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Float {

	/// Logs pass 1 decimal; tiles keep whole numbers (design#53 requirement 3).
	func formattedTemperature(fractionDigits: Int = 0) -> String {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		let mf = MeasurementFormatter()
		mf.numberFormatter.minimumFractionDigits = fractionDigits
		mf.numberFormatter.maximumFractionDigits = fractionDigits
		return mf.string(from: temperature)
	}
	func shortFormattedTemperature() -> String {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		let mf = MeasurementFormatter()
		mf.unitStyle = .short
		mf.numberFormatter.maximumFractionDigits = 0
		return mf.string(from: temperature)
	}
	func localeTemperature() -> Double {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		let locale = NSLocale.current as NSLocale
		let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
		var format: UnitTemperature = .celsius

		if (localeUnit as? String) == "Fahrenheit" {
			format = .fahrenheit
		}
		return temperature.converted(to: format).value
	}
}
