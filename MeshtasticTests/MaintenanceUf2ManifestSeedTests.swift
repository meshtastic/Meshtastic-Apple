//
//  MaintenanceUf2ManifestSeedTests.swift
//  MeshtasticTests
//
//  Byte-fidelity and digest-pin coverage for MaintenanceUf2ManifestSeed / OTAFIXManifestStore
//  (2026-08-20). The manifest gates an irreversible bootloader/erase write, so unlike most bundled
//  seeds, a mismatch between the seed's actual bytes and OTAFIXBootloader.expectedManifestSHA256
//  must fail a test, not just a runtime warning — that mismatch would mean a future edit to one
//  without the other shipped silently.
//

import CryptoKit
import Foundation
import Testing

@testable import Meshtastic

// .serialized: every test reads/mutates the process-global OTAFIXManifestStore.shared, the same
// caution MeshtasticAPIBundledSeedTests takes for its own global recorder.
@Suite("MaintenanceUf2 manifest seed and store", .serialized)
struct MaintenanceUf2ManifestSeedTests {

	@Test func bundledSeedMatchesThePinnedDigest() {
		let digest = SHA256.hash(data: MaintenanceUf2ManifestSeed.rawJSON).map { String(format: "%02x", $0) }.joined()
		#expect(digest == OTAFIXBootloader.expectedManifestSHA256)
	}

	@Test func bundledSeedDecodesToTheAuditedBoardCount() {
		// Same 14-board audited set MaintenanceUF2Tests asserts by content; this just confirms the
		// seed itself (not just the live store, which is seeded from it) carries them.
		#expect(OTAFIXManifestStore.shared.imagesByBoardID.count == 14)
	}

	@Test func applyRejectsAMismatchedDigestAndKeepsTheCurrentManifest() {
		let store = OTAFIXManifestStore.shared
		let before = store.imagesByBoardID
		let tampered = Data("not the real manifest".utf8)

		let applied = store.apply(rawBytes: tampered, expectedSHA256: OTAFIXBootloader.expectedManifestSHA256)

		#expect(!applied)
		#expect(store.imagesByBoardID == before)
	}

	@Test func applyRejectsValidJSONThatDoesNotMatchTheExpectedDigest() {
		let store = OTAFIXManifestStore.shared
		let before = store.imagesByBoardID
		// Well-formed JSON in the right shape, but its bytes don't hash to expectedManifestSHA256
		// — must still be rejected. A digest check on well-formed-but-wrong data is exactly the
		// case a "does it parse?" check alone would miss.
		let otherValidManifest = Data("""
		{"otafixReleaseTag":"0.0.0-fake","otafixBase":"https://example.invalid","otafixByBoardId":{},"otafixSupportedTargets":[]}
		""".utf8)

		let applied = store.apply(rawBytes: otherValidManifest, expectedSHA256: OTAFIXBootloader.expectedManifestSHA256)

		#expect(!applied)
		#expect(store.imagesByBoardID == before)
	}

	@Test func applyAcceptsBytesMatchingTheExpectedDigest() {
		let store = OTAFIXManifestStore.shared
		let before = store.imagesByBoardID

		// The seed's own bytes trivially satisfy their own pinned digest — applying them back is a
		// no-op in content but must report success and leave the manifest usable.
		let applied = store.apply(rawBytes: MaintenanceUf2ManifestSeed.rawJSON, expectedSHA256: OTAFIXBootloader.expectedManifestSHA256)

		#expect(applied)
		#expect(store.imagesByBoardID == before)
	}
}
