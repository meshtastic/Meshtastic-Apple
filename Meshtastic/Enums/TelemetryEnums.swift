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
			return "telemetry.good".localized
		case .moderate:
			return "telemetry.moderate".localized
		case .sensitive:
			return "telemetry.sensitive".localized
		case .unhealthy:
			return "telementry.unhealthy".localized
		case .veryUnhealthy:
			return "telementry.veryUnhealthy".localized
		case .hazardous:
			return "telementry.hazardous".localized
		}
	}
	var color: Color {
		switch self {
		case .good:
			return .green
		case .moderate:
			return .yellow
		case .sensitive:
			return .orange
		case .unhealthy:
			return .red
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

enum Iaq: Int, CaseIterable, Identifiable {
	case excellent = 0
	case good = 1
	case lightlyPolluted = 2
	case moderatelyPolluted = 3
	case heavilyPolluted = 4
	case severelyPolluted = 5
	case extremelyPolluted = 6

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .excellent:
			return "Excellent"
		case .good:
			return "Good"
		case .lightlyPolluted:
			return "Lightly Polluted"
		case .moderatelyPolluted:
			return "Moderately Polluted"
		case .heavilyPolluted:
			return "Heavily Polluted"
		case .severelyPolluted:
			return "Severely Polluted"
		case .extremelyPolluted:
			return "Extremely Polluted"
		}
	}
	var color: Color {
		switch self {
		case .excellent:
			return .green
		case .good:
			return .mint
		case .lightlyPolluted:
			return .yellow
		case .moderatelyPolluted:
			return .orange
		case .heavilyPolluted:
			return .red
		case .severelyPolluted:
			return .magenta
		case .extremelyPolluted:
			return .brown
		}
	}

	var range: Range<Int> {
		switch self {
		case .excellent:
			return Range(0...50)
		case .good:
			return Range(51...100)
		case .lightlyPolluted:
			return Range(101...150)
		case .moderatelyPolluted:
			return Range(151...200)
		case .heavilyPolluted:
			return Range(201...250)
		case .severelyPolluted:
			return Range(251...350)
		case .extremelyPolluted:
			return Range(351...500)
		}
	}
	static func getIaq(for value: Int) -> Iaq {
		let iaq: Iaq
		switch value {
		case 0...50:
			iaq = .excellent
		case 51...100:
			iaq = .good
		case 101...150:
			iaq = .lightlyPolluted
		case 151...200:
			iaq = .moderatelyPolluted
		case 201...250:
			iaq = .heavilyPolluted
		case 251...350:
			iaq = .severelyPolluted
		case 351...:
			iaq = .extremelyPolluted
		default:
			fatalError("Invalid int value")
		}
		return iaq
	}
}

// Default of 0 is Client
enum MetricsTypes: Int, CaseIterable, Identifiable {

	case device = 0
	case environment = 1
	case power = 2
	case airQuality = 3
	case stats = 4

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
		}
	}
}
