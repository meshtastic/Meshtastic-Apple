//
//  SpatialTerrainDownloadTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/12/26.
//
import CoreLocation
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map terrain download")
struct SpatialTerrainDownloadTests {
	let box = GeoBounds(minLon: -122.4, minLat: 47.5, maxLon: -122.1, maxLat: 47.7)
	let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

	func region(_ bounds: GeoBounds, basemap: Bool = true, terrain: Bool = false, terrainBytes: Int64 = 1, managedBy: String? = nil) -> OfflineMapRegion {
		OfflineMapRegion(
			name: "Region", fileName: "\(UUID().uuidString).pmtiles", bounds: bounds, minZoom: 0, maxZoom: 13,
			fileSize: 1, sourceBuild: "test", includesBasemap: basemap,
			terrain: terrain ? OfflineMapTerrain(fileName: "t.pmtiles", regionalFileName: nil, byteCount: terrainBytes, downloadedAt: .now, maxZoom: 12) : nil,
			managedBy: managedBy
		)
	}

	/// The spatial map's region: streets and terrain unless `basemap` is false (an older build's).
	func managed(_ bounds: GeoBounds, bytes: Int64 = 1, basemap: Bool = true, terrain: Bool = true) -> OfflineMapRegion {
		region(bounds, basemap: basemap, terrain: terrain, terrainBytes: bytes, managedBy: OfflineMapRegion.spatialMapManager)
	}

	func decide(
		_ box: GeoBounds, _ regions: [OfflineMapRegion], busy: Bool = false, backoff: SpatialTerrainBackoff = SpatialTerrainBackoff(),
		growOnly: Bool = false, streetsTooLarge: GeoBounds? = nil
	) -> SpatialTerrainAutoDecision {
		SpatialTerrainAutoDecision.make(box: box, regions: regions, isBusy: busy, backoff: backoff, now: now, growOnly: growOnly, streetsTooLarge: streetsTooLarge)
	}

	func contains(_ outer: GeoBounds, _ inner: GeoBounds) -> Bool {
		outer.minLon <= inner.minLon && outer.maxLon >= inner.maxLon && outer.minLat <= inner.minLat && outer.maxLat >= inner.maxLat
	}

	// MARK: - Coverage

	@Test func coverageFraction() {
		let left = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: -122.25, maxLat: box.maxLat)
		let right = GeoBounds(minLon: -122.25, minLat: box.minLat, maxLon: box.maxLon, maxLat: box.maxLat)
		let quarter = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: -122.25, maxLat: 47.6)
		let far = GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53)
		#expect(SpatialTerrainCoverage.fraction(of: box, covered: []) == 0)
		#expect(SpatialTerrainCoverage.fraction(of: box, covered: [box.expandedForTerrain()]) == 1)
		#expect(SpatialTerrainCoverage.fraction(of: box, covered: [left, right]) == 1, "two halves that only touch cover it all")
		#expect(abs(SpatialTerrainCoverage.fraction(of: box, covered: [quarter]) - 0.25) < 0.05)
		#expect(SpatialTerrainCoverage.fraction(of: box, covered: [far]) == 0)
	}

	// MARK: - Union and expansion

	@Test func unionContainsBoth() {
		let other = GeoBounds(minLon: -122.0, minLat: 47.0, maxLon: -121.5, maxLat: 47.6)
		let union = box.union(other)
		#expect(contains(union, box))
		#expect(contains(union, other))
	}

	@Test func expandedForTerrainContainsTheBoxAndSnapsToZ10() {
		let target = box.expandedForTerrain()
		#expect(contains(target, box))
		let n = 1024.0
		for lon in [target.minLon, target.maxLon] {
			let x = (lon + 180) / 360 * n
			#expect(abs(x - x.rounded()) < 1e-6)
		}
		for lat in [target.minLat, target.maxLat] {
			let y = SpatialFrame.mercatorY(lat) * n
			#expect(abs(y - y.rounded()) < 1e-6)
		}
		// At least 10 km of padding on each side.
		#expect((box.minLat - target.minLat) * SpatialFrame.metersPerDegreeLatitude >= 10_000)
		#expect(target.expandedForTerrain(ratio: 0, minPadMeters: 0) == target, "snapping a snapped box changes nothing")
	}

	@Test func aSlightlyMovedBoxGivesTheSameTarget() {
		let moved = GeoBounds(minLon: box.minLon + 0.002, minLat: box.minLat + 0.001, maxLon: box.maxLon + 0.002, maxLat: box.maxLat + 0.001)
		#expect(moved.expandedForTerrain() == box.expandedForTerrain())
	}

	// MARK: - Decision

	@Test func coveredByAUserRegionDownloadsNothing() {
		let user = region(GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: -121.9, maxLat: 47.85), terrain: true)
		#expect(decide(box, [user]) == .none)
	}

	@Test func coverageNeedsStreetsAndTerrain() {
		let area = GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: -121.9, maxLat: 47.85)
		let terrainOnly = region(area, basemap: false, terrain: true)
		let streetsOnly = region(area)
		#expect(decide(box, [terrainOnly]) == .create(box.expandedForTerrain()))
		#expect(decide(box, [streetsOnly]) == .create(box.expandedForTerrain()))
		#expect(decide(box, [terrainOnly, streetsOnly]) == .none, "two user regions together cover it")
	}

	@Test func aTerrainOnlyManagedRegionIsUpgradedForTheSameArea() {
		let old = managed(box.expandedForTerrain(), basemap: false)
		#expect(decide(box, [old]) == .expand(old.bounds, replacing: old.id), "no extra padding")
		#expect(decide(box, [old], growOnly: true) == .expand(old.bounds, replacing: old.id), "upgrading counts as growing")
		let full = managed(old.bounds)
		#expect(decide(box, [full], growOnly: true) == .none)
	}

	@Test func aManagedRegionCutShortIsReplaced() {
		// The app quit after the street map and before the terrain.
		let leftover = managed(box.expandedForTerrain(), terrain: false)
		#expect(decide(box, [leftover], growOnly: true) == .expand(leftover.bounds, replacing: leftover.id))
	}

	@Test func whereStreetsWereTooLargeTerrainAloneCovers() {
		let old = managed(box.expandedForTerrain(), basemap: false)
		#expect(decide(box, [old], streetsTooLarge: old.bounds) == .none)
		// Outside that area the full map is tried again.
		let grown = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: -121.5, maxLat: box.maxLat)
		#expect(decide(grown, [old], streetsTooLarge: old.bounds) == .expand(old.bounds.union(grown).expandedForTerrain(), replacing: old.id))
	}

	@Test func theEstimateCountsStreetsAndTerrain() {
		let area = Int64(box.areaSquareKm)
		#expect(SpatialTerrainAutoDecision.estimatedTerrainBytes(box) == area * 4_096)
		#expect(SpatialTerrainAutoDecision.estimatedBasemapBytes(box) == area * 4_096)
		#expect(SpatialTerrainAutoDecision.estimatedBytes(box) == area * 8_192)
	}

	@Test func storageCreditsEveryManagedRegion() {
		// The new map is well under 100 MB; only crediting both old ones makes room for it.
		#expect(SpatialTerrainAutoDecision.estimatedBytes(box.expandedForTerrain()) < 100_000_000)
		var big = region(GeoBounds(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1))
		big.fileSize = OfflineMapStorageLimits.maxTotalBytes - 100_000_000
		let far = GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53)
		let old = managed(far, bytes: 150_000_000, basemap: false)
		var leftover = managed(far, terrain: false)
		leftover.fileSize = 150_000_000
		#expect(decide(box, [big, old, leftover]) == .expand(box.expandedForTerrain(), replacing: old.id))
	}

	@Test func managedTerrainCoversOnlyWithTerrain() {
		let inside = GeoBounds(minLon: -122.3, minLat: 47.55, maxLon: -122.2, maxLat: 47.65)
		let manager = OfflineMapRegion.spatialMapManager
		#expect(OfflineMapManager.managedTerrainCovers(inside, in: [managed(box, basemap: false)], managedBy: manager))
		#expect(!OfflineMapManager.managedTerrainCovers(inside, in: [managed(box, terrain: false)], managedBy: manager))
		#expect(!OfflineMapManager.managedTerrainCovers(box.expandedForTerrain(), in: [managed(box)], managedBy: manager))
		#expect(!OfflineMapManager.managedTerrainCovers(inside, in: [region(box, terrain: true)], managedBy: manager), "the user's terrain is not the managed one")
	}

	@Test func smallerAreasForTheStreetMap() {
		let grown = box.expandedForTerrain().union(GeoBounds(minLon: -121.0, minLat: 47.5, maxLon: -120.8, maxLat: 47.7)).expandedForTerrain()
		#expect(SpatialTerrainAutoDecision.smallerAreas(than: grown, box: box) == [box.expandedForTerrain(), box])
		#expect(SpatialTerrainAutoDecision.smallerAreas(than: box.expandedForTerrain(), box: box) == [box])
		#expect(SpatialTerrainAutoDecision.smallerAreas(than: box, box: box).isEmpty)
	}

	@Test func aFullManagedMapReplacesEveryOlderOne() {
		let oldFull = managed(box)
		let oldTerrain = managed(box.expandedForTerrain(), basemap: false)
		let user = region(box, terrain: true)
		let new = managed(box.expandedForTerrain())
		let replaced = OfflineMapManager.managedRegionsReplaced(by: new, in: [oldFull, oldTerrain, user, new])
		#expect(Set(replaced.map(\.id)) == [oldFull.id, oldTerrain.id])
	}

	@Test func terrainOnlyKeepsTheStreetsTheUserHad() {
		let oldFull = managed(box)
		let farFull = managed(GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53))
		let oldTerrain = managed(box, basemap: false)
		let new = managed(box.expandedForTerrain(), basemap: false)
		let replaced = OfflineMapManager.managedRegionsReplaced(by: new, in: [oldFull, farFull, oldTerrain, new])
		#expect(Set(replaced.map(\.id)) == [farFull.id, oldTerrain.id], "the street map under the new terrain stays")
		#expect(OfflineMapManager.managedBytesFreed(by: new, in: [oldFull, farFull, oldTerrain, new]) == farFull.totalByteCount + oldTerrain.totalByteCount)
	}

	@Test func growsFromTheLargestManagedTerrain() {
		// A street map for the box, and terrain for a bigger area beside it.
		let streets = managed(box.expandedForTerrain())
		let wide = GeoBounds(minLon: -123.5, minLat: 47.0, maxLon: -121.0, maxLat: 48.2)
		let terrain = managed(wide, basemap: false)
		let east = GeoBounds(minLon: -121.5, minLat: 47.5, maxLon: -120.5, maxLat: 47.7)
		#expect(decide(east, [streets, terrain]) == .expand(wide.union(east).expandedForTerrain(), replacing: terrain.id))
		#expect(decide(wide, [streets, terrain], streetsTooLarge: wide) == .none)
	}

	@Test func managedBytesNeverBlockTheUsersDownloads() {
		var user = region(GeoBounds(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1))
		user.fileSize = OfflineMapStorageLimits.maxTotalBytes - 200_000_000
		var m = managed(box)
		m.fileSize = 400_000_000
		#expect(OfflineMapManager.storageCounted(in: [user, m], forAppManaged: false) == user.totalByteCount)
		#expect(OfflineMapManager.storageCounted(in: [user, m], forAppManaged: true) == user.totalByteCount + m.totalByteCount)
		#expect(OfflineMapManager.downloadBlockReason(regions: [user, m], estimatedBytes: 100_000_000, replacing: nil) == nil)
		#expect(OfflineMapManager.downloadBlockReason(regions: [user, m], estimatedBytes: 300_000_000, replacing: nil) != nil)
	}

	@Test func aThinUncoveredStripAlongAnEdgeStillDownloads() {
		// The user's terrain stops 1% short of the box's east edge.
		let user = region(GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: box.maxLon - 0.003, maxLat: 47.85), terrain: true)
		#expect(SpatialTerrainCoverage.fraction(of: box, covered: [user.bounds]) < 1)
		#expect(decide(box, [user]) == .create(box.expandedForTerrain()))
	}

	@Test func aRegionExactlyTheBoxCoversIt() {
		let odd = GeoBounds(minLon: -122.123456789, minLat: 47.1, maxLon: -121.987654321, maxLat: 47.3)
		#expect(SpatialTerrainCoverage.fraction(of: odd, covered: [odd]) == 1)
	}

	@Test func partlyCoveredCreatesAManagedRegionForTheWholeBox() {
		let user = region(GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: -122.25, maxLat: 47.85), terrain: true)
		let decision = decide(box, [user])
		guard case .create(let target) = decision else {
			Issue.record("expected .create, got \(decision)")
			return
		}
		#expect(contains(target, box))
		#expect(target == box.expandedForTerrain())
	}

	@Test func aGrownBoxExpandsTheManagedRegion() {
		let m = managed(box.expandedForTerrain())
		let grown = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: -121.5, maxLat: box.maxLat)
		let decision = decide(grown, [m])
		#expect(decision == .expand(m.bounds.union(grown).expandedForTerrain(), replacing: m.id))
		#expect(decision.target.map { contains($0, m.bounds) && contains($0, grown) } == true)
	}

	@Test func growOnlyNeverCreatesButStillExpands() {
		let user = region(GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: -122.25, maxLat: 47.85), terrain: true)
		#expect(decide(box, [], growOnly: true) == .none)
		#expect(decide(box, [user], growOnly: true) == .none)
		let m = managed(box.expandedForTerrain())
		let grown = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: -121.5, maxLat: box.maxLat)
		#expect(decide(grown, [m], growOnly: true) == decide(grown, [m]))
		#expect(decide(grown, [m], growOnly: true) != .none)
	}

	@Test func aFarAwayBoxMovesTheManagedRegion() {
		let m = managed(GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53))
		#expect(decide(box, [m]) == .expand(box.expandedForTerrain(), replacing: m.id))
	}

	@Test func aWideMeshFallsBackToTheBareBox() {
		// About 320 km a side: padded it is over 350 km, the box itself still fits.
		let wide = GeoBounds(minLon: -1.44, minLat: -1.44, maxLon: 1.44, maxLat: 1.44)
		#expect(decide(wide, []) == .create(wide))
	}

	@Test func tooLargeIsBlocked() {
		let huge = GeoBounds(minLon: -2, minLat: -2, maxLon: 2, maxLat: 2)
		#expect(decide(huge, []) == .blocked(.tooLarge))
	}

	@Test func storageNearTheCapIsBlockedButTheOldManagedBytesAreCredited() {
		// A user basemap far away that leaves 1 MB free.
		var big = region(GeoBounds(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1))
		big.fileSize = OfflineMapStorageLimits.maxTotalBytes - 1_000_000
		#expect(decide(box, [big]) == .blocked(.storage))
		big.fileSize -= 200_000_000
		let m = managed(GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53), bytes: 200_000_000)
		#expect(decide(box, [big, m]) == .expand(box.expandedForTerrain(), replacing: m.id))
	}

	@Test func busyDownloadsNothing() {
		#expect(decide(box, [], busy: true) == .none)
	}

	@Test func userRegionsAreNeverNamed() {
		let userA = region(GeoBounds(minLon: -122.55, minLat: 47.4, maxLon: -122.3, maxLat: 47.85), terrain: true)
		let userB = region(GeoBounds(minLon: -122.3, minLat: 47.4, maxLon: -122.2, maxLat: 47.85), basemap: false, terrain: true)
		let userC = region(GeoBounds(minLon: -122.2, minLat: 47.4, maxLon: -122.15, maxLat: 47.85))
		#expect(decide(box, [userA, userB, userC]) == .create(box.expandedForTerrain()))
		let m = managed(GeoBounds(minLon: -122.2, minLat: 47.4, maxLon: -122.12, maxLat: 47.85))
		guard case .expand(_, let replacing) = decide(box, [userA, userB, userC, m]) else {
			Issue.record("expected .expand")
			return
		}
		#expect(replacing == m.id)
	}

	// MARK: - Backoff

	@Test func aFailureDelaysTheRetry() {
		let target = box.expandedForTerrain()
		var backoff = SpatialTerrainBackoff()
		backoff.recordFailure(target, now: now)
		#expect(decide(box, [], backoff: backoff) == .none)
		#expect(!backoff.allows(target, now: now.addingTimeInterval(599)))
		#expect(backoff.allows(target, now: now.addingTimeInterval(601)))
		backoff.recordFailure(target, now: now)
		#expect(!backoff.allows(target, now: now.addingTimeInterval(1_199)), "the second wait is twice as long")
		#expect(backoff.allows(target, now: now.addingTimeInterval(1_201)))
	}

	@Test func threeFailuresStopIt() {
		let target = box.expandedForTerrain()
		var backoff = SpatialTerrainBackoff()
		for _ in 0..<3 { backoff.recordFailure(target, now: now) }
		#expect(!backoff.allows(target, now: now.addingTimeInterval(365 * 86_400)))
		#expect(backoff.gaveUp(on: target))
	}

	@Test func cancelBlocksOnlyThatTarget() {
		let target = box.expandedForTerrain()
		var backoff = SpatialTerrainBackoff()
		backoff.recordCancel(target)
		#expect(!backoff.allows(target, now: now.addingTimeInterval(86_400)))
		#expect(decide(box, [], backoff: backoff) == .none)
		let elsewhere = GeoBounds(minLon: 13, minLat: 52, maxLon: 13.3, maxLat: 52.2)
		#expect(backoff.allows(elsewhere.expandedForTerrain(), now: now))
		#expect(decide(elsewhere, [], backoff: backoff) == .create(elsewhere.expandedForTerrain()))
	}

	@Test func successDoesNotLoop() {
		guard let first = decide(box, []).target else {
			Issue.record("expected a download")
			return
		}
		let m1 = managed(first)
		#expect(decide(box, [m1]) == .none)
		let grown = GeoBounds(minLon: box.minLon, minLat: box.minLat, maxLon: -121.5, maxLat: 47.9)
		guard let second = decide(grown, [m1]).target else {
			Issue.record("expected an expansion")
			return
		}
		let m2 = managed(second)
		#expect(decide(grown, [m2]) == .none)
		#expect(decide(box, [m2]) == .none, "shrinking back never downloads")
	}

	@Test func regionalExtractOnlyForSmallAreas() {
		#expect(!SpatialTerrainAutoDecision.includesRegional(box.expandedForTerrain()))
		#expect(SpatialTerrainAutoDecision.includesRegional(GeoBounds(minLon: -122.3, minLat: 47.6, maxLon: -122.2, maxLat: 47.65)))
	}

	@Test func boxSizeInMeters() {
		let size = box.sizeInMeters
		#expect(abs(size.height - 0.2 * 111_320) < 1)
		#expect(abs(size.width - 0.3 * 111_320 * cos(47.6 * .pi / 180)) < 1)
	}

	// MARK: - Region flag

	@Test func manifestWithoutManagedByIsTheUsers() throws {
		let json = """
		[{"id": "E3B0C442-98FC-1C14-9AFB-F4C8996FB924", "name": "Old", "fileName": "old.pmtiles",
		  "minLongitude": -122.5, "minLatitude": 47.3, "maxLongitude": -122.0, "maxLatitude": 47.8,
		  "minZoom": 0, "maxZoom": 13, "fileSize": 2048, "createdDate": 700000000, "updatedDate": 700000000,
		  "sourceBuild": "20260101"},
		 {"id": "E3B0C442-98FC-1C14-9AFB-F4C8996FB925", "name": "Future", "fileName": "new.pmtiles",
		  "minLongitude": -122.5, "minLatitude": 47.3, "maxLongitude": -122.0, "maxLatitude": 47.8,
		  "minZoom": 0, "maxZoom": 0, "fileSize": 0, "createdDate": 700000000, "updatedDate": 700000000,
		  "sourceBuild": "Mapterhorn", "includesBasemap": false, "managedBy": "somethingNewer"}]
		"""
		let decoded = try JSONDecoder().decode([OfflineMapRegion].self, from: Data(json.utf8))
		#expect(decoded.count == 2)
		#expect(decoded[0].managedBy == nil)
		#expect(!decoded[0].isAppManaged)
		#expect(decoded[1].managedBy == "somethingNewer")
		#expect(decoded[1].isAppManaged)
		let roundTrip = try JSONDecoder().decode(OfflineMapRegion.self, from: JSONEncoder().encode(managed(box)))
		#expect(roundTrip.managedBy == OfflineMapRegion.spatialMapManager)
	}

	// MARK: - Manager rules

	@Test func overlapIgnoresTheManagedRegion() {
		let m = managed(box.expandedForTerrain())
		let inside = GeoBounds(minLon: -122.3, minLat: 47.55, maxLon: -122.2, maxLat: 47.65)
		#expect(OfflineMapManager.overlappingRegion(in: [m], with: inside) == nil)
		let user = region(box)
		#expect(OfflineMapManager.overlappingRegion(in: [m, user], with: inside)?.id == user.id)
	}

	@Test func regionCountExcludesTheManagedRegion() {
		let users = (0..<OfflineMapStorageLimits.maxRegions - 1).map { i in
			region(GeoBounds(minLon: Double(i), minLat: 0, maxLon: Double(i) + 0.5, maxLat: 0.5))
		}
		let m = managed(box)
		#expect(OfflineMapManager.userRegionCount(users + [m]) == OfflineMapStorageLimits.maxRegions - 1)
		#expect(OfflineMapManager.downloadBlockReason(regions: users + [m], estimatedBytes: 0, replacing: nil) == nil)
		let full = users + [region(GeoBounds(minLon: 20, minLat: 0, maxLon: 20.5, maxLat: 0.5))]
		#expect(OfflineMapManager.downloadBlockReason(regions: full, estimatedBytes: 0, replacing: nil) != nil)
	}

	// MARK: - Terrain source selection

	@Test func theSourceContainingTheTileWins() {
		let user = GeoBounds(minLon: -122.35, minLat: 47.55, maxLon: -122.25, maxLat: 47.65)
		let managedBox = box.expandedForTerrain()
		let sources: [(bounds: GeoBounds, maxZoom: Int)] = [(user, 12), (managedBox, 12)]
		// Just east of the user box's east edge, inside the managed box.
		let point = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.2495)
		let pixel = TerrainStore.tilePixel(latitude: point.latitude, longitude: point.longitude, z: 12, size: 256)
		let tile = TerrainStore.tileBounds(z: 12, x: pixel.x, y: pixel.y)
		#expect(tile.minLon < user.maxLon, "the tile straddles the user box's edge")
		let chosen = TerrainStore.preferredSourceIndex(tile: tile, sources: sources)
		#expect(chosen == 1)
		#expect(chosen.map { sources[$0].bounds.contains(point) } == true, "the point is covered")
	}

	@Test func sourceSelectionPrefersFinerDataThenOverlap() {
		let tile = TerrainStore.tileBounds(z: 12, x: 655, y: 1428)
		let big = GeoBounds(minLon: tile.minLon - 1, minLat: tile.minLat - 1, maxLon: tile.maxLon + 1, maxLat: tile.maxLat + 1)
		#expect(TerrainStore.preferredSourceIndex(tile: tile, sources: [(big, 12), (big, 15)]) == 1)
		#expect(TerrainStore.preferredSourceIndex(tile: tile, sources: [(big, 12), (big, 12)]) == 0)
		let width = tile.maxLon - tile.minLon
		let sliver = GeoBounds(minLon: tile.minLon, minLat: tile.minLat, maxLon: tile.minLon + width * 0.1, maxLat: tile.maxLat)
		let most = GeoBounds(minLon: tile.minLon + width * 0.2, minLat: tile.minLat, maxLon: tile.maxLon + 1, maxLat: tile.maxLat)
		#expect(TerrainStore.preferredSourceIndex(tile: tile, sources: [(sliver, 12), (most, 12)]) == 1)
		let far = GeoBounds(minLon: 13, minLat: 52, maxLon: 14, maxLat: 53)
		#expect(TerrainStore.preferredSourceIndex(tile: tile, sources: [(far, 12)]) == nil)
	}
}
