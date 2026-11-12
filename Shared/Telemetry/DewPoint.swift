//
//  DewPoint.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import Foundation

/// Magnus Formula
func calculateDewPoint(temp: Float, relativeHumidity: Float, convertToLocale: Bool = true) -> Double {
	let a: Float = 17.27
	let b: Float = 237.7
	let alpha = ((a * temp) / (b + temp)) + log(relativeHumidity / 100.0)
	let dewPoint = (b * alpha) / (a - alpha)
	let dewPointUnit = Measurement<UnitTemperature>(value: Double(dewPoint), unit: .celsius)
	
	if !convertToLocale {
		return Double(dewPoint)
	}
	
	// Otherwise convert to locale units, default behavior
	let locale = NSLocale.current as NSLocale
	let localeUnit = locale.object(forKey: NSLocale.Key(rawValue: "kCFLocaleTemperatureUnitKey"))
	var format: UnitTemperature = .celsius

	if (localeUnit as? String) == "Fahrenheit" {
		format = .fahrenheit
	}
	return dewPointUnit.converted(to: format).value
}
