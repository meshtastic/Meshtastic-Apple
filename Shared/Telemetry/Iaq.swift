//
//  Iaq.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//

import SwiftUI

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
			return Color(uiColor: .systemGreen)
		case .good:
			return .mint
		case .lightlyPolluted:
			return .yellow
		case .moderatelyPolluted:
			return Color(uiColor: .systemOrange)
		case .heavilyPolluted:
			return Color(uiColor: .systemRed)
		case .severelyPolluted:
			// Color.magenta in the app, which the widget extension doesn't build.
			return Color(red: 0.50, green: 0.00, blue: 0.00)
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
