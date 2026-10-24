//
//  SpatialMapDownloadPromptTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import Foundation
import Testing
@testable import Meshtastic

@Suite("Spatial map download prompt")
struct SpatialMapDownloadPromptTests {
	private func offers(_ prompt: inout SpatialMapDownloadPrompt, refreshes: Int, positionedNodes: Int = 0, hasDownloadedMap: Bool = false, autoDownload: Bool = true, isBusy: Bool = false) -> [Bool] {
		(0..<refreshes).map { _ in prompt.shouldOffer(positionedNodes: positionedNodes, hasDownloadedMap: hasDownloadedMap, autoDownload: autoDownload, isBusy: isBusy) }
	}

	private func region(_ bounds: GeoBounds, created: Date, managedBy: String? = nil) -> OfflineMapRegion {
		OfflineMapRegion(
			name: "Region", fileName: "\(UUID().uuidString).pmtiles", bounds: bounds, minZoom: 0, maxZoom: 13,
			fileSize: 1, createdDate: created, sourceBuild: "test", managedBy: managedBy
		)
	}

	@Test func offersOnceAfterTheSettleWithNoPositions() {
		var prompt = SpatialMapDownloadPrompt()
		let results = offers(&prompt, refreshes: SpatialMapDownloadPrompt.settleRefreshes + 3)
		#expect(results.filter { $0 }.count == 1)
		#expect(results[SpatialMapDownloadPrompt.settleRefreshes - 1])
	}

	@Test func neverOffersOncePositionsArrive() {
		var prompt = SpatialMapDownloadPrompt()
		_ = offers(&prompt, refreshes: 1)
		_ = offers(&prompt, refreshes: 1, positionedNodes: 3)
		let later = offers(&prompt, refreshes: 10)
		#expect(!later.contains(true))
	}

	@Test func waitsWhileTheAutomaticDownloadIsOff() {
		var prompt = SpatialMapDownloadPrompt()
		#expect(!offers(&prompt, refreshes: 10, autoDownload: false).contains(true))
	}

	@Test func waitsWhileADownloadIsRunning() {
		var prompt = SpatialMapDownloadPrompt()
		#expect(!offers(&prompt, refreshes: 10, isBusy: true).contains(true))
		let shouldOffer = prompt.shouldOffer(positionedNodes: 0, hasDownloadedMap: false, autoDownload: true, isBusy: false)
		#expect(shouldOffer)
	}

	@Test func neverOffersWithADownloadedMapToShow() {
		var prompt = SpatialMapDownloadPrompt()
		#expect(!offers(&prompt, refreshes: 10, hasDownloadedMap: true).contains(true))
	}

	@Test func downloadedMapCircleIsCenteredOnTheNewestUserMap() throws {
		let older = region(GeoBounds(minLon: -123, minLat: 45, maxLon: -122, maxLat: 46), created: Date(timeIntervalSinceReferenceDate: 1))
		let newest = region(GeoBounds(minLon: -122.4, minLat: 47.5, maxLon: -122.2, maxLat: 47.7), created: Date(timeIntervalSinceReferenceDate: 2))
		let managed = region(GeoBounds(minLon: 10, minLat: 50, maxLon: 11, maxLat: 51), created: Date(timeIntervalSinceReferenceDate: 3), managedBy: OfflineMapRegion.spatialMapManager)
		let circle = try #require(SpatialMapArea.downloadedMapCircle([older, newest, managed]))
		#expect(abs(circle.latitude - 47.6) < 1e-9)
		#expect(abs(circle.longitude - -122.3) < 1e-9)
		#expect(circle.contains(.init(latitude: 47.5, longitude: -122.4)))
		#expect(circle.contains(.init(latitude: 47.7, longitude: -122.2)))
	}

	@Test func downloadedMapCircleIgnoresTheAppsOwnMap() {
		let managed = region(GeoBounds(minLon: 10, minLat: 50, maxLon: 11, maxLat: 51), created: .now, managedBy: OfflineMapRegion.spatialMapManager)
		#expect(SpatialMapArea.downloadedMapCircle([managed]) == nil)
		#expect(SpatialMapArea.downloadedMapCircle([]) == nil)
	}

	@Test func downloadedMapCircleIsCappedAtTheTableLimit() throws {
		let huge = region(GeoBounds(minLon: -125, minLat: 40, maxLon: -115, maxLat: 49), created: .now)
		let circle = try #require(SpatialMapArea.downloadedMapCircle([huge]))
		#expect(circle.radiusMeters == SpatialMapArea.maxRadiusMeters)
	}
}
