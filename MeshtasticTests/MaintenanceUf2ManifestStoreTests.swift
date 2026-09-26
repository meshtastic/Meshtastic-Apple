//
//  MaintenanceUf2ManifestStoreTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/27/26.
//
//  Pins the API-refresh half of the maintenance manifest: a valid payload
//  replaces the live board map and erase rows, and anything that fails decoding
//  or structural validation is a no-op that keeps the audited bundled seed.
//  Validation is structural, not content pinning — the fetch is trusted like the
//  firmware downloads are, but a payload that could produce an unsafe write path
//  or an unverifiable digest is refused wholesale.
//
//  Every test runs against an isolated store, never `shared`: the singleton is
//  read by the seed-pinning suites, which run in parallel with this one.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Maintenance UF2 manifest store")
struct MaintenanceUf2ManifestStoreTests {

	private func validPayload(
		tag: String = "0.9.3-OTAFIX2.4",
		digest: String = String(repeating: "ab", count: 32),
		version: Int = 1,
		erase: String = ""
	) -> String {
		"""
		{ "manifestVersion": \(version),
		  "otafixReleaseTag": "\(tag)",
		  "otafixBase": "https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/\(tag)",
		  "otafixByBoardId": { "WisBlock-RAK4631-Board": { "otafixBoardSlug": "wiscore_rak4631_board", "sha256": "\(digest)" } },
		  "otafixSupportedTargets": ["rak4631"]\(erase) }
		"""
	}

	private static let eraseBlock = """
		,
		  "erase": {
		    "nrf52": { "7.3.0": { "fileName": "nrf_erase_sd7_3.uf2", "sha256": "\(String(repeating: "cd", count: 32))", "expectedFirstTargetAddress": 159744 } },
		    "nrf52Bootloader": { "fileName": "meshtastic_factory_erase.uf2", "sha256": "\(String(repeating: "ef", count: 32))", "expectedFamilyId": 1296388936 }
		  }
		"""

	@Test func validPayloadReplacesTheLiveMap() throws {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		#expect(store.apply(rawBytes: Data(validPayload().utf8)))
		#expect(store.releaseTag == "0.9.3-OTAFIX2.4")
		let image = try #require(store.image(forBoardID: "WisBlock-RAK4631-Board"))
		#expect(image.fileName == "update-wiscore_rak4631_board_bootloader-0.9.3-OTAFIX2.4_nosd.uf2")
		#expect(store.supportedTargets == ["rak4631"])
	}

	@Test func storeSeedsFromTheAuditedBundledMap() {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		#expect(store.releaseTag == OTAFIXBootloader.bundledReleaseTag)
		#expect(store.imagesByBoardID.count == OTAFIXBootloader.bundledImagesByBoardID.count)
		#expect(store.eraseSet == NRF52FactoryErase.bundledEraseSet)
	}

	@Test func eraseRowsResolveToTheAPIAssetRoute() throws {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		#expect(store.apply(rawBytes: Data(validPayload(erase: Self.eraseBlock).utf8)))

		let softDevice = try #require(store.eraseSet.nrf52BySoftDevice["7.3.0"])
		#expect(softDevice.image.url.absoluteString
			== "https://api.meshtastic.org/resource/maintenanceUf2/asset/nrf_erase_sd7_3.uf2")
		#expect(softDevice.expectedFirstTargetAddress == 0x27000)

		let bootloader = try #require(store.eraseSet.nrf52Bootloader)
		#expect(bootloader.expectedFamilyID == 0x4D45_5348)
		#expect(bootloader.expectedFirstTargetAddress == nil)
	}

	/// A manifest with no erase set at all is structurally valid — it simply leaves the erase
	/// flow with nothing to offer, which the view reports rather than guessing an image.
	@Test func aManifestWithoutAnEraseSetIsValidAndEmptiesTheEraseRows() {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		#expect(store.apply(rawBytes: Data(validPayload().utf8)))
		#expect(store.eraseSet.nrf52BySoftDevice.isEmpty)
		#expect(store.eraseSet.nrf52Bootloader == nil)
	}

	/// The load-bearing one. Erase file names come from the server and are appended to the
	/// user-picked drive URL before the write, so a row naming a path must never be applied.
	@Test func anEraseRowWithATraversingFileNameIsRefused() {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		let before = store.releaseTag
		let traversal = validPayload(erase: Self.eraseBlock)
			.replacingOccurrences(of: "meshtastic_factory_erase.uf2", with: "../../evil.uf2")
		#expect(!store.apply(rawBytes: Data(traversal.utf8)))
		#expect(store.releaseTag == before, "a refused payload must keep the current manifest")
	}

	/// A row we cannot cross-check against the downloaded bytes is dropped, not trusted: the
	/// digest proves the bytes, but only the address (or family) proves the pairing.
	@Test func eraseRowsMissingTheirHeaderContractAreDropped() {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		let noContract = validPayload(erase: Self.eraseBlock)
			.replacingOccurrences(of: ", \"expectedFirstTargetAddress\": 159744", with: "")
			.replacingOccurrences(of: ", \"expectedFamilyId\": 1296388936", with: "")
		#expect(store.apply(rawBytes: Data(noContract.utf8)), "structurally valid — the rows just cannot be used")
		#expect(store.eraseSet.nrf52BySoftDevice.isEmpty)
		#expect(store.eraseSet.nrf52Bootloader == nil)
	}

	@Test func garbageAndInvalidPayloadsAreNoOps() {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		let before = store.releaseTag
		// Not JSON at all.
		#expect(!store.apply(rawBytes: Data("not json".utf8)))
		// A manifest version this build does not know how to read.
		#expect(!store.apply(rawBytes: Data(validPayload(version: 2).utf8)))
		// Digest is not 64 lowercase hex.
		#expect(!store.apply(rawBytes: Data(validPayload(digest: "ZZ").utf8)))
		// Board slug that would traverse out of the drive path.
		let unsafeSlug = validPayload().replacingOccurrences(of: "wiscore_rak4631_board", with: "../evil")
		#expect(!store.apply(rawBytes: Data(unsafeSlug.utf8)))
		// Plain-HTTP download base.
		let httpBase = validPayload().replacingOccurrences(of: "https://", with: "http://")
		#expect(!store.apply(rawBytes: Data(httpBase.utf8)))
		// Release tag that would traverse the URL path.
		#expect(!store.apply(rawBytes: Data(validPayload(tag: "../v9").utf8)))
		#expect(store.releaseTag == before, "a refused payload must keep the current manifest")
	}

	/// The live manifest must satisfy the validator this app ships, or a deploy silently
	/// pins every client to its bundled seed. Structural only — no network.
	@Test func theBundledSeedRoundTripsThroughTheValidator() throws {
		let store = MaintenanceUf2ManifestStore.isolatedForTesting()
		let rows = OTAFIXBootloader.bundledImagesByBoardID
		#expect(!rows.isEmpty)
		for (boardID, image) in rows {
			#expect(image.sha256.count == 64, "\(boardID) digest length")
			#expect(image.fileName.hasSuffix(".uf2"), "\(boardID) file name")
			#expect(!image.fileName.contains("/"), "\(boardID) file name must not be a path")
		}
		let bootloader = try #require(store.eraseSet.nrf52Bootloader)
		#expect(!bootloader.image.fileName.contains("/"))
	}
}
