//
//  SerialConfigEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/10/22.
//
import Foundation
import MeshtasticProtobufs

enum SerialBaudRates: Int, CaseIterable, Identifiable {

	case baudDefault = 0
	case baud110 = 1
	case baud300 = 2
	case baud600 = 3
	case baud1200 = 4
	case baud2400 = 5
	case baud4800 = 6
	case baud9600 = 7
	case baud19200 = 8
	case baud38400 = 9
	case baud57600 = 10
	case baud115200 = 11
	case baud230400 = 12
	case baud460800 = 13
	case baud576000 = 14
	case baud921600 = 15

	var id: Int { self.rawValue }
	var description: String {
		switch self {

		case .baudDefault:
			return "default".localized
		case .baud110:
			return "110 Baud"
		case .baud300:
			return "300 Baud"
		case .baud600:
			return "600 Baud"
		case .baud1200:
			return "1200 Baud"
		case .baud2400:
			return "2400 Baud"
		case .baud4800:
			return "4800 Baud"
		case .baud9600:
			return "9600 Baud"
		case .baud19200:
			return "19200 Baud"
		case .baud38400:
			return "38400 Baud"
		case .baud57600:
			return "57600 Baud"
		case .baud115200:
			return "115200 Baud"
		case .baud230400:
			return "230400 Baud"
		case .baud460800:
			return "460800 Baud"
		case .baud576000:
			return "576000 Baud"
		case .baud921600:
			return "921600 Baud"
		}
	}

	func protoEnumValue() -> ModuleConfig.SerialConfig.Serial_Baud {

		switch self {

		case .baudDefault:
			return ModuleConfig.SerialConfig.Serial_Baud.baudDefault
		case .baud110:
			return ModuleConfig.SerialConfig.Serial_Baud.baud110
		case .baud300:
			return ModuleConfig.SerialConfig.Serial_Baud.baud300
		case .baud600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud600
		case .baud1200:
			return ModuleConfig.SerialConfig.Serial_Baud.baud1200
		case .baud2400:
			return ModuleConfig.SerialConfig.Serial_Baud.baud2400
		case .baud4800:
			return ModuleConfig.SerialConfig.Serial_Baud.baud4800
		case .baud9600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud9600
		case .baud19200:
			return ModuleConfig.SerialConfig.Serial_Baud.baud19200
		case .baud38400:
			return ModuleConfig.SerialConfig.Serial_Baud.baud38400
		case .baud57600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud57600
		case .baud115200:
			return ModuleConfig.SerialConfig.Serial_Baud.baud115200
		case .baud230400:
			return ModuleConfig.SerialConfig.Serial_Baud.baud230400
		case .baud460800:
			return ModuleConfig.SerialConfig.Serial_Baud.baud460800
		case .baud576000:
			return ModuleConfig.SerialConfig.Serial_Baud.baud576000
		case .baud921600:
			return ModuleConfig.SerialConfig.Serial_Baud.baud921600
		}
	}
}

enum SerialModeTypes: Int, CaseIterable, Identifiable {

	case `default` = 0
	case simple = 1
	case proto = 2
	case txtmsg = 3
	case nmea = 4
	case caltopo = 5

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .default:
			return "serial.mode.default".localized
		case .simple:
			return "serial.mode.simple".localized
		case .proto:
			return "serial.mode.proto".localized
		case .txtmsg:
			return "serial.mode.txtmsg".localized
		case .nmea:
			return "serial.mode.nmea".localized
		case .caltopo:
			return "serial.mode.caltopo".localized
		}
	}
	func protoEnumValue() -> ModuleConfig.SerialConfig.Serial_Mode {

		switch self {

		case .default:
			return ModuleConfig.SerialConfig.Serial_Mode.default
		case .simple:
			return ModuleConfig.SerialConfig.Serial_Mode.simple
		case .proto:
			return ModuleConfig.SerialConfig.Serial_Mode.proto
		case .txtmsg:
			return ModuleConfig.SerialConfig.Serial_Mode.textmsg
		case .nmea:
			return ModuleConfig.SerialConfig.Serial_Mode.nmea
		case .caltopo:
			return ModuleConfig.SerialConfig.Serial_Mode.caltopo
		}
	}
}

enum SerialTimeoutIntervals: Int, CaseIterable, Identifiable {

	case unset = 0
	case oneSecond = 1
	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .unset:
			return "unset".localized
		case .oneSecond:
			return "interval.one.second".localized
		case .fiveSeconds:
			return "interval.five.seconds".localized
		case .tenSeconds:
			return "interval.ten.seconds".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
		case .fiveMinutes:
			return "interval.five.minutes".localized
		}
	}
}
