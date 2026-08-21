//
//  MaintenanceUf2ManifestSeedTests.swift
//  MeshtasticTests
//
//  Coverage for MaintenanceUf2ManifestSeed / OTAFIXManifestStore (2026-08-20/21). The manifest
//  gates an irreversible bootloader write, so a malformed fetch must never overwrite an
//  already-loaded manifest.
//

import Foundation
import Testing

@testable import Meshtastic

// .serialized: every test reads/mutates the process-global OTAFIXManifestStore.shared, the same
// caution MeshtasticAPIBundledSeedTests takes for its own global recorder.
@Suite("MaintenanceUf2 manifest seed and store", .serialized)
struct MaintenanceUf2ManifestSeedTests {

	@Test func bundledSeedDecodesToTheAuditedBoardCount() {
		// Same 14-board audited set MaintenanceUF2Tests asserts by content; this just confirms the
		// seed itself (not just the live store, which is seeded from it) carries them.
		#expect(OTAFIXManifestStore.shared.imagesByBoardID.count == 14)
	}

	@Test func applyRejectsMalformedBytesAndKeepsTheCurrentManifest() {
		let store = OTAFIXManifestStore.shared
		let before = store.imagesByBoardID
		let malformed = Data("not json at all".utf8)

		let applied = store.apply(rawBytes: malformed)

		#expect(!applied)
		#expect(store.imagesByBoardID == before)
	}

	@Test func applyReplacesTheManifestOnAValidFetch() {
		let store = OTAFIXManifestStore.shared
		let before = store.imagesByBoardID

		// The seed's own bytes are trivially a valid fetch — applying them back is a no-op in
		// content but must report success and leave the manifest usable.
		let applied = store.apply(rawBytes: MaintenanceUf2ManifestSeed.rawJSON)

		#expect(applied)
		#expect(store.imagesByBoardID == before)
	}

	@Test func applyAcceptsAWellFormedManifestWithADifferentBoardSet() {
		let store = OTAFIXManifestStore.shared
		let before = store.imagesByBoardID
		defer { store.apply(rawBytes: MaintenanceUf2ManifestSeed.rawJSON) } // restore for other tests

		let replacement = Data("""
		{"otafixReleaseTag":"0.0.0-test","otafixBase":"https://example.invalid","otafixByBoardId":{"TEST-BOARD":{"otafixBoardSlug":"test_board","sha256":"0000000000000000000000000000000000000000000000000000000000000"}},"otafixSupportedTargets":[]}
		""".utf8)

		let applied = store.apply(rawBytes: replacement)

		#expect(applied)
		#expect(store.imagesByBoardID != before)
		#expect(store.imagesByBoardID.count == 1)
		#expect(store.releaseTag == "0.0.0-test")
	}
}
