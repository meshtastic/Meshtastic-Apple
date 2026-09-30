//
//  SupportLevel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 5/3/26.
//

import Foundation

enum SupportLevel: Int, CaseIterable, Identifiable {

	case discontinued = 0
	case flagship = 1
	case niche = 2
	case legacy = 3

	var id: Int { self.rawValue }

	var name: String {
		switch self {
		case .discontinued:
			return String(localized: "Discontinued", comment: "SupportLevel.name")
		case .flagship:
			return String(localized: "Flagship", comment: "SupportLevel.name")
		case .niche:
			return String(localized: "Niche", comment: "SupportLevel.name")
		case .legacy:
			return String(localized: "Legacy", comment: "SupportLevel.name")
		}
	}

	var description: String {
		switch self {
		case .discontinued:
			return String(localized: "This device is no longer supported and does not receive firmware updates.", comment: "SupportLevel.description")
		case .flagship:
			return String(localized: "Recommended device with full feature support and active development.", comment: "SupportLevel.description")
		case .niche:
			return String(localized: "Supported niche device with active firmware updates and a specialized form factor.", comment: "SupportLevel.description")
		case .legacy:
			return String(localized: "Older or legacy device that still receives firmware updates but may lack some features.", comment: "SupportLevel.description")
		}
	}

	var isSupported: Bool {
		switch self {
		case .discontinued:
			return false
		case .flagship, .niche, .legacy:
			return true
		}
	}
}
