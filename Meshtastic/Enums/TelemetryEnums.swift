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
			return "Good"
		case .moderate:
			return "Moderate"
		case .sensitive:
			return "Unhealthy for Sensitive Groups"
		case .unhealthy:
			return "Unhealthy"
		case .veryUnhealthy:
			return "Very Unhealthy"
		case .hazardous:
			return "Hazardous"
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
