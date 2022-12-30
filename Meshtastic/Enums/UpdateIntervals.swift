//
//  UpdateIntervals.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/30/22.
//

import Foundation

enum UpdateIntervals: Int, CaseIterable, Identifiable {

	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600
	case twoHours = 7200
	case threeHours = 10800
	case fourHours = 14400
	case fiveHours = 18000
	case sixHours = 21600
	case twelveHours = 43200
	case eighteenHours = 64800
	case twentyFourHours = 86400
	case thirtySixHours = 129600
	case fortyeightHours = 172800
	case seventyTwoHours = 259200

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
				
			case .fifteenSeconds:
				return NSLocalizedString("interval.fifteen.seconds", comment: "Fifteen Seconds")
			case .thirtySeconds:
				return NSLocalizedString("interval.thirty.seconds", comment: "Thirty Seconds")
			case .oneMinute:
				return NSLocalizedString("interval.one.minute", comment: "One Minute")
			case .fiveMinutes:
				return NSLocalizedString("interval.five.minutes", comment: "Five Minutes")
			case .tenMinutes:
				return NSLocalizedString("interval.ten.minutes", comment: "Ten Minutes")
			case .fifteenMinutes:
				return NSLocalizedString("interval.fifteen.minutes", comment: "Fifteen Minutes")
			case .thirtyMinutes:
				return NSLocalizedString("interval.thirty.minutes", comment: "Thirty Minutes")
			case .oneHour:
				return NSLocalizedString("interval.one.hour", comment: "One Hour")
			case .twoHours:
				return NSLocalizedString("interval.two.hours", comment: "Two Hours")
			case .threeHours:
				return NSLocalizedString("interval.three.hours", comment: "Three Hours")
			case .fourHours:
				return NSLocalizedString("interval.four.hours", comment: "Four Hours")
			case .fiveHours:
				return NSLocalizedString("interval.five.hours", comment: "Five Hours")
			case .sixHours:
				return NSLocalizedString("interval.six.hours", comment: "Six Hours")
			case .twelveHours:
				return NSLocalizedString("interval.twelve.hours", comment: "Twelve Hours")
			case .eighteenHours:
				return NSLocalizedString("interval.eighteen.hours", comment: "Eighteen Hours")
			case .twentyFourHours:
				return NSLocalizedString("interval.twentyfour.hours", comment: "Twenty Four Hours")
			case .thirtySixHours:
				return NSLocalizedString("interval.thirtysix.hours", comment: "Thirty Six Hours")
			case .fortyeightHours:
				return NSLocalizedString("interval.fortyeight.hours", comment: "Forty Eight Hours")
			case .seventyTwoHours:
				return NSLocalizedString("interval.seventytwo.hours", comment: "Seventy Two Hours")
			}
		}
	}
}
