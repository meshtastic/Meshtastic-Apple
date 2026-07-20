//
//  BurningManOfflinePackTests.swift
//  MeshtasticTests
//

import CoreLocation
import Foundation
import Testing

@testable import Meshtastic

@Suite("Burning Man offline pack policy")
struct BurningManOfflinePackTests {

	@Test func outsideAreaOnSeptember8_removesPack() {
		let action = BurningManOfflinePack.policy(
			now: .burningMan("2026-09-08T08:00:00Z"),
			location: CLLocation(
				coordinate: .init(latitude: 37.3346, longitude: -122.0090), altitude: 0,
				horizontalAccuracy: 30, verticalAccuracy: 30,
				timestamp: .burningMan("2026-09-08T07:00:00Z")
			)
		)
		#expect(action == .remove)
	}

	@Test func noLocationBeforeSeptember12_retainsPack() {
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: nil
		) == .retain)
	}

	@Test func noLocationOnSeptember12_removesPack() {
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-12T07:00:00Z"), location: nil
		) == .remove)
	}

	@Test func recentLocationInsideBufferedArea_retainsPack() {
		let location = CLLocation(
			coordinate: .init(latitude: 40.7800, longitude: -119.2000), altitude: 0,
			horizontalAccuracy: 30, verticalAccuracy: 30,
			timestamp: .burningMan("2026-09-10T07:00:00Z")
		)
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: location
		) == .retain)
	}

	@Test func staleLocationBeforeSeptember12_retainsPack() {
		let location = CLLocation(
			coordinate: .init(latitude: 37.3346, longitude: -122.0090), altitude: 0,
			horizontalAccuracy: 30, verticalAccuracy: 30,
			timestamp: .burningMan("2026-09-08T07:59:59Z")
		)
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: location
		) == .retain)
	}

	@Test func invalidAccuracyBeforeSeptember12_retainsPack() {
		let location = CLLocation(
			coordinate: .init(latitude: 37.3346, longitude: -122.0090), altitude: 0,
			horizontalAccuracy: -1, verticalAccuracy: -1,
			timestamp: .burningMan("2026-09-10T07:00:00Z")
		)
		#expect(BurningManOfflinePack.policy(
			now: .burningMan("2026-09-10T08:00:00Z"), location: location
		) == .retain)
	}

	@Test @MainActor func reconcileInstallsOnlyOnce() async {
		let store = InMemoryBurningManPackStore()
		let downloader = RecordingBurningManPackDownloader()
		let coordinator = BurningManOfflinePackCoordinator(store: store, downloader: downloader)

		await coordinator.reconcile(now: .burningMan("2026-08-01T12:00:00Z"), location: nil)
		await coordinator.reconcile(now: .burningMan("2026-08-02T12:00:00Z"), location: nil)

		#expect(downloader.downloadRequests == 1)
	}

	@Test @MainActor func userRemovalSuppressesLaterInstall() async {
		let store = InMemoryBurningManPackStore(userSuppressed: true)
		let downloader = RecordingBurningManPackDownloader()

		await BurningManOfflinePackCoordinator(store: store, downloader: downloader)
			.reconcile(now: .burningMan("2026-08-01T12:00:00Z"), location: nil)

		#expect(downloader.downloadRequests == 0)
	}
}

private extension Date {
	static func burningMan(_ value: String) -> Date {
		ISO8601DateFormatter().date(from: value)!
	}
}

@MainActor
private final class InMemoryBurningManPackStore: BurningManOfflinePackStoring {
	private(set) var regionID: UUID?
	private(set) var sourceBuild: String?
	var userSuppressed: Bool

	init(userSuppressed: Bool = false) {
		self.userSuppressed = userSuppressed
	}

	func record(region: OfflineMapRegion) {
		regionID = region.id
		sourceBuild = region.sourceBuild
	}

	func clearPack() {
		regionID = nil
		sourceBuild = nil
	}

	func suppressIfManaging(regionID: UUID) {
		guard self.regionID == regionID else { return }
		clearPack()
		userSuppressed = true
	}
}

@MainActor
private final class RecordingBurningManPackDownloader: BurningManOfflinePackDownloading {
	private var regions: [UUID: OfflineMapRegion] = [:]
	private(set) var downloadRequests = 0
	var isDownloading = false

	func region(id: UUID) -> OfflineMapRegion? {
		regions[id]
	}

	func startSystemPackDownload(
		packID: String,
		bounds: GeoBounds,
		detail: OfflineMapDetailLevel,
		completion: @escaping (OfflineMapRegion?) -> Void
	) {
		downloadRequests += 1
		let region = OfflineMapRegion(
			name: packID, fileName: "burning-man-test.pmtiles", bounds: bounds,
			minZoom: detail.minZoom, maxZoom: detail.maxZoom, fileSize: 1,
			sourceBuild: "20260720"
		)
		regions[region.id] = region
		completion(region)
	}

	func removeSystemPack(id: UUID, reason: OfflineMapRemovalReason) {
		regions[id] = nil
	}
}
