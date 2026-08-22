//
//  MaintenanceUF2Tests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/19/26.
//
//  Pins the OTAFIX bootloader map and INFO_UF2.TXT parsing (#2336). The map's
//  correctness is safety-critical — a wrong Board-ID pairing writes a
//  bootloader built for other hardware, which is unrecoverable without a debug
//  probe — so the rows are asserted against the audited set mirrored from
//  Meshtastic-Android rather than merely being internally consistent.
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("OTAFIX bootloader resolution")
struct MaintenanceUF2Tests {

	/// The audited Board-ID set, mirrored from Android's OTAFIX_BY_BOARD_ID.
	/// A row appearing or vanishing here must be a deliberate change.
	private static let auditedBoardIDs: Set<String> = [
		"HT-n5262",
		"MinewSemi-MX25LE01",
		"TRACKER L1",
		"WisBlock-RAK4631-Board",
		"WisMesh-Tag",
		"nRF52840-SeeedSenseCAPSolarP1-v1",
		"nRF52840-SeeedXiao-v1",
		"nRF52840-SeeedXiaoSense-v1",
		"nRF52840-T1000-E-v1",
		"nRF52840-TEcho-v1",
		"nRF52840-ThinkNode-M3-v1",
		"nRF52840-ThinkNodeM1-v1",
		"nRF52840-ThinkNodeM6-v1",
		"nRF52840-promicro"
	]

	@Test func mapCarriesExactlyTheAuditedBoards() {
		#expect(Set(OTAFIXBootloader.imagesByBoardID.keys) == Self.auditedBoardIDs)
	}

	@Test func everyRowIsInternallyConsistent() throws {
		for (boardID, image) in OTAFIXBootloader.imagesByBoardID {
			// Release-pinned URL that ends in its own file name.
			#expect(image.url.absoluteString.contains(OTAFIXBootloader.releaseTag), "\(boardID) URL is not release-pinned")
			#expect(image.url.lastPathComponent == image.fileName, "\(boardID) URL/fileName mismatch")
			#expect(image.fileName.hasPrefix("update-"), "\(boardID) is not a self-update image")
			#expect(image.fileName.hasSuffix("_nosd.uf2"), "\(boardID) image must not carry a SoftDevice")
			// Pinned digest is well-formed lowercase hex.
			#expect(image.sha256.count == 64, "\(boardID) digest length")
			#expect(image.sha256.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) }, "\(boardID) digest format")
			// fileName is interpolated into a path on the drive; keep it inert.
			#expect(!image.fileName.contains("/") && !image.fileName.contains(".."), "\(boardID) unsafe file name")
		}
	}

	/// The split OTAFIX's own README warns about: the two XIAO variants differ
	/// only by Board-ID, and each must resolve to its own image.
	@Test func xiaoVariantsResolveToDistinctImages() throws {
		let ble = try #require(OTAFIXBootloader.image(forBoardID: "nRF52840-SeeedXiao-v1"))
		let sense = try #require(OTAFIXBootloader.image(forBoardID: "nRF52840-SeeedXiaoSense-v1"))
		#expect(ble.fileName != sense.fileName)
		#expect(ble.sha256 != sense.sha256)
	}

	@Test func unknownBoardIDRefuses() {
		#expect(OTAFIXBootloader.image(forBoardID: "nRF52840-SomeNewBoard-v1") == nil)
		#expect(OTAFIXBootloader.image(forBoardID: "") == nil)
	}

	@Test func boardIDLookupTrimsWhitespace() {
		#expect(OTAFIXBootloader.image(forBoardID: "  WisBlock-RAK4631-Board ") != nil)
	}

	// MARK: - INFO_UF2.TXT parsing

	@Test func parsesTheCanonicalInfoFile() {
		let text = "UF2 Bootloader 0.4.3 lib/nrfx (v2.0.0) lib/tinyusb (0.10.1-293-gaf8e5a90) lib/uf2 (remotes/origin/configupdate-9-gadbb8c7)\r\nModel: WisBlock RAK4631 Board\r\nBoard-ID: WisBlock-RAK4631-Board\r\nDate: Dec 1 2021\r\n"
		#expect(OTAFIXBootloader.parseBoardID(fromInfoText: text) == "WisBlock-RAK4631-Board")
	}

	@Test func parsingIsCaseInsensitiveAndTrims() {
		#expect(OTAFIXBootloader.parseBoardID(fromInfoText: "board-id:   HT-n5262  \n") == "HT-n5262")
	}

	@Test func missingBoardIDLineIsNil() {
		#expect(OTAFIXBootloader.parseBoardID(fromInfoText: "Model: Something\r\nDate: Jan 1 2024\r\n") == nil)
		#expect(OTAFIXBootloader.parseBoardID(fromInfoText: "") == nil)
	}

	@Test func emptyBoardIDValueIsNil() {
		#expect(OTAFIXBootloader.parseBoardID(fromInfoText: "Board-ID:\r\n") == nil)
	}

	// MARK: - UX gate

	@Test func supportedTargetsMatchTheAuditedSet() {
		// Positive cases from OTAFIX's supported list…
		#expect(OTAFIXBootloader.supportsTarget("rak4631"))
		#expect(OTAFIXBootloader.supportsTarget("t-echo"))
		#expect(OTAFIXBootloader.supportsTarget("tracker-t1000-e"))
		// …and products that share a build target but have no OTAFIX bootloader
		// stay excluded (they'd refuse at Board-ID resolution anyway).
		#expect(!OTAFIXBootloader.supportsTarget("canaryone"))
		#expect(!OTAFIXBootloader.supportsTarget("tbeam"))
		#expect(!OTAFIXBootloader.supportsTarget(""))
	}

	// MARK: - Digest verification

	@Test func checksumMatchGatesTheImage() {
		let data = Data("meshtastic".utf8)
		// SHA-256 of "meshtastic"
		let good = MaintenanceUF2(
			url: URL(string: "https://example.invalid/a.uf2")!,
			fileName: "a.uf2",
			sha256: "eb5cb6dab3bf5bf095a9173a0491a63abb8889dc20f808d5245399017a5ac03d"
		)
		let bad = MaintenanceUF2(
			url: URL(string: "https://example.invalid/a.uf2")!,
			fileName: "a.uf2",
			sha256: String(repeating: "0", count: 64)
		)
		#expect(good.matches(data))
		#expect(!bad.matches(data))
		#expect(!good.matches(Data("meshtastic2".utf8)))
	}
}
