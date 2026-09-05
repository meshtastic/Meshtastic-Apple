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
}
