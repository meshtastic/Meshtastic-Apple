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

enum MeshMapDistances: Double, CaseIterable, Identifiable {
	case twoMiles = 3218.69
	case fiveMiles = 8046.72
	case tenMiles = 16093.4
	case twentyFiveMiles = 40233.6
	case fiftyMiles = 80467.2
	case oneHundredMiles = 160934
	case twoHundredMiles = 321869
	case fiveHundredMiles = 804672
	case oneThousandMiles = 1609000
	case fifteenHundredMiles = 2414016
	case twentyFiveHundredMiles = 4023360
	case fiveThouandMiles = 8046720
	var id: Double { self.rawValue }
	var description: String {
		let distanceFormatter = MKDistanceFormatter()
		return String.localizedStringWithFormat("nodelist.filter.distance %@".localized, distanceFormatter.string(fromDistance: Double(self.rawValue)))
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

enum MapLayer: String, CaseIterable, Equatable, Decodable {
	case standard
	case hybrid
	case satellite
	case offline
	var localized: String { self.rawValue.localized }
}

enum MapTileServer: String, CaseIterable, Identifiable, Decodable {
	case openStreetMap
	case openStreetMapDE
	case openStreetMapFR
	case openCycleMap
	case openStreetMapHot
	case openTopoMap
	case usgsTopo
	case usgsImageryTopo
	case usgsImageryOnly
	case terrain
	case toner
	case watercolor
	var id: String { self.rawValue }
	var attribution: String {
		switch self {
		case .openStreetMap:
			return "Map and data © [OpenStreetMap](http://www.openstreetmap.org) and contributors, [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)"
		case .openStreetMapDE:
			return "[OpenStreetMap DE](https://openstreetmap.de) map and data © [OpenStreetMap](http://www.openstreetmap.org) and contributors, [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)"
		case .openStreetMapFR:
			return "[OpenStreetMap FR](https://www.openstreetmap.fr) map and data © [OpenStreetMap](http://www.openstreetmap.org) and contributors, [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)"
		case .openCycleMap:
			return "[OpenCycleMap](https://www.cyclosm.org) map and data © [OpenStreetMap](http://www.openstreetmap.org) and contributors, [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)"
		case .openTopoMap:
			return "[OpenTopoMap](https://opentopomap.org) map and data © [OpenStreetMap](http://www.openstreetmap.org) and contributors, [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)"
		case .openStreetMapHot:
			return "[OpenStreetMap FR](https://www.openstreetmap.fr) map and data © [OpenStreetMap](http://www.openstreetmap.org) and contributors, [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)"
		case .usgsTopo:
			return "[USGS](https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer) [National Map](http://nationalmap.gov/) topographic overlay."
		case .usgsImageryTopo:
			return "[USGS](https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer) [National Map](http://nationalmap.gov/) imagery and topographic overlay."
		case .usgsImageryOnly:
			return "[USGS](https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer) [National Map](http://nationalmap.gov/) imagery only overlay."
		case .terrain:
			return "[Map Tiles](http://maps.stamen.com/#terrain/) by [Stamen Design](https://stamen.com), under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Data © [OpenStreetMap](http://www.openstreetmap.org) contributors under [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)."
		case .toner:
			return "[Map Tiles](http://maps.stamen.com/#toner/) by [Stamen Design](https://stamen.com), under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Data © [OpenStreetMap](http://www.openstreetmap.org) contributors under [CC-BY-SA](http://creativecommons.org/licenses/by-sa/2.0/)."
		case .watercolor:
			return "Cooper Hewitt, Smithsonian Design Museum's [Watercolor Maptiles](https://watercolormaps.collection.cooperhewitt.org/) is a open-source mapping tool created by Stamen Design and built on [OpenStreetMap](http://www.openstreetmap.org) data."
		}
	}
	var description: String {
		switch self {
		case .openStreetMap:
			return "Open Street Map"
		case .openStreetMapDE:
			return "Open Street Map DE"
		case .openStreetMapFR:
			return "Open Street Map FR"
		case .openCycleMap:
			return "Open Cycle Map"
		case .openStreetMapHot:
			return "Humanitarian (OSM)"
		case.openTopoMap:
			return "Open Topo Map"
		case .usgsTopo:
			return "USGS Topographic"
		case .usgsImageryTopo:
			return "USGS Topo Imagery"
		case .usgsImageryOnly:
			return "USGS Imagery Only"
		case .terrain:
			return "Terrain"
		case .toner:
			return "Toner"
		case .watercolor:
			return "Watercolor Maptiles"
		}
	}
	var tileUrl: String {
		switch self {
		case .openStreetMap:
			return "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
		case .openStreetMapDE:
			return "https://tile.openstreetmap.de/{z}/{x}/{y}.png"
		case .openStreetMapFR:
			return "https://a.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png"
		case .openCycleMap:
			return "https://c.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png"
		case .openStreetMapHot:
			return "https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png"
		case .openTopoMap:
			return "https://a.tile.opentopomap.org/{z}/{x}/{y}.png"
		case .usgsTopo:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSTopo/MapServer/tile/{z}/{y}/{x}"
		case .usgsImageryTopo:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}"
		case .usgsImageryOnly:
			return "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}"
		case .terrain:
			return "https://stamen-tiles-d.a.ssl.fastly.net/terrain/{z}/{x}/{y}.png"
		case .toner:
			return "https://stamen-tiles.a.ssl.fastly.net/toner/{z}/{x}/{y}.png"
		case .watercolor:
			return "https://watercolormaps.collection.cooperhewitt.org/tile/watercolor/{z}/{x}/{y}.jpg"

		}
	}
	var zoomRange: [Int] {
		switch self {
		case .openStreetMap:
			return [Int](0...18)
		case .openStreetMapDE:
			return [Int](0...18)
		case .openStreetMapFR:
			return [Int](0...18)
		case .openCycleMap:
			return [Int](0...18)
		case .openTopoMap:
			return [Int](0...18)
		case .openStreetMapHot:
			return [Int](0...18)
		case .usgsTopo:
			return [Int](6...16)
		case .usgsImageryTopo:
			return [Int](6...16)
		case .usgsImageryOnly:
			return [Int](6...16)
		case .terrain:
			return [Int](0...15)
		case .toner:
			return [Int](0...18)
		case .watercolor:
			return [Int](0...18)
		}
	}
}

enum OverlayType: String, CaseIterable, Equatable {
	case tileServer
	case geoJson
	var localized: String { self.rawValue.localized }
}

enum MapOverlayServer: String, CaseIterable, Identifiable, Decodable {
	case baseReReflectivityCurrent
	case baseReReflectivityOneHourAgo
	case echoTopsEetCurrent
	case echoTopsEetOneHourAgo
	case q2OneHourPrecipitation
	case q2TwentyFourHourPrecipitation
	case q2FortyEightHourPrecipitation
	case q2SeventyTwoHourPrecipitation
	case mrmsHybridScanReflectivityComposite

	var id: String { self.rawValue }
	var overlayType: OverlayType {
		switch self {
		case .baseReReflectivityCurrent:
			return .tileServer
		case .baseReReflectivityOneHourAgo:
			return .tileServer
		case .echoTopsEetCurrent:
			return .tileServer
		case .echoTopsEetOneHourAgo:
			return .tileServer
		case .q2OneHourPrecipitation:
			return .tileServer
		case .q2TwentyFourHourPrecipitation:
			return .tileServer
		case .q2FortyEightHourPrecipitation:
			return .tileServer
		case .q2SeventyTwoHourPrecipitation:
			return .tileServer
		case .mrmsHybridScanReflectivityComposite:
			return .tileServer
		}
	}
	var attribution: String {
		return "NEXRAD Weather tiles from Iowa State University Environmental Mesonet [OGC Web Services](https://mesonet.agron.iastate.edu/ogc/)."
	}
	var description: String {
		switch self {
		case .baseReReflectivityCurrent:
			return "Base Reflectivity current"
		case .baseReReflectivityOneHourAgo:
			return "Base Reflectivity one hour ago"
		case .echoTopsEetCurrent:
			return "Echo Tops EET current"
		case .echoTopsEetOneHourAgo:
			return "Echo Tops EET one hour ago"
		case .q2OneHourPrecipitation:
			return "Q2 1 Hour Precipitation"
		case .q2TwentyFourHourPrecipitation:
			return "Q2 24 Hour Precipitation"
		case .q2FortyEightHourPrecipitation:
			return "Q2 48 Hour Precipitation"
		case .q2SeventyTwoHourPrecipitation:
			return "Q2 72 Hour Precipitation"
		case .mrmsHybridScanReflectivityComposite:
			return "MRMS Hybrid-Scan Reflectivity Composite"
		}
	}
	var tileUrl: String {
		switch self {
		case .baseReReflectivityCurrent:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}"
		case .baseReReflectivityOneHourAgo:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913-m55m/{z}/{x}/{y}"
		case .echoTopsEetCurrent:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-eet-900913/{z}/{x}/{y}"
		case .echoTopsEetOneHourAgo:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-eet-900913-m55m/{z}/{x}/{y}"
		case .q2OneHourPrecipitation:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/q2-n1p-900913/{z}/{x}/{y}"
		case .q2TwentyFourHourPrecipitation:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/q2-p24h-900913/{z}/{x}/{y}"
		case .q2FortyEightHourPrecipitation:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/q2-p48h-900913/{z}/{x}/{y}"
		case .q2SeventyTwoHourPrecipitation:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/q2-p72h-900913/{z}/{x}/{y}"
		case .mrmsHybridScanReflectivityComposite:
			return "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/q2-hsr-900913/{z}/{x}/{y}"
		}
	}
	var zoomRange: [Int] {
		switch self {
		case .baseReReflectivityCurrent:
			return [Int](0...18)
		case .baseReReflectivityOneHourAgo:
			return [Int](0...18)
		case .echoTopsEetCurrent:
			return [Int](0...18)
		case .echoTopsEetOneHourAgo:
			return [Int](0...18)
		case .q2OneHourPrecipitation:
			return [Int](0...18)
		case .q2TwentyFourHourPrecipitation:
			return [Int](0...18)
		case .q2FortyEightHourPrecipitation:
			return [Int](0...18)
		case .q2SeventyTwoHourPrecipitation:
			return [Int](0...18)
		case .mrmsHybridScanReflectivityComposite:
			return [Int](0...18)
		}
	}
}
