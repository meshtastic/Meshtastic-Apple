//
//  OTAFIXManifestStoreTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/27/26.
//
//  Pins the API-refresh half of the OTAFIX board map: a valid manifest payload
//  replaces the live map, and anything that fails decoding or structural
//  validation is a no-op that keeps the audited bundled seed. Validation is
//  structural, not content pinning — the fetch is trusted like the firmware
//  downloads are, but a payload that could produce an unsafe write path or an
//  unverifiable digest is refused wholesale.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("OTAFIX manifest store", .serialized)
struct OTAFIXManifestStoreTests {

	private func validPayload(tag: String = "0.9.3-OTAFIX2.4", digest: String = String(repeating: "ab", count: 32)) -> String {
		"""
		{ "otafixReleaseTag": "\(tag)",
		  "otafixBase": "https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/\(tag)",
		  "otafixByBoardId": { "WisBlock-RAK4631-Board": { "otafixBoardSlug": "wiscore_rak4631_board", "sha256": "\(digest)" } },
		  "otafixSupportedTargets": ["rak4631"] }
		"""
	}

	@Test func validPayloadReplacesTheLiveMap() {
		defer { OTAFIXManifestStore.shared.resetToBundledSeedForTesting() }
		#expect(OTAFIXManifestStore.shared.apply(rawBytes: Data(validPayload().utf8)))
		#expect(OTAFIXBootloader.releaseTag == "0.9.3-OTAFIX2.4")
		let image = OTAFIXBootloader.image(forBoardID: "WisBlock-RAK4631-Board")
		#expect(image?.fileName == "update-wiscore_rak4631_board_bootloader-0.9.3-OTAFIX2.4_nosd.uf2")
	}

	@Test func storeSeedsFromTheAuditedBundledMap() {
		OTAFIXManifestStore.shared.resetToBundledSeedForTesting()
		#expect(OTAFIXBootloader.releaseTag == OTAFIXBootloader.bundledReleaseTag)
		#expect(OTAFIXBootloader.imagesByBoardID.count == OTAFIXBootloader.bundledImagesByBoardID.count)
	}

	@Test func garbageAndInvalidPayloadsAreNoOps() {
		defer { OTAFIXManifestStore.shared.resetToBundledSeedForTesting() }
		let before = OTAFIXBootloader.releaseTag
		// Not JSON at all.
		#expect(!OTAFIXManifestStore.shared.apply(rawBytes: Data("not json".utf8)))
		// Digest is not 64 lowercase hex.
		#expect(!OTAFIXManifestStore.shared.apply(rawBytes: Data(validPayload(digest: "ZZ").utf8)))
		// Board slug that would traverse out of the drive path.
		let unsafeSlug = validPayload().replacingOccurrences(of: "wiscore_rak4631_board", with: "../evil")
		#expect(!OTAFIXManifestStore.shared.apply(rawBytes: Data(unsafeSlug.utf8)))
		// Plain-HTTP download base.
		let httpBase = validPayload().replacingOccurrences(of: "https://", with: "http://")
		#expect(!OTAFIXManifestStore.shared.apply(rawBytes: Data(httpBase.utf8)))
		// Release tag that would traverse the URL path.
		#expect(!OTAFIXManifestStore.shared.apply(rawBytes: Data(validPayload(tag: "../v9").utf8)))
		#expect(OTAFIXBootloader.releaseTag == before, "a refused payload must keep the current map")
	}
}
