//
//  BurningManOfflinePackTests.swift
//  MeshtasticTests
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Burning Man offline map")
struct BurningManOfflinePackTests {

	@Test func onlyBurningManFirmwareIsEligible() {
		#expect(BurningManOfflinePack.isEligible(firmwareEdition: FirmwareEditions.burningMan))
		#expect(!BurningManOfflinePack.isEligible(firmwareEdition: FirmwareEditions.vanilla))
		#expect(!BurningManOfflinePack.isEligible(firmwareEdition: FirmwareEditions.defcon))
	}

	@Test func identifiesTheBurningManMapAmongDownloadedRegions() {
		let region = OfflineMapRegion(
			name: "Burning Man 2026",
			fileName: "playa.pmtiles",
			bounds: BurningManOfflinePack.bounds,
			minZoom: 0,
			maxZoom: 15,
			fileSize: 4_096,
			sourceBuild: "20260727",
			systemPackID: BurningManOfflinePack.packID
		)

		#expect(BurningManOfflinePack.existingRegion(in: [region])?.id == region.id)
	}

	@Test func ignoresOtherOfflineMaps() {
		let region = OfflineMapRegion(
			name: "Other map",
			fileName: "other.pmtiles",
			bounds: BurningManOfflinePack.bounds,
			minZoom: 0,
			maxZoom: 15,
			fileSize: 4_096,
			sourceBuild: "20260727"
		)

		#expect(BurningManOfflinePack.existingRegion(in: [region]) == nil)
	}
}

@Suite("Offline map download lifecycle")
struct OfflineMapDownloadLifecycleTests {

	@Test func cancelledDownloadCannotClearReplacement() {
		var lifecycle = OfflineMapDownloadLifecycle()
		let cancelledID = UUID()
		let replacementID = UUID()

		let beganCancelled = lifecycle.begin(id: cancelledID)
		let endedCancelled = lifecycle.end(id: cancelledID)
		let beganReplacement = lifecycle.begin(id: replacementID)
		let staleCleanupWasIgnored = !lifecycle.end(id: cancelledID)
		#expect(beganCancelled)
		#expect(endedCancelled)
		#expect(beganReplacement)
		#expect(staleCleanupWasIgnored)
		#expect(lifecycle.isCurrent(replacementID))
	}

	@Test func failedDownloadDoesNotBlockRetry() {
		var lifecycle = OfflineMapDownloadLifecycle()
		let failedID = UUID()
		let retryID = UUID()

		let beganFailed = lifecycle.begin(id: failedID)
		let endedFailed = lifecycle.end(id: failedID)
		#expect(beganFailed)
		#expect(endedFailed)
		#expect(!lifecycle.isDownloading)
		let beganRetry = lifecycle.begin(id: retryID)
		#expect(beganRetry)
		#expect(lifecycle.isCurrent(retryID))
	}
}
