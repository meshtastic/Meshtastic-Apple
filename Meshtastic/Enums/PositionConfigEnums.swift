//
//  GpsFormats.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

enum PositionBroadcastIntervals: Int, CaseIterable, Identifiable {

	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 0
	case thirtyMinutes = 1800
	case oneHour = 3600
	case sixHours = 21600
	case twelveHours = 43200
	case twentyFourHours = 86400

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

			case .fifteenSeconds:
				return "Fifteen Seconds"
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
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			case .sixHours:
				return "Six Hours"
			case .twelveHours:
				return "Twelve Hours"
			case .twentyFourHours:
				return "Twenty Four Hours"
			}
		}
	}
}

enum GpsFormats: Int, CaseIterable, Identifiable {

	case gpsFormatDec = 0
	case gpsFormatDms = 1
	case gpsFormatUtm = 2
	case gpsFormatMgrs = 3
	case gpsFormatOlc = 4
	case gpsFormatOsgr = 5

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .gpsFormatDec:
				return "Decimal Degrees Format"
			case .gpsFormatDms:
				return "Degrees Minutes Seconds"
			case .gpsFormatUtm:
				return "Universal Transverse Mercator"
			case .gpsFormatMgrs:
				return "Military Grid Reference System"
			case .gpsFormatOlc:
				return "Open Location Code (aka Plus Codes)"
			case .gpsFormatOsgr:
				return "Ordnance Survey Grid Reference"
			}
		}
	}
	func protoEnumValue() -> Config.DisplayConfig.GpsCoordinateFormat {
		
		switch self {
			
		case .gpsFormatDec:
			return Config.DisplayConfig.GpsCoordinateFormat.dec
		case .gpsFormatDms:
			return Config.DisplayConfig.GpsCoordinateFormat.dms
		case .gpsFormatUtm:
			return Config.DisplayConfig.GpsCoordinateFormat.utm
		case .gpsFormatMgrs:
			return Config.DisplayConfig.GpsCoordinateFormat.mgrs
		case .gpsFormatOlc:
			return Config.DisplayConfig.GpsCoordinateFormat.olc
		case .gpsFormatOsgr:
			return Config.DisplayConfig.GpsCoordinateFormat.osgr
		}
	}
}


enum GpsUpdateIntervals: Int, CaseIterable, Identifiable {

	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 0
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case sixHours = 21600
	case twelveHours = 43200
	case twentyFourHours = 86400
	case maxInt32 = 2147483647

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
				
			case .fiveSeconds:
				return "Five Seconds"
			case .tenSeconds:
				return "Ten Seconds"
			case .fifteenSeconds:
				return "Fifteen Seconds"
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
			case .thirtyMinutes:
				return "Thirty Minutes"
			case .oneHour:
				return "One Hour"
			case .sixHours:
				return "Six Hours"
			case .twelveHours:
				return "Twelve Hours"
			case .twentyFourHours:
				return "Twenty Four Hours"
			case .maxInt32:
				return "On Boot Only"
			}
		}
	}
}

enum GpsAttemptTimes: Int, CaseIterable, Identifiable {

	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 0
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

			case .fiveSeconds:
				return "Five Seconds"
			case .tenSeconds:
				return "Ten Seconds"
			case .fifteenSeconds:
				return "Fifteen Seconds"
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
