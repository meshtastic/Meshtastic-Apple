//
//  UpdateIntervals.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/30/22.
//

import Foundation

enum NagIntervals: Int, CaseIterable, Identifiable {

	case unset = 0
	case oneSecond = 1
	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .unset:
			return NSLocalizedString("unset", comment: "No comment provided")
		case .oneSecond:
			return NSLocalizedString("interval.one.second", comment: "No comment provided")
		case .fiveSeconds:
			return NSLocalizedString("interval.five.seconds", comment: "No comment provided")
		case .tenSeconds:
			return NSLocalizedString("interval.ten.seconds", comment: "No comment provided")
		case .fifteenSeconds:
			return NSLocalizedString("interval.fifteen.seconds", comment: "No comment provided")
		case .thirtySeconds:
			return NSLocalizedString("interval.thirty.seconds", comment: "No comment provided")
		case .oneMinute:
			return NSLocalizedString("interval.one.minute", comment: "No comment provided")
		case .fiveMinutes:
			return NSLocalizedString("interval.five.minutes", comment: "No comment provided")
		}
	}
}

enum OutputIntervals: Int, CaseIterable, Identifiable {

	case unset = 0
	case oneSecond = 1000
	case twoSeconds = 2000
	case threeSeconds = 3000
	case fourSeconds = 4000
	case fiveSeconds = 5000
	case tenSeconds = 10000
	case fifteenSeconds = 15000
	case thirtySeconds = 30000
	case oneMinute = 60000

	var id: Int { self.rawValue }
	var description: String {

		switch self {
		case .unset:
			return NSLocalizedString("unset", comment: "No comment provided")
		case .oneSecond:
			return NSLocalizedString("interval.one.second", comment: "No comment provided")
		case .twoSeconds:
			return NSLocalizedString("interval.two.seconds", comment: "No comment provided")
		case .threeSeconds:
			return NSLocalizedString("interval.three.seconds", comment: "No comment provided")
		case .fourSeconds:
			return NSLocalizedString("interval.four.seconds", comment: "No comment provided")
		case .fiveSeconds:
			return NSLocalizedString("interval.five.seconds", comment: "No comment provided")
		case .tenSeconds:
			return NSLocalizedString("interval.ten.seconds", comment: "No comment provided")
		case .fifteenSeconds:
			return NSLocalizedString("interval.fifteen.seconds", comment: "No comment provided")
		case .thirtySeconds:
			return NSLocalizedString("interval.thirty.seconds", comment: "No comment provided")
		case .oneMinute:
			return NSLocalizedString("interval.one.minute", comment: "No comment provided")
		}
	}
}

// Default of 0 is off
enum SenderIntervals: Int, CaseIterable, Identifiable {

	case off = 0
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case fortyFiveSeconds = 45
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	case thirtyMinutes = 1800
	case oneHour = 3600

	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .off:
			return NSLocalizedString("off", comment: "No comment provided")
		case .fifteenSeconds:
			return NSLocalizedString("interval.fifteen.seconds", comment: "No comment provided")
		case .thirtySeconds:
			return NSLocalizedString("interval.thirty.seconds", comment: "No comment provided")
		case .fortyFiveSeconds:
			return NSLocalizedString("interval.fortyfive.seconds", comment: "No comment provided")
		case .oneMinute:
			return NSLocalizedString("interval.one.minute", comment: "No comment provided")
		case .fiveMinutes:
			return NSLocalizedString("interval.five.minutes", comment: "No comment provided")
		case .tenMinutes:
			return NSLocalizedString("interval.ten.minutes", comment: "No comment provided")
		case .fifteenMinutes:
			return NSLocalizedString("interval.fifteen.minutes", comment: "No comment provided")
		case .thirtyMinutes:
			return NSLocalizedString("interval.thirty.minutes", comment: "No comment provided")
		case .oneHour:
			return NSLocalizedString("interval.one.hour", comment: "No comment provided")
		}
	}
}

enum UpdateIntervals: Int, CaseIterable, Identifiable {

	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case fortyFiveSeconds = 45
	case oneMinute = 60
	case twoMinutes = 120
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

		switch self {
		case .tenSeconds:
			return NSLocalizedString("interval.ten.seconds", comment: "No comment provided")
		case .fifteenSeconds:
			return NSLocalizedString("interval.fifteen.seconds", comment: "No comment provided")
		case .thirtySeconds:
			return NSLocalizedString("interval.thirty.seconds", comment: "No comment provided")
		case .fortyFiveSeconds:
			return NSLocalizedString("interval.fortyfive.seconds", comment: "No comment provided")
		case .oneMinute:
			return NSLocalizedString("interval.one.minute", comment: "No comment provided")
		case .twoMinutes:
			return NSLocalizedString("interval.two.minutes", comment: "No comment provided")
		case .fiveMinutes:
			return NSLocalizedString("interval.five.minutes", comment: "No comment provided")
		case .tenMinutes:
			return NSLocalizedString("interval.ten.minutes", comment: "No comment provided")
		case .fifteenMinutes:
			return NSLocalizedString("interval.fifteen.minutes", comment: "No comment provided")
		case .thirtyMinutes:
			return NSLocalizedString("interval.thirty.minutes", comment: "No comment provided")
		case .oneHour:
			return NSLocalizedString("interval.one.hour", comment: "No comment provided")
		case .twoHours:
			return NSLocalizedString("interval.two.hours", comment: "No comment provided")
		case .threeHours:
			return NSLocalizedString("interval.three.hours", comment: "No comment provided")
		case .fourHours:
			return NSLocalizedString("interval.four.hours", comment: "No comment provided")
		case .fiveHours:
			return NSLocalizedString("interval.five.hours", comment: "No comment provided")
		case .sixHours:
			return NSLocalizedString("interval.six.hours", comment: "No comment provided")
		case .twelveHours:
			return NSLocalizedString("interval.twelve.hours", comment: "No comment provided")
		case .eighteenHours:
			return NSLocalizedString("interval.eighteen.hours", comment: "No comment provided")
		case .twentyFourHours:
			return NSLocalizedString("interval.twentyfour.hours", comment: "No comment provided")
		case .thirtySixHours:
			return NSLocalizedString("interval.thirtysix.hours", comment: "No comment provided")
		case .fortyeightHours:
			return NSLocalizedString("interval.fortyeight.hours", comment: "No comment provided")
		case .seventyTwoHours:
			return NSLocalizedString("interval.seventytwo.hours", comment: "No comment provided")
		}
	}
}

typealias PowerIntervals = UpdateIntervals
