//
//  ScreenIntervals.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

enum ScreenUnits: Int, CaseIterable, Identifiable {
	
	case metric = 0
	case imperial = 1
   
    var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .metric:
			   return "Metric"
			case .imperial:
			   return "Imperial"
			}
		}
	}
	func protoEnumValue() -> Config.DisplayConfig.DisplayUnits {
		
		switch self {
		case .metric:
			return Config.DisplayConfig.DisplayUnits.metric
		case .imperial:
			return Config.DisplayConfig.DisplayUnits.imperial
		}
	}
}

enum ScreenOnIntervals: Int, CaseIterable, Identifiable {

	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case max = 31536000 // One Year

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			case .max:
				return "Always On"
			}
		}
	}
}
// Default of 0 is off
enum ScreenCarouselIntervals: Int, CaseIterable, Identifiable {

	case off = 0
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .off:
				return "Off"
			case .thirtySeconds:
				return "Thirty Seconds"
			case .oneMinute:
				return "One Minute"
			case .fiveMinutes:
				return "Five Minutes"
			case .tenMinutes:
				return "Ten Minutes"
			case .fifteenMinutes:
				return "Fifteen Minutes"
			}
		}
	}

}
// Default of 0 is auto
enum OledTypes: Int, CaseIterable, Identifiable {

	case auto = 0
	case ssd1306 = 1
	case sh1106 = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .auto:
				return "Automatic Detection"
			case .ssd1306:
				return "SSD 1306"
			case .sh1106:
				return "SH 1106"
			}
		}
	}
	func protoEnumValue() -> Config.DisplayConfig.OledType {
		
		switch self {
		case .auto:
			return Config.DisplayConfig.OledType.oledAuto
		case .ssd1306:
			return Config.DisplayConfig.OledType.oledSsd1306
		case .sh1106:
			return Config.DisplayConfig.OledType.oledSh1106
		}
	}
}
