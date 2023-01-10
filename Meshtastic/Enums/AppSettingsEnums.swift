//
//  AppSettingsEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/30/22.
//

import Foundation

enum KeyboardType: Int, CaseIterable, Identifiable {

	case defaultKeyboard = 0
	case asciiCapable = 1
	case twitter = 9
	case emailAddress = 7
	case numbersAndPunctuation = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .defaultKeyboard:
				return NSLocalizedString("default", comment: "Default Keyboard")
			case .asciiCapable:
				return NSLocalizedString("ascii.capable", comment: "ASCII Capable Keyboard")
			case .twitter:
				return NSLocalizedString("twitter", comment: "Twitter Keyboard")
			case .emailAddress:
				return NSLocalizedString("email.address", comment: "Email Address Keyboard")
			case .numbersAndPunctuation:
				return NSLocalizedString("numbers.punctuation", comment: "Numbers and Punctuation Keyboard")
			}
		}
	}
}

enum MeshMapType: String, CaseIterable, Identifiable {

	case satellite = "satellite"
	case hybrid = "hybrid"
	case standard = "standard"

	var id: String { self.rawValue }

	var description: String {
		get {
			switch self {
			case .satellite:
				return NSLocalizedString("satellite", comment: "Satellite Map Type")
			case .standard:
				return NSLocalizedString("standard", comment: "Standard Map Type")
			case .hybrid:
				return NSLocalizedString("hybrid", comment: "Hybrid Map Type")
			}
		}
	}
}

enum LocationUpdateInterval: Int, CaseIterable, Identifiable {

	case fiveSeconds = 5
	case tenSeconds = 10
	case fifteenSeconds = 15
	case thirtySeconds = 30
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .fiveSeconds:
				return NSLocalizedString("interval.five.seconds", comment: "Five Seconds")
			case .tenSeconds:
				return NSLocalizedString("interval.ten.seconds", comment: "Ten Seconds")
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
			}
		}
	}
}
