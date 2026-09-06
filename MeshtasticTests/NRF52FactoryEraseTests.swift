//
//  NRF52FactoryEraseTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 8/27/26.
//
//  Pins the factory-erase safety contract (#2336): the two erase images are
//  linked for different flash addresses, and writing the wrong one erases part
//  of the SoftDevice — so the image is selected only by the SoftDevice the
//  drive reports, and the bytes are cross-checked against the expected start
//  address. Digests re-verified against the commit-pinned web-flasher files.
//
//  Also pins the bootloader-run erase: one block for every board, selected only
//  by the Factory-Erase line the drive reports and cross-checked by UF2 family
//  ID instead of start address (its target address is 0).
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("nRF52 factory erase")
struct NRF52FactoryEraseTests {

	@Test func pinnedImagesMatchTheAuditedFixture() {
		let s140611 = NRF52FactoryErase.image(for: .s140_6_1_1)
		#expect(s140611.fileName == "nrf_erase2.uf2")
		#expect(s140611.sha256 == "4b778a3def19854415db64cb51bfd29c15b11cc46006353dd518f62d09efe3fe")
		#expect(NRF52FactoryErase.expectedFirstTargetAddress(for: .s140_6_1_1) == 0x26000)

		let s140730 = NRF52FactoryErase.image(for: .s140_7_3_0)
		#expect(s140730.fileName == "nrf_erase_sd7_3.uf2")
		#expect(s140730.sha256 == "13941bedce009e61255c37b1524d11ca604e88c38e7588bb8b391e2998da468f")
		#expect(NRF52FactoryErase.expectedFirstTargetAddress(for: .s140_7_3_0) == 0x27000)

		#expect(s140611.url.absoluteString.hasPrefix("https://raw.githubusercontent.com/meshtastic/web-flasher/0e353b5d"), "commit-pinned, not a mutable path")
	}

	@Test func parsesTheCanonicalSoftDeviceLine() {
		let text = "UF2 Bootloader 0.9.2\r\nModel: T1000-E\r\nBoard-ID: nRF52840-T1000-E-v1\r\nSoftDevice: S140 7.3.0\r\nDate: Aug 1 2026\r\n"
		#expect(NRF52FactoryErase.parseSoftDevice(fromInfoText: text) == .s140_7_3_0)
		#expect(NRF52FactoryErase.parseSoftDevice(fromInfoText: "softdevice: s140 6.1.1\n") == .s140_6_1_1)
	}

	@Test func refusesAnythingButAKnownS140() {
		// No line at all: a bootloader too old to report it.
		#expect(NRF52FactoryErase.parseSoftDevice(fromInfoText: "Board-ID: X\r\n") == nil)
		// Not S140.
		#expect(NRF52FactoryErase.parseSoftDevice(fromInfoText: "SoftDevice: S113 7.3.0\r\n") == nil)
		// A version we ship no image for.
		#expect(NRF52FactoryErase.parseSoftDevice(fromInfoText: "SoftDevice: S140 8.0.0\r\n") == nil)
		// Unparseable value.
		#expect(NRF52FactoryErase.parseSoftDevice(fromInfoText: "SoftDevice:\r\n") == nil)
	}

	@Test func readsTheFirstTargetAddressFromARealUF2Header() {
		var block = Data(count: 512)
		// Magic 0x0A324655 little-endian, target address 0x26000 at offset 12.
		block.replaceSubrange(0..<4, with: [0x55, 0x46, 0x32, 0x0A])
		block.replaceSubrange(12..<16, with: [0x00, 0x60, 0x02, 0x00])
		#expect(NRF52FactoryErase.uf2FirstTargetAddress(block) == 0x26000)

		// Wrong magic is not a UF2.
		var bad = block
		bad.replaceSubrange(0..<4, with: [0x00, 0x00, 0x00, 0x00])
		#expect(NRF52FactoryErase.uf2FirstTargetAddress(bad) == nil)

		// Short payloads are not a UF2.
		#expect(NRF52FactoryErase.uf2FirstTargetAddress(Data(count: 100)) == nil)
	}

	// MARK: - Bootloader-run erase

	@Test func pinnedBootloaderImageMatchesTheContract() {
		let image = NRF52FactoryErase.bootloaderImage
		#expect(image.fileName == "meshtastic_factory_erase.uf2")
		#expect(image.sha256 == "6ef3146505c40079ee9e7e692448e40a793dad636f55d1545063299d28908f0d")
		#expect(image.url.lastPathComponent == image.fileName)
		#expect(image.url.absoluteString == "https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/0.9.2-OTAFIX2.4/meshtastic_factory_erase.uf2", "the OTAFIX 2.4 release asset")
		#expect(NRF52FactoryErase.bootloaderEraseFamilyID == 0x4D45_5348)
	}

	@Test func parsesTheCanonicalFactoryEraseLine() {
		let text = "UF2 Bootloader 0.9.2\r\nModel: T1000-E\r\nBoard-ID: nRF52840-T1000-E-v1\r\nSoftDevice: S140 7.3.0\r\nFactory-Erase: UF2 family 0x4D455348\r\nDate: Sep 1 2026\r\n"
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: text) == 0x4D45_5348)
		// Case and leading whitespace are tolerated, like the other parsers.
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "  factory-erase: uf2 family 0x4d455348\n") == 0x4D45_5348)
		// A different family still parses; the caller decides it is not ours.
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "Factory-Erase: UF2 family 0xADA52840\r\n") == 0xADA5_2840)
	}

	@Test func missingOrMalformedFactoryEraseLineIsNil() {
		// Every bootloader shipped before the line existed; the SoftDevice path applies.
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "Board-ID: X\r\nSoftDevice: S140 7.3.0\r\n") == nil)
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "") == nil)
		// No hex token.
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "Factory-Erase: UF2 family\r\n") == nil)
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "Factory-Erase:\r\n") == nil)
		// A 0x token that is not hex.
		#expect(NRF52FactoryErase.parseFactoryEraseFamily(fromInfoText: "Factory-Erase: UF2 family 0xMESH\r\n") == nil)
	}

	@Test func readsTheFamilyIDFromTheContractHeader() {
		// The single block meshtastic_factory_erase.uf2 is made of, per the OTAFIX contract.
		var block = Data(count: 512)
		block.replaceSubrange(0..<4, with: [0x55, 0x46, 0x32, 0x0A])     // magic0 0x0A324655
		block.replaceSubrange(4..<8, with: [0x57, 0x51, 0x5D, 0x9E])     // magic1 0x9E5D5157
		block.replaceSubrange(8..<12, with: [0x00, 0x20, 0x00, 0x00])    // flags: family ID present
		block.replaceSubrange(16..<20, with: [0x00, 0x01, 0x00, 0x00])   // payloadSize 256
		block.replaceSubrange(24..<28, with: [0x01, 0x00, 0x00, 0x00])   // numBlocks 1
		block.replaceSubrange(28..<32, with: [0x48, 0x53, 0x45, 0x4D])   // familyID 0x4D455348 "MESH"
		block.replaceSubrange(508..<512, with: [0x30, 0x6F, 0xB1, 0x0A]) // magicEnd 0x0AB16F30
		#expect(NRF52FactoryErase.uf2FamilyID(block) == 0x4D45_5348)
		#expect(NRF52FactoryErase.uf2FamilyID(block) == NRF52FactoryErase.bootloaderEraseFamilyID)
		// Its target address is 0, so the SoftDevice-path check must not be applied to it.
		#expect(NRF52FactoryErase.uf2FirstTargetAddress(block) == 0)

		// Flag cleared: the word at 28 is not a family ID.
		var noFamily = block
		noFamily.replaceSubrange(8..<12, with: [0x00, 0x00, 0x00, 0x00])
		#expect(NRF52FactoryErase.uf2FamilyID(noFamily) == nil)

		// Not a UF2 at all.
		#expect(NRF52FactoryErase.uf2FamilyID(Data("not a uf2 block".utf8)) == nil)
		#expect(NRF52FactoryErase.uf2FamilyID(Data(count: 512)) == nil)
	}
}
