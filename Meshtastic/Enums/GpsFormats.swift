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
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatDec
		case .gpsFormatDms:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatDms
		case .gpsFormatUtm:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatUtm
		case .gpsFormatMgrs:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatMgrs
		case .gpsFormatOlc:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatOlc
		case .gpsFormatOsgr:
			return Config.DisplayConfig.GpsCoordinateFormat.gpsFormatOsgr
		}
	}
}
