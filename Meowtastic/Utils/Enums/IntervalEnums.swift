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
			return "unset".localized
		case .oneSecond:
			return "interval.one.second".localized
		case .fiveSeconds:
			return "interval.five.seconds".localized
		case .tenSeconds:
			return "interval.ten.seconds".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
		case .fiveMinutes:
			return "interval.five.minutes".localized
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
			return "unset".localized
		case .oneSecond:
			return "interval.one.second".localized
		case .twoSeconds:
			return "interval.two.seconds".localized
		case .threeSeconds:
			return "interval.three.seconds".localized
		case .fourSeconds:
			return "interval.four.seconds".localized
		case .fiveSeconds:
			return "interval.five.seconds".localized
		case .tenSeconds:
			return "interval.ten.seconds".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
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
			return "off".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .fortyFiveSeconds:
			return "interval.fortyfive.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
		case .fiveMinutes:
			return "interval.five.minutes".localized
		case .tenMinutes:
			return "interval.ten.minutes".localized
		case .fifteenMinutes:
			return "interval.fifteen.minutes".localized
		case .thirtyMinutes:
			return "interval.thirty.minutes".localized
		case .oneHour:
			return "interval.one.hour".localized
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
			return "interval.ten.seconds".localized
		case .fifteenSeconds:
			return "interval.fifteen.seconds".localized
		case .thirtySeconds:
			return "interval.thirty.seconds".localized
		case .fortyFiveSeconds:
			return "interval.fortyfive.seconds".localized
		case .oneMinute:
			return "interval.one.minute".localized
		case .twoMinutes:
			return "interval.two.minutes".localized
		case .fiveMinutes:
			return "interval.five.minutes".localized
		case .tenMinutes:
			return "interval.ten.minutes".localized
		case .fifteenMinutes:
			return "interval.fifteen.minutes".localized
		case .thirtyMinutes:
			return "interval.thirty.minutes".localized
		case .oneHour:
			return "interval.one.hour".localized
		case .twoHours:
			return "interval.two.hours".localized
		case .threeHours:
			return "interval.three.hours".localized
		case .fourHours:
			return "interval.four.hours".localized
		case .fiveHours:
			return "interval.five.hours".localized
		case .sixHours:
			return "interval.six.hours".localized
		case .twelveHours:
			return "interval.twelve.hours".localized
		case .eighteenHours:
			return "interval.eighteen.hours".localized
		case .twentyFourHours:
			return "interval.twentyfour.hours".localized
		case .thirtySixHours:
			return "interval.thirtysix.hours".localized
		case .fortyeightHours:
			return "interval.fortyeight.hours".localized
		case .seventyTwoHours:
			return "interval.seventytwo.hours".localized
		}
	}
}

typealias PowerIntervals = UpdateIntervals
