//
//  Float.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 4/25/23.
//

import Foundation

extension Float {

	func formattedTemperature() -> String {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		return temperature.formatted(.measurement(width: .narrow, usage: .weather))
	}
	func localeTemperature() -> Double {
		let temperature = Measurement<UnitTemperature>(value: Double(self), unit: .celsius)
		let locale = NSLocale.current as NSLocale
		let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
		var format: UnitTemperature = .celsius

		if localeUnit! as? String == "Fahrenheit" {
			format = .fahrenheit
		}
		return temperature.converted(to: format).value
	}
}
