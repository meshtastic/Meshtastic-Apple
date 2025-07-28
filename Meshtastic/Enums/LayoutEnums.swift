//
//  LayoutEnums.swift
//  Meshtastic
//
//  Copyright(c) Chase Christiansen Houwen 8/3/25.
//
import Foundation

enum NodeListDensity: Int, CaseIterable, Identifiable {

	case standard = 0
	case compact = 1

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .standard:
			return "Standard".localized
		case .compact:
			return "Compact".localized
		}
	}
}

enum NodeFavoritesLayout: Int, CaseIterable, Identifiable {

	case standard = 0
	case above = 1

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .standard:
			return "Standard".localized
		case .above:
			return "Above".localized
		}
	}
}
