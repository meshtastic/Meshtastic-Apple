//
//  FirmwareEditionEnum.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 2026.
//

import Foundation
import MeshtasticProtobufs

enum FirmwareEditions: Int, CaseIterable, Identifiable {

	case vanilla = 0
	case smartCitizen = 1
	case openSauce = 16
	case defcon = 17
	case burningMan = 18
	case hamvention = 19
	case diyEdition = 127

	var id: Int { self.rawValue }

	var name: String {
		switch self {
		case .vanilla:
			return "Vanilla".localized
		case .smartCitizen:
			return "Smart Citizen".localized
		case .openSauce:
			return "Open Sauce".localized
		case .defcon:
			return "DEFCON".localized
		case .burningMan:
			return "Burning Man".localized
		case .hamvention:
			return "Hamvention".localized
		case .diyEdition:
			return "DIY Edition".localized
		}
	}

	var description: String {
		switch self {
		case .vanilla:
			return "Standard Meshtastic firmware for everyday use.".localized
		case .smartCitizen:
			return "Firmware for the Smart Citizen environmental monitoring network.".localized
		case .openSauce:
			return "Event firmware for Open Sauce, the annual maker conference in California.".localized
		case .defcon:
			return "Event firmware for DEFCON, the annual hacker conference in Las Vegas.".localized
		case .burningMan:
			return "Event firmware for Burning Man, the annual gathering in Black Rock Desert.".localized
		case .hamvention:
			return "Event firmware for Hamvention, the Dayton amateur radio convention.".localized
		case .diyEdition:
			return "Firmware for DIY and unofficial community events.".localized
		}
	}

	var isEvent: Bool {
		self != .vanilla
	}

	/// The stable proto enum name used as the join key against the off-device event-firmware
	/// metadata (`EventFirmwareEntity.edition`). Matches the names in `event_firmware.json`.
	var editionKey: String {
		switch self {
		case .vanilla:
			return "VANILLA"
		case .smartCitizen:
			return "SMART_CITIZEN"
		case .openSauce:
			return "OPEN_SAUCE"
		case .defcon:
			return "DEFCON"
		case .burningMan:
			return "BURNING_MAN"
		case .hamvention:
			return "HAMVENTION"
		case .diyEdition:
			return "DIY_EDITION"
		}
	}

	/// Initialize from the protobuf FirmwareEdition enum
	init(from protoEdition: FirmwareEdition) {
		self = FirmwareEditions(rawValue: protoEdition.rawValue) ?? .vanilla
	}

	/// Initialize from the stable proto edition name (e.g. `"DEFCON"`) used in the
	/// event-firmware metadata payload. Returns nil for an unknown key so callers can ignore
	/// editions this app build doesn't know about.
	init?(editionKey: String) {
		guard let match = FirmwareEditions.allCases.first(where: { $0.editionKey == editionKey }) else {
			return nil
		}
		self = match
	}
}
