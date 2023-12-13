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
