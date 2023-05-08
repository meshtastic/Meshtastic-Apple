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
}

enum MapTileServerLinks: String, CaseIterable, Identifiable {
	
	case openStreetMaps
	case usgsTopo
	case usgsImageryTopo
	case usgsImageryOnly
	case watercolor
	var id: String { self.rawValue }
	var attribution: String {
		switch self {
			
		case .openStreetMaps:
			return "OpenStreetMap is a map of the world, created by people like you and free to use under an open license. &copy; [OpenStreetMap](http://osm.org/copyright) contributors"
		case .usgsTopo:
			return "[USGS Topo](https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer) is a tile cache base map service that combines the most current data in The National Map (TNM), and other public-domain data, into a multi-scale topographic reference map."
		case .usgsImageryTopo:
			return "[USGS Imagery Topo](https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer) is a tile cache base map of orthoimagery in The National Map and US Topo vector data."
		case .usgsImageryOnly:
			return "[USGS Imagery Only](https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer) is a tile cache base map service of orthoimagery in The National Map."
		case .watercolor:
			return "Cooper Hewitt, Smithsonian Design Museum's [Watercolor Maptiles](https://watercolormaps.collection.cooperhewitt.org/) is a open-source mapping tool created by Stamen Design and built on OpenStreetMap data."
		}
	}
	var description: String {
		switch self {
		case .openStreetMaps:
			return "Open Street Maps"
		case .usgsTopo:
			return "USGS Topographic"
		case .usgsImageryTopo:
			return "USGS Topo Imagery"
		case .usgsImageryOnly:
			return "USGS Imagery Only"
		case .watercolor:
			return "Watercolor Maptiles"
		}
	}
	var tileUrl: String {
		switch self {
		case .openStreetMaps:
			return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
		case .usgsTopo:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"
		case .usgsImageryTopo:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}"
		case .usgsImageryOnly:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}"
		case .watercolor:
			return "https://watercolormaps.collection.cooperhewitt.org/tile/watercolor/{z}/{x}/{y}.jpg"

		}
	}
	var zoomRange: [Int] {
		switch self {
		case .openStreetMaps:
			return [Int](0...17)
		case .usgsTopo:
			return [Int](0...17)
		case .usgsImageryTopo:
			return [Int](0...17)
		case .usgsImageryOnly:
			return [Int](0...17)
		case .watercolor:
			return [Int](0...17)
		}
	}
}
