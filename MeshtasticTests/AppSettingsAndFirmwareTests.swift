// AppSettingsAndFirmwareTests.swift
// MeshtasticTests

import Testing
import Foundation
import MapKit
@testable import Meshtastic

// MARK: - MapTileServer Property Tests

@Suite("MapTileServer Properties")
struct MapTileServerPropertyTests {

	@Test func allCases_haveAttribution() {
		for server in MapTileServer.allCases {
			#expect(!server.attribution.isEmpty)
		}
	}

	@Test func allCases_haveTileUrl() {
		for server in MapTileServer.allCases {
			#expect(!server.tileUrl.isEmpty)
			#expect(server.tileUrl.contains("{z}"))
			#expect(server.tileUrl.contains("{x}"))
			#expect(server.tileUrl.contains("{y}"))
		}
	}

	@Test func allCases_haveZoomRange() {
		for server in MapTileServer.allCases {
			let range = server.zoomRange
			#expect(!range.isEmpty)
			#expect(range.first! >= 0)
			#expect(range.last! <= 18)
		}
	}

	@Test func allCases_haveId() {
		for server in MapTileServer.allCases {
			#expect(server.id == server.rawValue)
		}
	}

	@Test func specificDescriptions() {
		#expect(MapTileServer.openStreetMap.description == "Open Street Map")
		#expect(MapTileServer.usgsTopo.description == "USGS Topographic")
		#expect(MapTileServer.watercolor.description == "Watercolor Maptiles")
		#expect(MapTileServer.terrain.description == "Terrain")
		#expect(MapTileServer.toner.description == "Toner")
	}

	@Test func usgsServers_haveRestrictedZoom() {
		#expect(MapTileServer.usgsTopo.zoomRange.first == 6)
		#expect(MapTileServer.usgsImageryTopo.zoomRange.first == 6)
		#expect(MapTileServer.usgsImageryOnly.zoomRange.first == 6)
	}

	@Test func terrainServer_restrictedZoom() {
		#expect(MapTileServer.terrain.zoomRange.last == 15)
	}
}

// MARK: - MapOverlayServer Tests

@Suite("MapOverlayServer Properties")
struct MapOverlayServerPropertyTests {

	@Test func allCases_count() {
		#expect(MapOverlayServer.allCases.count == 9)
	}

	@Test func allCases_haveAttribution() {
		for server in MapOverlayServer.allCases {
			#expect(!server.attribution.isEmpty)
			#expect(server.attribution.contains("Iowa State"))
		}
	}

	@Test func allCases_haveTileUrl() {
		for server in MapOverlayServer.allCases {
			#expect(!server.tileUrl.isEmpty)
			#expect(server.tileUrl.contains("mesonet.agron.iastate.edu"))
		}
	}

	@Test func allCases_haveZoomRange() {
		for server in MapOverlayServer.allCases {
			let range = server.zoomRange
			#expect(!range.isEmpty)
		}
	}

	@Test func allCases_haveOverlayType() {
		for server in MapOverlayServer.allCases {
			#expect(server.overlayType == .tileServer)
		}
	}

	@Test func allCases_haveId() {
		for server in MapOverlayServer.allCases {
			#expect(server.id == server.rawValue)
		}
	}

	@Test func specificDescriptions() {
		#expect(MapOverlayServer.baseReReflectivityCurrent.description == "Base Reflectivity current")
		#expect(MapOverlayServer.q2OneHourPrecipitation.description == "Q2 1 Hour Precipitation")
		#expect(MapOverlayServer.mrmsHybridScanReflectivityComposite.description == "MRMS Hybrid-Scan Reflectivity Composite")
	}
}

// MARK: - OverlayType Tests

@Suite("OverlayType Enum")
struct OverlayTypeEnumTests {

	@Test func allCases_count() {
		#expect(OverlayType.allCases.count == 2)
	}

	@Test func localized_notEmpty() {
		for overlay in OverlayType.allCases {
			#expect(!overlay.localized.isEmpty)
		}
	}
}

// MARK: - MeshMapTypes Tests

@Suite("MeshMapTypes Detailed")
struct MeshMapTypesDetailedTests {

	@Test func allCases_count() {
		#expect(MeshMapTypes.allCases.count == 6)
	}

	@Test func allCases_haveDescriptions() {
		for mapType in MeshMapTypes.allCases {
			#expect(!mapType.description.isEmpty)
		}
	}

	@Test func allCases_haveId() {
		for mapType in MeshMapTypes.allCases {
			#expect(mapType.id == mapType.rawValue)
		}
	}

	@Test func allCases_haveMKMapType() {
		for mapType in MeshMapTypes.allCases {
			_ = mapType.MKMapTypeValue()
		}
	}

	@Test func specificDescriptions() {
		#expect(MeshMapTypes.standard.description.contains("Standard"))
		#expect(MeshMapTypes.satellite.description.contains("Satellite"))
		#expect(MeshMapTypes.hybrid.description.contains("Hybrid"))
	}
}

// MARK: - MeshMapDistances Tests

@Suite("MeshMapDistances Detailed")
struct MeshMapDistancesDetailedTests {

	@Test func allCases_count() {
		#expect(MeshMapDistances.allCases.count == 11)
	}

	@Test func allCases_haveDescriptions() {
		for distance in MeshMapDistances.allCases {
			#expect(!distance.description.isEmpty)
		}
	}

	@Test func allCases_haveId() {
		for distance in MeshMapDistances.allCases {
			#expect(distance.id == distance.rawValue)
		}
	}

	@Test func rawValues_increasing() {
		let sorted = MeshMapDistances.allCases.sorted { $0.rawValue < $1.rawValue }
		for i in 1..<sorted.count {
			#expect(sorted[i].rawValue > sorted[i - 1].rawValue)
		}
	}
}

// MARK: - UserTrackingModes Tests

@Suite("UserTrackingModes Detailed")
struct UserTrackingModesDetailedTests {

	@Test func allCases_count() {
		#expect(UserTrackingModes.allCases.count == 3)
	}

	@Test func allCases_haveDescriptions() {
		for mode in UserTrackingModes.allCases {
			#expect(!mode.description.isEmpty)
		}
	}

	@Test func allCases_haveIcons() {
		for mode in UserTrackingModes.allCases {
			#expect(!mode.icon.isEmpty)
		}
	}

	@Test func allCases_haveMKValues() {
		for mode in UserTrackingModes.allCases {
			_ = mode.MKUserTrackingModeValue()
		}
	}

	@Test func specificIcons() {
		#expect(UserTrackingModes.none.icon == "location")
		#expect(UserTrackingModes.follow.icon == "location.fill")
		#expect(UserTrackingModes.followWithHeading.icon == "location.north.line.fill")
	}
}

// MARK: - Architecture Tests

@Suite("Architecture Enum")
struct ArchitectureEnumTests {

	@Test func allCases_haveRawValues() {
		#expect(Architecture.esp32.rawValue == "esp32")
		#expect(Architecture.esp32C3.rawValue == "esp32-c3")
		#expect(Architecture.esp32S3.rawValue == "esp32-s3")
		#expect(Architecture.nrf52840.rawValue == "nrf52840")
		#expect(Architecture.rp2040.rawValue == "rp2040")
		#expect(Architecture.esp32C6.rawValue == "esp32-c6")
	}

	@Test func identifiable() {
		for arch in [Architecture.esp32, .esp32C3, .esp32S3, .nrf52840, .rp2040, .esp32C6] {
			#expect(arch.id == arch.rawValue)
		}
	}
}

// MARK: - ReleaseType Tests

@Suite("ReleaseType Enum")
struct ReleaseTypeEnumTests {

	@Test func rawValues() {
		#expect(ReleaseType.stable.rawValue == "Stable")
		#expect(ReleaseType.alpha.rawValue == "Alpha")
		#expect(ReleaseType.unlisted.rawValue == "Unlisted")
	}
}

// MARK: - FirmwareFile validFilenameSuffixes Tests

@Suite("FirmwareFile ValidFilenameSuffixes")
struct FirmwareFileValidSuffixesTests {

	@Test func esp32_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32)
		#expect(suffixes == [.bin])
	}

	@Test func esp32C3_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32C3)
		#expect(suffixes == [.bin])
	}

	@Test func esp32S3_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32S3)
		#expect(suffixes == [.bin])
	}

	@Test func esp32C6_returnsBin() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .esp32C6)
		#expect(suffixes == [.bin])
	}

	@Test func nrf52840_returnsUf2AndOtaZip() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .nrf52840)
		#expect(suffixes == [.uf2, .otaZip])
	}

	@Test func rp2040_returnsUf2() {
		let suffixes = FirmwareFile.validFilenameSuffixes(forArchitecture: .rp2040)
		#expect(suffixes == [.uf2])
	}
}

// MARK: - FirmwareFile Static Properties Tests

@Suite("FirmwareFile Static Properties")
struct FirmwareFileStaticPropertyTests {

	@Test func localFirmwareStorageURL_isDocumentsDir() {
		let url = FirmwareFile.localFirmwareStorageURL
		#expect(url.path.contains("Documents"))
	}

	@Test func remoteFirmwareURLPrefix_isGithub() {
		let url = FirmwareFile.remoteFirmwareURLPrefix
		#expect(url.absoluteString.contains("github"))
		#expect(url.absoluteString.contains("meshtastic"))
	}
}

// MARK: - LocationUpdateInterval Extended Tests

@Suite("LocationUpdateInterval Extended")
struct LocationUpdateIntervalExtendedTests {

	@Test func allCases_haveNonEmptyDescriptions() {
		for interval in LocationUpdateInterval.allCases {
			#expect(!interval.description.isEmpty)
		}
	}

	@Test func allCases_identifiable() {
		for interval in LocationUpdateInterval.allCases {
			#expect(interval.id == interval.rawValue)
		}
	}
}

// MARK: - RouteEnums Tests

@Suite("ActivityType Detailed")
struct ActivityTypeDetailedTests {

	@Test func allCases_count() {
		#expect(ActivityType.allCases.count == 6)
	}

	@Test func allCases_haveDescriptions() {
		for activity in ActivityType.allCases {
			#expect(!activity.description.isEmpty)
		}
	}

	@Test func allCases_haveFileNameStrings() {
		for activity in ActivityType.allCases {
			#expect(!activity.fileNameString.isEmpty)
		}
	}

	@Test func identifiable() {
		for activity in ActivityType.allCases {
			#expect(activity.id == activity.rawValue)
		}
	}
}

// MARK: - UserDefault Property Wrapper Tests

@Suite("UserDefault PropertyWrapper")
struct UserDefaultPropertyWrapperTests {

	@Test func readDefaultValue() {
		// Create a UserDefault with a known-unused key pattern
		let wrapper = UserDefault(.meshMapDistance, defaultValue: 8046.72)
		// Should return defaultValue or whatever is stored
		let value = wrapper.wrappedValue
		#expect(value > 0)
	}

	@Test func keys_allCases_haveRawValues() {
		for key in UserDefaults.Keys.allCases {
			#expect(!key.rawValue.isEmpty)
		}
	}
}

// MARK: - CoTXMLParser Additional Tests

@Suite("CoTXMLParser Extended")
struct CoTXMLParserExtendedTests {

	@Test func parse_markerWithDetail() {
		let xml = """
		<event version="2.0" uid="marker-1" type="a-h-G" time="2024-01-01T00:00:00Z" start="2024-01-01T00:00:00Z" stale="2024-01-01T00:10:00Z" how="h-g-i-g-o">
			<point lat="37.7749" lon="-122.4194" hae="10" ce="9999999" le="9999999"/>
			<detail>
				<contact callsign="TestMarker"/>
				<remarks>This is a test marker</remarks>
			</detail>
		</event>
		"""
		let cot = CoTMessage.parse(from: xml)
		#expect(cot != nil)
		#expect(cot?.type == "a-h-G")
		#expect(cot?.contact?.callsign == "TestMarker")
	}

	@Test func parse_pliWithTeamAndRole() {
		let xml = """
		<event version="2.0" uid="pli-1" type="a-f-G-U-C" time="2024-01-01T00:00:00Z" start="2024-01-01T00:00:00Z" stale="2024-01-01T00:10:00Z" how="m-g">
			<point lat="38.0" lon="-121.0" hae="100" ce="10" le="10"/>
			<detail>
				<contact callsign="Alpha1"/>
				<__group name="Yellow" role="Team Lead"/>
				<track speed="5.0" course="180.0"/>
				<status battery="75"/>
			</detail>
		</event>
		"""
		let cot = CoTMessage.parse(from: xml)
		#expect(cot != nil)
		#expect(cot?.type == "a-f-G-U-C")
		#expect(cot?.contact?.callsign == "Alpha1")
		#expect(cot?.group?.name == "Yellow")
		#expect(cot?.group?.role == "Team Lead")
	}

	@Test func parse_chatMessage() {
		let xml = """
		<event version="2.0" uid="GeoChat.user1.All Chat Rooms.abc123" type="b-t-f" time="2024-01-01T00:00:00Z" start="2024-01-01T00:00:00Z" stale="2024-01-01T00:10:00Z" how="h-g-i-g-o">
			<point lat="0" lon="0" hae="0" ce="9999999" le="9999999"/>
			<detail>
				<__chat parent="RootContactGroup" groupOwner="false" chatroom="All Chat Rooms" id="All Chat Rooms" senderCallsign="TestUser">
					<chatgrp uid0="user1" uid1="All Chat Rooms" id="All Chat Rooms"/>
				</__chat>
				<remarks source="BAO.F.ATAK.user1" time="2024-01-01T00:00:00Z">Hello world!</remarks>
			</detail>
		</event>
		"""
		let cot = CoTMessage.parse(from: xml)
		#expect(cot != nil)
		#expect(cot?.type == "b-t-f")
	}
}
