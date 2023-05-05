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
		switch self {
		case .gpsFormatDec:
			return "gpsformat.dec".localized
		case .gpsFormatDms:
			return "gpsformat.dms".localized
		case .gpsFormatUtm:
			return "gpsformat.utm".localized
		case .gpsFormatMgrs:
			return "gpsformat.mgrs".localized
		case .gpsFormatOlc:
			return "gpsformat.olc".localized
		case .gpsFormatOsgr:
			return "gpsformat.osgr".localized
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
	case fortyFiveSeconds = 45
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
		switch self {
		case .fiveSeconds:
			return "interval.five.seconds".localized
		case .tenSeconds:
			return "interval.ten.seconds".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .twentySeconds:
			return "interval.twenty.seconds".localized
		case .twentyFiveSeconds:
			return "interval.twentyfive.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .fortyFiveSeconds:
			return "interval.fortyfive.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
		case .twoMinutes:
			return "interval.two.minutes".localized
		case .fiveMinutes:
			return "interval.five.minutes".localized
		case .tenMinutes:
			return "interval.ten.minutes".localized
		case .fifteenMinutes:
			return "interval.fifteen.minutes".localized
		case .thirtyMinutes:
			return "interval.thirty.minutes".localized
		case .oneHour:
			return "interval.one.hour".localized
		case .sixHours:
			return "interval.six.hours".localized
		case .twelveHours:
			return "interval.twelve.hours".localized
		case .twentyFourHours:
			return "interval.twentyfour.hours".localized
		case .maxInt32:
			return "on.boot"
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
	case fortyFiveSeconds = 45
	case oneMinute = 60
	case twoMinutes = 120
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .twoSeconds:
			return "interval.two.seconds".localized
		case .fiveSeconds:
			return "interval.five.seconds".localized
		case .tenSeconds:
			return "interval.ten.seconds".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .twentySeconds:
			return "interval.twenty.seconds".localized
		case .twentyFiveSeconds:
			return "interval.twentyfive.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .fortyFiveSeconds:
			return "interval.fortyfive.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
		case .twoMinutes:
			return "interval.two.minutes".localized
		case .fiveMinutes:
			return "interval.five.minutes".localized
		case .tenMinutes:
			return "interval.ten.minutes".localized
		case .fifteenMinutes:
			return "interval.fifteen.minutes".localized
		}
	}
}
