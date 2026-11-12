//
//  TelemetryEnums.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 4/9/24.
//

import Foundation
import SwiftUI

enum Aqi: Int, CaseIterable, Identifiable {
	case good = 0
	case moderate = 1
	case sensitive = 2
	case unhealthy = 3
	case veryUnhealthy = 4
	case hazardous = 5

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .good:
			return String(localized: "Good", comment: "Aqi.description")
		case .moderate:
			return String(localized: "Moderate", comment: "Aqi.description")
		case .sensitive:
			return String(localized: "Unhealthy for Sensitive Groups", comment: "Aqi.description")
		case .unhealthy:
			return String(localized: "Unhealthy", comment: "Aqi.description")
		case .veryUnhealthy:
			return String(localized: "Very Unhealthy", comment: "Aqi.description")
		case .hazardous:
			return String(localized: "Hazardous", comment: "Aqi.description")
		}
	}
	var color: Color {
		switch self {
		case .good:
			return Color(uiColor: .systemGreen)
		case .moderate:
			return .yellow
		case .sensitive:
			return Color(uiColor: .systemOrange)
		case .unhealthy:
			return Color(uiColor: .systemRed)
		case .veryUnhealthy:
			return .purple
		case .hazardous:
			return .magenta
		}
	}
	var range: Range<Int> {
		switch self {
		case .good:
			return Range(0...50)
		case .moderate:
			return Range(51...100)
		case .sensitive:
			return Range(101...150)
		case .unhealthy:
			return Range(151...200)
		case .veryUnhealthy:
			return Range(201...300)
		case .hazardous:
			return Range(301...500)
		}
	}

	static func getAqi(for value: Int) -> Aqi {
		let aqi: Aqi
		switch value {
		case 0...50:
			aqi = .good
		case 51...100:
			aqi = .moderate
		case 101...150:
			aqi = .sensitive
		case 151...200:
			aqi = .unhealthy
		case 201...300:
			aqi = .veryUnhealthy
		case 301...500:
			aqi = .hazardous
		default:
			fatalError("Invalid int value")
		}
		return aqi
	}
}

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
			return .magenta
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

// Default of 0 is Client
enum MetricsTypes: Int, CaseIterable, Identifiable {

	case device = 0
	case environment = 1
	case power = 2
	case airQuality = 3
	case stats = 4
	case host = 5

	var id: Int { self.rawValue }
	var name: String {
		switch self {
		case .device:
			return "Device Metrics"
		case .environment:
			return "Environment Metrics"
		case .power:
			return "Power Metrics"
		case .airQuality:
			return "Air Quality Metrics"
		case .stats:
			return "Stats"
		case .host:
			return "Host Metrics"
		}
	}
}
