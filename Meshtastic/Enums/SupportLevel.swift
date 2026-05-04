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
			return "Discontinued".localized
		case .flagship:
			return "Flagship".localized
		case .niche:
			return "Niche".localized
		case .legacy:
			return "Legacy".localized
		}
	}

	var description: String {
		switch self {
		case .discontinued:
			return "This device is no longer supported and does not receive firmware updates.".localized
		case .flagship:
			return "Recommended device with full feature support and active development.".localized
		case .niche:
			return "Supported niche device with active firmware updates and a specialized form factor.".localized
		case .legacy:
			return "Older or legacy device that still receives firmware updates but may lack some features.".localized
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
