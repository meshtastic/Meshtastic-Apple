//
//  GpsFormats.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation
import MeshtasticProtobufs

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
			return NSLocalizedString("gpsformat.dec", comment: "No comment provided")
		case .gpsFormatDms:
			return NSLocalizedString("gpsformat.dms", comment: "No comment provided")
		case .gpsFormatUtm:
			return NSLocalizedString("gpsformat.utm", comment: "No comment provided")
		case .gpsFormatMgrs:
			return NSLocalizedString("gpsformat.mgrs", comment: "No comment provided")
		case .gpsFormatOlc:
			return NSLocalizedString("gpsformat.olc", comment: "No comment provided")
		case .gpsFormatOsgr:
			return NSLocalizedString("gpsformat.osgr", comment: "No comment provided")
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
		switch self {
		case .thirtySeconds:
			return NSLocalizedString("interval.thirty.seconds", comment: "No comment provided")
		case .oneMinute:
			return NSLocalizedString("interval.one.minute", comment: "No comment provided")
		case .twoMinutes:
			return NSLocalizedString("interval.two.minutes", comment: "No comment provided")
		case .fiveMinutes:
			return NSLocalizedString("interval.five.minutes", comment: "No comment provided")
		case .tenMinutes:
			return NSLocalizedString("interval.ten.minutes", comment: "No comment provided")
		case .fifteenMinutes:
			return NSLocalizedString("interval.fifteen.minutes", comment: "No comment provided")
		case .thirtyMinutes:
			return NSLocalizedString("interval.thirty.minutes", comment: "No comment provided")
		case .oneHour:
			return NSLocalizedString("interval.one.hour", comment: "No comment provided")
		case .sixHours:
			return NSLocalizedString("interval.six.hours", comment: "No comment provided")
		case .twelveHours:
			return NSLocalizedString("interval.twelve.hours", comment: "No comment provided")
		case .twentyFourHours:
			return NSLocalizedString("interval.twentyfour.hours", comment: "No comment provided")
		case .maxInt32:
			return NSLocalizedString("on.boot", comment: "No comment provided")
		}
	}
}

enum GpsMode: Int, CaseIterable, Equatable {
	case enabled = 1
	case disabled = 0
	case notPresent = 2

	var id: Int { self.rawValue }

	var description: String {
		switch self {
		case .disabled:
			return NSLocalizedString("gpsmode.disabled", comment: "No comment provided")
		case .enabled:
			return NSLocalizedString("gpsmode.enabled", comment: "No comment provided")
		case .notPresent:
			return NSLocalizedString("gpsmode.notPresent", comment: "No comment provided")
		}
	}
	func protoEnumValue() -> Config.PositionConfig.GpsMode {

		switch self {

		case .enabled:
			return Config.PositionConfig.GpsMode.enabled
		case .disabled:
			return Config.PositionConfig.GpsMode.disabled
		case .notPresent:
			return Config.PositionConfig.GpsMode.notPresent
		}
	}
}
