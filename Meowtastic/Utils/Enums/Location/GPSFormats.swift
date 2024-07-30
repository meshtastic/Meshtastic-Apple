import Foundation
import MeshtasticProtobufs

enum GPSFormats: Int, CaseIterable, Identifiable {
	case gpsFormatDec = 0
	case gpsFormatDms = 1
	case gpsFormatUtm = 2
	case gpsFormatMgrs = 3
	case gpsFormatOlc = 4
	case gpsFormatOsgr = 5

	var id: Int {
		self.rawValue
	}

	// TODO: use some user-friendly representation of the format
	var description: String {
		switch self {
		case .gpsFormatDec:
			return "DEC"

		case .gpsFormatDms:
			return "DMS"

		case .gpsFormatUtm:
			return "UTM"

		case .gpsFormatMgrs:
			return "MGRS"

		case .gpsFormatOlc:
			return "OLC"

		case .gpsFormatOsgr:
			return "OSGR"
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
