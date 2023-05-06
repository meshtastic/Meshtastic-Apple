//
//  AppSettingsEnums.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 12/30/22.
//

import Foundation
import MapKit

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
			return "standard".localized
		case .mutedStandard:
			return "standard.muted".localized
		case .hybrid:
			return "hybrid".localized
		case .hybridFlyover:
			return "hybrid.flyover".localized
		case .satellite:
			return "satellite".localized
		case .satelliteFlyover:
			return "satellite.flyover".localized
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
			return "map.usertrackingmode.none".localized
		case .follow:
			return "map.usertrackingmode.follow".localized
		case .followWithHeading:
			return "map.usertrackingmode.followwithheading".localized
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
	case fortyFiveSeconds = 45
	case oneMinute = 60
	case fiveMinutes = 300
	case tenMinutes = 600
	case fifteenMinutes = 900
	
	var id: Int { self.rawValue }
	var description: String {
		switch self {
		case .fiveSeconds:
			return "interval.five.seconds".localized
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
		case .fiveMinutes:
			return "interval.five.minutes".localized
		case .tenMinutes:
			return "interval.ten.minutes".localized
		case .fifteenMinutes:
			return "interval.fifteen.minutes".localized
		}
	}
}

enum MapLayer: String, CaseIterable, Equatable {
	case standard
	case hybrid
	case satellite
	case offline
	var localized: String { self.rawValue.localized }
	var zoomRange: [Int] {
		switch self {
		case .standard:
			return [Int](0...24)
		case .hybrid:
			return [Int](0...24)
		case .satellite:
			return [Int](0...24)
		case .offline:
			return [Int](0...17)
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
}
