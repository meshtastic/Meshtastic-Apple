//
//  Co2Level.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import SwiftUI

/// CO2 bands from design#53, the same as Android's `Co2Severity`.
enum Co2Level: Int, CaseIterable, Identifiable {
	case good = 0
	case stuffy = 1
	case poor = 2
	case unsafe = 3
	case evacuate = 4

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .good:
			return String(localized: "Good", comment: "CO2 level under 1000 ppm")
		case .stuffy:
			return String(localized: "Stuffy", comment: "CO2 level from 1000 to 2000 ppm")
		case .poor:
			return String(localized: "Poor", comment: "CO2 level from 2000 to 5000 ppm")
		case .unsafe:
			return String(localized: "Unsafe", comment: "CO2 level from 5000 to 30000 ppm")
		case .evacuate:
			return String(localized: "Evacuate", comment: "CO2 level of 30000 ppm or more")
		}
	}
	var color: Color {
		switch self {
		case .good:
			return Color(uiColor: .systemGreen)
		case .stuffy:
			return .yellow
		case .poor:
			return Color(uiColor: .systemOrange)
		case .unsafe:
			return Color(uiColor: .systemRed)
		case .evacuate:
			// Color.magenta in the app, which the widget extension doesn't build.
			return Color(red: 0.50, green: 0.00, blue: 0.00)
		}
	}

	static func level(for ppm: UInt32) -> Co2Level {
		switch ppm {
		case ..<1000: .good
		case ..<2000: .stuffy
		case ..<5000: .poor
		case ..<30000: .unsafe
		default: .evacuate
		}
	}
}
