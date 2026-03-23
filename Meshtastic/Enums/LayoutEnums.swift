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

/**
 This enum contains the keys for different UserDefault preferences for convenience
 */
enum NodeListPreferences: String {
	case shouldShowLocation
	case shouldShowTelemetry
	case shouldShowPower
	case lastHeardIsRelative
	case shouldShowLastHeard
}
