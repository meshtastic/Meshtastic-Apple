//
//  GpsFormats.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/20/22.
//

import Foundation
import MeshtasticProtobufs

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
			return String(localized: "Thirty Seconds", comment: "GpsUpdateIntervals.description")
		case .oneMinute:
			return String(localized: "One Minute", comment: "GpsUpdateIntervals.description")
		case .twoMinutes:
			return String(localized: "Two Minutes", comment: "GpsUpdateIntervals.description")
		case .fiveMinutes:
			return String(localized: "Five Minutes", comment: "GpsUpdateIntervals.description")
		case .tenMinutes:
			return String(localized: "Ten Minutes", comment: "GpsUpdateIntervals.description")
		case .fifteenMinutes:
			return String(localized: "Fifteen Minutes", comment: "GpsUpdateIntervals.description")
		case .thirtyMinutes:
			return String(localized: "Thirty Minutes", comment: "GpsUpdateIntervals.description")
		case .oneHour:
			return String(localized: "One Hour", comment: "GpsUpdateIntervals.description")
		case .sixHours:
			return String(localized: "Six Hours", comment: "GpsUpdateIntervals.description")
		case .twelveHours:
			return String(localized: "Twelve Hours", comment: "GpsUpdateIntervals.description")
		case .twentyFourHours:
			return String(localized: "Twenty Four Hours", comment: "GpsUpdateIntervals.description")
		case .maxInt32:
			return String(localized: "On Boot Only", comment: "GpsUpdateIntervals.description")
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
			return "Disabled".localized
		case .enabled:
			return "Enabled".localized
		case .notPresent:
			return "Not Present".localized
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
