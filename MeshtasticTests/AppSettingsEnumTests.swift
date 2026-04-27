import Foundation
import MapKit
import Testing

@testable import Meshtastic

// MARK: - MeshMapTypes

@Suite("MeshMapTypes")
struct MeshMapTypesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mapType in MeshMapTypes.allCases {
			#expect(!mapType.description.isEmpty)
		}
	}

	@Test func allCases_haveMKMapTypeValue() {
		for mapType in MeshMapTypes.allCases {
			_ = mapType.MKMapTypeValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(MeshMapTypes.allCases.count == 6)
	}
}

// MARK: - MeshMapDistances

@Suite("MeshMapDistances")
struct MeshMapDistancesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for distance in MeshMapDistances.allCases {
			#expect(!distance.description.isEmpty)
		}
	}

	@Test func allCases_havePositiveRawValue() {
		for distance in MeshMapDistances.allCases {
			#expect(distance.rawValue > 0)
		}
	}

	@Test func totalCaseCount() {
		#expect(MeshMapDistances.allCases.count == 11)
	}
}

// MARK: - UserTrackingModes

@Suite("UserTrackingModes")
struct UserTrackingModesTests {

	@Test func allCases_haveNonEmptyDescription() {
		for mode in UserTrackingModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyIcon() {
		for mode in UserTrackingModes.allCases {
			#expect(!mode.icon.isEmpty)
		}
	}

	@Test func allCases_haveMKUserTrackingModeValue() {
		for mode in UserTrackingModes.allCases {
			_ = mode.MKUserTrackingModeValue()
		}
	}

	@Test func totalCaseCount() {
		#expect(UserTrackingModes.allCases.count == 3)
	}
}

// MARK: - LocationUpdateInterval

@Suite("LocationUpdateInterval")
struct LocationUpdateIntervalTests {

	@Test func allCases_haveNonEmptyDescription() {
		for interval in LocationUpdateInterval.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(LocationUpdateInterval.allCases.count == 8)
	}

	@Test func tenSeconds_hasCorrectRawValue() {
		#expect(LocationUpdateInterval.tenSeconds.rawValue == 10)
	}

	@Test func fifteenMinutes_hasCorrectRawValue() {
		#expect(LocationUpdateInterval.fifteenMinutes.rawValue == 900)
	}
}

// MARK: - MapLayer

@Suite("MapLayer")
struct MapLayerTests {

	@Test func allCases_haveNonEmptyLocalized() {
		for layer in MapLayer.allCases {
			#expect(!layer.localized.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(MapLayer.allCases.count == 4)
	}

	@Test func equatable_sameValuesAreEqual() {
		#expect(MapLayer.standard == MapLayer.standard)
	}

	@Test func equatable_differentValuesAreNotEqual() {
		#expect(MapLayer.standard != MapLayer.satellite)
	}
}

// MARK: - MapTileServer

@Suite("MapTileServer")
struct MapTileServerTests {

	@Test func allCases_haveNonEmptyDescription() {
		for server in MapTileServer.allCases {
			#expect(!server.description.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyAttribution() {
		for server in MapTileServer.allCases {
			#expect(!server.attribution.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyTileUrl() {
		for server in MapTileServer.allCases {
			#expect(!server.tileUrl.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyZoomRange() {
		for server in MapTileServer.allCases {
			#expect(!server.zoomRange.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(MapTileServer.allCases.count == 12)
	}

	@Test func identifiable_idMatchesRawValue() {
		for server in MapTileServer.allCases {
			#expect(server.id == server.rawValue)
		}
	}
}

// MARK: - OverlayType

@Suite("OverlayType")
struct OverlayTypeTests {

	@Test func allCases_haveNonEmptyLocalized() {
		for overlay in OverlayType.allCases {
			#expect(!overlay.localized.isEmpty)
		}
	}

	@Test func totalCaseCount() {
		#expect(OverlayType.allCases.count == 2)
	}
}

// MARK: - MapOverlayServer

@Suite("MapOverlayServer")
struct MapOverlayServerTests {

	@Test func allCases_haveNonEmptyDescription() {
		for server in MapOverlayServer.allCases {
			#expect(!server.description.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyAttribution() {
		for server in MapOverlayServer.allCases {
			#expect(!server.attribution.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyTileUrl() {
		for server in MapOverlayServer.allCases {
			#expect(!server.tileUrl.isEmpty)
		}
	}

	@Test func allCases_haveNonEmptyZoomRange() {
		for server in MapOverlayServer.allCases {
			#expect(!server.zoomRange.isEmpty)
		}
	}

	@Test func allCases_haveOverlayType() {
		for server in MapOverlayServer.allCases {
			#expect(server.overlayType == .tileServer)
		}
	}

	@Test func totalCaseCount() {
		#expect(MapOverlayServer.allCases.count == 9)
	}
}
