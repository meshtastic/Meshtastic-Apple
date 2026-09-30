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
	case fab = 20
	case dragonCon = 21
	case ccc = 22
	case diyEdition = 127

	var id: Int { self.rawValue }

	var name: String {
		switch self {
		case .vanilla:
			return String(localized: "Vanilla", comment: "FirmwareEditions.name")
		case .smartCitizen:
			return String(localized: "Smart Citizen", comment: "FirmwareEditions.name")
		case .openSauce:
			return String(localized: "Open Sauce", comment: "FirmwareEditions.name")
		case .defcon:
			return String(localized: "DEFCON", comment: "FirmwareEditions.name")
		case .burningMan:
			return String(localized: "Burning Man", comment: "FirmwareEditions.name")
		case .hamvention:
			return String(localized: "Hamvention", comment: "FirmwareEditions.name")
		case .fab:
			return String(localized: "FAB", comment: "FirmwareEditions.name")
		case .dragonCon:
			return String(localized: "Dragon Con", comment: "FirmwareEditions.name")
		case .ccc:
			return String(localized: "CCC", comment: "FirmwareEditions.name")
		case .diyEdition:
			return String(localized: "DIY Edition", comment: "FirmwareEditions.name")
		}
	}

	var description: String {
		switch self {
		case .vanilla:
			return String(localized: "Standard Meshtastic firmware for everyday use.", comment: "FirmwareEditions.description")
		case .smartCitizen:
			return String(localized: "Firmware for the Smart Citizen environmental monitoring network.", comment: "FirmwareEditions.description")
		case .openSauce:
			return String(localized: "Event firmware for Open Sauce, the annual maker conference in California.", comment: "FirmwareEditions.description")
		case .defcon:
			return String(localized: "Event firmware for DEFCON, the annual hacker conference in Las Vegas.", comment: "FirmwareEditions.description")
		case .burningMan:
			return String(localized: "Event firmware for Burning Man, the annual gathering in Black Rock Desert.", comment: "FirmwareEditions.description")
		case .hamvention:
			return String(localized: "Event firmware for Hamvention, the Dayton amateur radio convention.", comment: "FirmwareEditions.description")
		case .fab:
			return String(localized: "Event firmware for FAB, the international Fab Lab digital fabrication conference.", comment: "FirmwareEditions.description")
		case .dragonCon:
			return String(localized: "Event firmware for Dragon Con, the annual multigenre convention in Atlanta.", comment: "FirmwareEditions.description")
		case .ccc:
			return String(localized: "Event firmware for the Chaos Communication Congress, the annual CCC hacker conference.", comment: "FirmwareEditions.description")
		case .diyEdition:
			return String(localized: "Firmware for DIY and unofficial community events.", comment: "FirmwareEditions.description")
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
		case .fab:
			return "FAB"
		case .dragonCon:
			return "DRAGON_CON"
		case .ccc:
			return "CCC"
		case .diyEdition:
			return "DIY_EDITION"
		}
	}

	/// Edition artwork shipped in the asset catalog for offline fallback. Editions without
	/// bundled artwork fall back to the standard Meshtastic logo.
	var bundledIconAssetName: String? {
		switch self {
		case .hamvention:
			return "EventFirmwareHAMVENTION"
		case .defcon:
			return "EventFirmwareDEFCON"
		case .fab:
			return "EventFirmwareFAB"
		default:
			return nil
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
