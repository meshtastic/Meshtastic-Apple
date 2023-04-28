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

enum MeshMapTypes: Int, CaseIterable, Identifiable {
	
	case standard = 0
	case mutedStandard = 5
	case hybrid = 2
	case hybridFlyover = 4
	case satellite = 1
	case satelliteFlyover = 3
	
	var id: Int { self.rawValue }
	
	var description: String {
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

enum UserTrackingModes: Int, CaseIterable, Identifiable {
	
	case none = 0
	case follow = 1
	case followWithHeading = 2
	
	var id: Int { self.rawValue }
	
	var description: String {
		switch self {
		case .none:
			return NSLocalizedString("map.usertrackingmode.none", comment: "None")
		case .follow:
			return NSLocalizedString("map.usertrackingmode.follow", comment: "Follow")
		case .followWithHeading:
			return NSLocalizedString("map.usertrackingmode.followwithheading", comment: "Follow with Heading")
		}
	}
	var icon: String {
		switch self {
		case .none: return "location"
		case .follow: return "location.fill"
		case .followWithHeading: return "location.north.line.fill"
		}
	}
	func MKUserTrackingModeValue() -> MKUserTrackingMode {
		
		switch self {
		case .none:
			return MKUserTrackingMode.none
		case .follow:
			return MKUserTrackingMode.follow
		case .followWithHeading:
			return MKUserTrackingMode.followWithHeading
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
enum MapTileServerLinks: Int, CaseIterable, Identifiable {
	
	case none = 0
	case openStreetMaps = 1
	case wikimedia = 2
	case nationalMap = 3
	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .none:
			return "Please Select"
		case .wikimedia:
			return "Wikimedia"
		case .openStreetMaps:
			return "Open Street Maps"
		case .nationalMap:
			return "US National Map"
		}
	}
	var tileUrl: String {
		switch self {
		case .none:
			return ""
		case .wikimedia:
			return "https://maps.wikimedia.org/osm-intl/{z}/{x}/{y}.png"
		case .openStreetMaps:
			return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
		case .nationalMap:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}"
		}
	}
	var zoomRange: [Int] {
		switch self {
		case .none:
			return [Int](0...1)
		case .wikimedia:
			return [Int](0...24)
		case .openStreetMaps:
			return [Int](0...24)
		case .nationalMap:
			return [Int](0...24)
		}
	}
}
