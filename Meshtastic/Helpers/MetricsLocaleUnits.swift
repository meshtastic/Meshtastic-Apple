//
//  MetricsLocaleUnits.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/9/26.
//

import Foundation

/// The units sensor readings show in for the current locale (design#53 requirement 2, after
/// design#99). Charts and tables both convert through here so the axis and the reading agree.
enum MetricsLocaleUnits {

	/// The UK keeps miles per hour for wind but uses millimeters and kilograms.
	static var system: Locale.MeasurementSystem { Locale.current.measurementSystem }

	static var windSpeed: UnitSpeed { system == .metric ? .kilometersPerHour : .milesPerHour }
	static var windSpeedLabel: String { system == .metric ? "km/h" : "mph" }

	static var length: UnitLength { system == .us ? .inches : .millimeters }
	static var lengthLabel: String { system == .us ? "in" : "mm" }

	static var mass: UnitMass { system == .us ? .pounds : .kilograms }
	static var massLabel: String { system == .us ? "lb" : "kg" }

	/// Wind arrives in meters per second.
	static func windSpeed(fromMetersPerSecond value: Float) -> Float {
		Float(Measurement(value: Double(value), unit: UnitSpeed.metersPerSecond).converted(to: windSpeed).value)
	}

	/// Rain and distance arrive in millimeters.
	static func length(fromMillimeters value: Float) -> Float {
		Float(Measurement(value: Double(value), unit: UnitLength.millimeters).converted(to: length).value)
	}

	/// Weight arrives in kilograms.
	static func mass(fromKilograms value: Float) -> Float {
		Float(Measurement(value: Double(value), unit: UnitMass.kilograms).converted(to: mass).value)
	}
}
