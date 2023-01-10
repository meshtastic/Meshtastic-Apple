//
//  GpsFormats.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation

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
				return NSLocalizedString("gpsformat.dec", comment: "Decimal Degrees Format")
			case .gpsFormatDms:
				return NSLocalizedString("gpsformat.dms", comment: "Degrees Minutes Seconds")
			case .gpsFormatUtm:
				return NSLocalizedString("gpsformat.utm", comment: "Universal Transverse Mercator")
			case .gpsFormatMgrs:
				return NSLocalizedString("gpsformat.mgrs", comment: "Military Grid Reference System")
			case .gpsFormatOlc:
				return NSLocalizedString("gpsformat.olc", comment: "Open Location Code (aka Plus Codes)")
			case .gpsFormatOsgr:
				return NSLocalizedString("gpsformat.osgr", comment: "Ordnance Survey Grid Reference")
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
	case twentySeconds = 20
	case twentyFiveSeconds = 25
	case thirtySeconds = 30
	case oneMinute = 60
	case twoMinutes = 120
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
				return NSLocalizedString("interval.five.seconds", comment: "Five Seconds")
			case .tenSeconds:
				return NSLocalizedString("interval.ten.seconds", comment: "Ten Seconds")
			case .fifteenSeconds:
				return NSLocalizedString("interval.fifteen.seconds", comment: "Fifteen Seconds")
			case .twentySeconds:
				return NSLocalizedString("interval.twenty.seconds", comment: "Twenty Seconds")
			case .twentyFiveSeconds:
				return NSLocalizedString("interval.twentyfive.seconds", comment: "Twenty Five Seconds")
			case .thirtySeconds:
				return NSLocalizedString("interval.thirty.seconds", comment: "Thirty Seconds")
			case .oneMinute:
				return NSLocalizedString("interval.one.minute", comment: "One Minute")
			case .twoMinutes:
				return NSLocalizedString("interval.two.minutes", comment: "Two Minutes")
			case .fiveMinutes:
				return NSLocalizedString("interval.five.minutes", comment: "Five Minutes")
			case .tenMinutes:
				return NSLocalizedString("interval.ten.minutes", comment: "Ten Minutes")
			case .fifteenMinutes:
				return NSLocalizedString("interval.fifteen.minutes", comment: "Fifteen Minutes")
			case .thirtyMinutes:
				return NSLocalizedString("interval.thirty.minutes", comment: "Thirty Minutes")
			case .oneHour:
				return NSLocalizedString("interval.one.hour", comment: "One Hour")
			case .sixHours:
				return NSLocalizedString("interval.six.hours", comment: "Six Hours")
			case .twelveHours:
				return NSLocalizedString("interval.twelve.hours", comment: "Twelve Hours")
			case .twentyFourHours:
				return NSLocalizedString("interval.twentyfour.hours", comment: "Twenty Four Hours")
			case .maxInt32:
				return NSLocalizedString("on.boot", comment: "On Boot Only")
			}
		}
	}
}

enum GpsAttemptTimes: Int, CaseIterable, Identifiable {

	case twoSeconds = 2
	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case twentySeconds = 20
	case twentyFiveSeconds = 25
	case thirtySeconds = 30
	case oneMinute = 60
	case twoMinutes = 120
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {

			case .twoSeconds:
				return NSLocalizedString("interval.two.seconds", comment: "Two Seconds")
			case .fiveSeconds:
				return NSLocalizedString("interval.five.seconds", comment: "Five Seconds")
			case .tenSeconds:
				return NSLocalizedString("interval.ten.seconds", comment: "Ten Seconds")
			case .fifteenSeconds:
				return NSLocalizedString("interval.fifteen.seconds", comment: "Fifteen Seconds")
			case .twentySeconds:
				return NSLocalizedString("interval.twenty.seconds", comment: "Twenty Seconds")
			case .twentyFiveSeconds:
				return NSLocalizedString("interval.twentyfive.seconds", comment: "Twenty Five Seconds")
			case .thirtySeconds:
				return NSLocalizedString("interval.thirty.seconds", comment: "Thirty Seconds")
			case .oneMinute:
				return NSLocalizedString("interval.one.minute", comment: "One Minute")
			case .twoMinutes:
				return NSLocalizedString("interval.two.minutes", comment: "Two Minutes")
			case .fiveMinutes:
				return NSLocalizedString("interval.five.minutes", comment: "Five Minutes")
			case .tenMinutes:
				return NSLocalizedString("interval.ten.minutes", comment: "Ten Minutes")
			case .fifteenMinutes:
				return NSLocalizedString("interval.fifteen.minutes", comment: "Fifteen Minutes")
			}
		}
	}
}
