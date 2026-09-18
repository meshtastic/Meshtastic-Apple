//
//  UpdateIntervals.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 12/30/22.
//

import Foundation

enum IntervalConfiguration: CaseIterable {
	case all
	case broadcastShort
	case broadcastMedium
	case broadcastLong
	case detectionSensorMinimum
	case detectionSensorState
	case meshBeacon
	case nagTimeout
	case neighborInfo
	case paxCounter
	case rangeTestSender
	case smartBroadcastMinimum
	case trafficPositionDedup
	case trafficRateLimitWindow

	var allowedCases: [FixedUpdateIntervals] {
		switch self {
		case .all:
			return FixedUpdateIntervals.allCases // Show all cases
		case .broadcastShort:
			return [.unset, .thirtyMinutes, .oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours, .never]
		case .broadcastMedium:
			return [.oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours, .never]
		case .broadcastLong:
			return [.threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours, .never]
		case .detectionSensorMinimum:
			return [.unset, .fifteenSeconds, .thirtySeconds, .oneMinute, .twoMinutes, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours]
		case .detectionSensorState:
			return [.unset, .fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours]
		case .meshBeacon:
			// Firmware minimum is one hour; a beacon with broadcast enabled always has an
			// interval, so there is no Never row.
			return [.oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours]
		case .nagTimeout:
			return [.unset, .oneSecond, .fiveSeconds, .tenSeconds, .fifteenSeconds, .thirtySeconds, .oneMinute]
		case .neighborInfo:
			return [.fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours]
		case .paxCounter:
			return [.fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .eighteenHours, .twentyFourHours, .thirtySixHours, .fortyeightHours, .seventyTwoHours]
		case .rangeTestSender:
			return [.unset, .fifteenSeconds, .thirtySeconds, .fortyFiveSeconds, .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour]
		case .smartBroadcastMinimum:
			return [.fifteenSeconds, .thirtySeconds, .fortyFiveSeconds, .oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour]
		case .trafficPositionDedup:
			// Firmware's defaults run long: 5 hours between identical positions, 1 hour for
			// trackers, 15 minutes for lost-and-found. No zero row — the feature toggle clears
			// the value instead.
			return [.oneMinute, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour, .twoHours, .threeHours, .fourHours, .fiveHours, .sixHours, .twelveHours, .twentyFourHours]
		case .trafficRateLimitWindow:
			// The accounting window packets are counted over, so it stays short. No zero row —
			// firmware needs both the window and the packet count non-zero.
			return [.tenSeconds, .fifteenSeconds, .thirtySeconds, .oneMinute, .twoMinutes, .fiveMinutes, .tenMinutes, .fifteenMinutes, .thirtyMinutes, .oneHour]
		}
	}
}

enum FixedUpdateIntervals: Int, CaseIterable, Hashable {

	case unset = 0
	case oneSecond = 1
	case fiveSeconds = 5
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
	case never = 2147483647 // Int.max
}

struct UpdateInterval: Hashable, Identifiable {
	
	enum IntervalType: Hashable {
		case fixed(FixedUpdateIntervals)
		case manual(Int)
	}
	
	let type: IntervalType

	var id: String {
		switch type {
		case .fixed(let fixedCase):
			return "fixed_\(fixedCase.rawValue)"
		case .manual(let value):
			return "manual_\(value)"
		}
	}
	
	var intValue: Int {
		switch type {
		case .fixed(let fixedCase):
			return fixedCase.rawValue
		case .manual(let value):
			return value
		}
	}
	
	var description: String {
		switch type {
		case .fixed(let fixedCase):
			switch fixedCase {
			case .unset:
				return String(localized: "Unset", comment: "UpdateInterval.description")
			case .oneSecond:
				return String(localized: "One Second", comment: "UpdateInterval.description")
			case .fiveSeconds:
				return String(localized: "Five Seconds", comment: "UpdateInterval.description")
			case .tenSeconds:
				return String(localized: "Ten Seconds", comment: "UpdateInterval.description")
			case .fifteenSeconds:
				return String(localized: "Fifteen Seconds", comment: "UpdateInterval.description")
			case .thirtySeconds:
				return String(localized: "Thirty Seconds", comment: "UpdateInterval.description")
			case .fortyFiveSeconds:
				return String(localized: "Forty Five Seconds", comment: "UpdateInterval.description")
			case .oneMinute:
				return String(localized: "One Minute", comment: "UpdateInterval.description")
			case .twoMinutes:
				return String(localized: "Two Minutes", comment: "UpdateInterval.description")
			case .fiveMinutes:
				return String(localized: "Five Minutes", comment: "UpdateInterval.description")
			case .tenMinutes:
				return String(localized: "Ten Minutes", comment: "UpdateInterval.description")
			case .fifteenMinutes:
				return String(localized: "Fifteen Minutes", comment: "UpdateInterval.description")
			case .thirtyMinutes:
				return String(localized: "Thirty Minutes", comment: "UpdateInterval.description")
			case .oneHour:
				return String(localized: "One Hour", comment: "UpdateInterval.description")
			case .twoHours:
				return String(localized: "Two Hours", comment: "UpdateInterval.description")
			case .threeHours:
				return String(localized: "Three Hours", comment: "UpdateInterval.description")
			case .fourHours:
				return String(localized: "Four Hours", comment: "UpdateInterval.description")
			case .fiveHours:
				return String(localized: "Five Hours", comment: "UpdateInterval.description")
			case .sixHours:
				return String(localized: "Six Hours", comment: "UpdateInterval.description")
			case .twelveHours:
				return String(localized: "Twelve Hours", comment: "UpdateInterval.description")
			case .eighteenHours:
				return String(localized: "Eighteen Hours", comment: "UpdateInterval.description")
			case .twentyFourHours:
				return String(localized: "Twenty Four Hours", comment: "UpdateInterval.description")
			case .thirtySixHours:
				return String(localized: "Thirty Six Hours", comment: "UpdateInterval.description")
			case .fortyeightHours:
				return String(localized: "Forty Eight Hours", comment: "UpdateInterval.description")
			case .seventyTwoHours:
				return String(localized: "Seventy Two Hours", comment: "UpdateInterval.description")
			case .never:
				return String(localized: "Never", comment: "UpdateInterval.description")
			}
		case .manual(let value):
			return String(localized: "Custom: \(value) Seconds", comment: "UpdateInterval.description")
		}
	}
	
	// MARK: - Initializer (For loading from Int)
	init(from int: Int) {
		if let fixedCase = FixedUpdateIntervals(rawValue: int) {
			self.type = .fixed(fixedCase)
		} else {
			self.type = .manual(int)
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
			return String(localized: "Unset", comment: "OutputIntervals.description")
		case .oneSecond:
			return String(localized: "One Second", comment: "OutputIntervals.description")
		case .twoSeconds:
			return String(localized: "Two Seconds", comment: "OutputIntervals.description")
		case .threeSeconds:
			return String(localized: "Three Seconds", comment: "OutputIntervals.description")
		case .fourSeconds:
			return String(localized: "Four Seconds", comment: "OutputIntervals.description")
		case .fiveSeconds:
			return String(localized: "Five Seconds", comment: "OutputIntervals.description")
		case .tenSeconds:
			return String(localized: "Ten Seconds", comment: "OutputIntervals.description")
		case .fifteenSeconds:
			return String(localized: "Fifteen Seconds", comment: "OutputIntervals.description")
		case .thirtySeconds:
			return String(localized: "Thirty Seconds", comment: "OutputIntervals.description")
		case .oneMinute:
			return String(localized: "One Minute", comment: "OutputIntervals.description")
		}
	}
}
