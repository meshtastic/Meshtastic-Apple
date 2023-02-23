//
//  AppSettingsEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/30/22.
//

import Foundation
import MapKit

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

enum CenteringMode: Int, CaseIterable, Identifiable {

	case allAnnotations = 0
	case allPositions = 1
	case clientGps = 2

	var id: Int { self.rawValue }
	var description: String {
		get {
			switch self {
			case .allAnnotations:
				return "All Annotations"// NSLocalizedString("default", comment: "Default Keyboard")
			case .allPositions:
				return "All Node Postions"// NSLocalizedString("ascii.capable", comment: "ASCII Capable Keyboard")
			case .clientGps:
				return "Client GPS"//NSLocalizedString("email.address", comment: "Email Address Keyboard")
			}
		}
	}
}

enum MeshMapType: String, CaseIterable, Identifiable {

	case standard = "standard"  
	case mutedStandard = "mutedStandard"
	case hybrid = "hybrid"
	case hybridFlyover = "hybridFlyover"
	case satellite = "satellite"
	case satelliteFlyover = "satelliteFlyover"
	

	var id: String { self.rawValue }

	var description: String {
		get {
			switch self {
			case .standard:
				return NSLocalizedString("standard", comment: "Standard")
			case .mutedStandard:
				return NSLocalizedString("standard.muted", comment: "Standard Muted")
			case .hybrid:
				return NSLocalizedString("hybrid", comment: "Hybrid")
			case .hybridFlyover:
				return NSLocalizedString("hybrid.flyover", comment: "Hybrid Flyover")
			case .satellite:
				return NSLocalizedString("satellite", comment: "Satellite")
			case .satelliteFlyover:
				return NSLocalizedString("satellite.flyover", comment: "Satellite Flyover")
			}
		}
	}
	func MKMapTypeValue() -> MKMapType {
		
		switch self {
		case .standard:
			return MKMapType.standard
		case .mutedStandard:
			return MKMapType.mutedStandard
		case .hybrid:
			return MKMapType.hybrid
		case .hybridFlyover:
			return MKMapType.hybridFlyover
		case .satellite:
			return MKMapType.satellite
		case .satelliteFlyover:
			return MKMapType.satelliteFlyover
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
