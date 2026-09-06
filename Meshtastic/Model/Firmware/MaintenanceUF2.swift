//
//  MaintenanceUF2.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/26.
//
//  A pinned, content-verified UF2 image used by a maintenance flow (bootloader
//  upgrade). Unlike release firmware, these images have no versioned upstream
//  the app can resolve against, so each one is pinned to an exact URL and
//  SHA-256 digest, and the digest is verified before the image is ever offered
//  for writing. Mirrors Meshtastic-Android's MaintenanceUf2.kt so both apps
//  ship the same audited pairings.
//

import CryptoKit
import Foundation

struct MaintenanceUF2: Sendable, Equatable {
	let url: URL
	let fileName: String
	/// Lowercase hex SHA-256 of the exact bytes at `url`.
	let sha256: String

	/// True when `data` hashes to the pinned digest. Any mismatch means the
	/// upstream bytes changed (or the download was tampered with) and the image
	/// must not be written.
	func matches(_ data: Data) -> Bool {
		let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
		return digest == sha256
	}
}

/// nRF52 factory erase from the bootloader drive. Works with no running firmware,
/// which is what makes it the recovery path for a radio that cannot boot.
///
/// Two paths, chosen by what the drive reports in INFO_UF2.TXT:
///
/// - A bootloader that prints `Factory-Erase: UF2 family 0x4D455348` erases its own
///   App Data region (settings, keys, BLE bonds, node database) when a UF2 block with
///   that family ID lands on the drive. One board-agnostic file; the installed
///   firmware is kept and boots factory-fresh.
/// - Older bootloaders run a tiny erase image once, wiping the application flash and
///   settings region and leaving only the SoftDevice and bootloader. The two images
///   are linked for different application start addresses (S140 6.1.1 apps begin at
///   0x26000, S140 7.3.0 at 0x27000), and writing the wrong one erases part of the
///   SoftDevice itself — so the image is selected only by the `SoftDevice:` line, read
///   from the chip's MBR, and the bytes are cross-checked against the expected start
///   address before writing, the one authoring mistake a digest alone cannot catch.
///
/// Mirrors Meshtastic-Android's MaintenanceUf2.kt so both apps ship the same pairings.
enum NRF52FactoryErase {

	enum SoftDeviceVariant: String, Sendable {
		case s140_6_1_1 = "6.1.1"
		case s140_7_3_0 = "7.3.0"
	}

	/// Commit-pinned base for the factory-erase images checked into
	/// `meshtastic/web-flasher` at `public/uf2/` (built from
	/// `meshtastic/nrf52_factory_erase`, GPL-3.0). The blobs have not changed since
	/// 2024-09-03, so the pin is cheap to hold — same images Android ships.
	private static let eraseBase =
		"https://raw.githubusercontent.com/meshtastic/web-flasher/0e353b5d0756c9a1b76f53be78e948fafc1ebd8a/public/uf2"

	/// The flash address the image's first UF2 block writes to, checked against the
	/// resolved SoftDevice before writing.
	static let appStartS140_6_1_1: UInt32 = 0x26000
	static let appStartS140_7_3_0: UInt32 = 0x27000

	static let imageS140_6_1_1 = MaintenanceUF2(
		url: URL(string: "\(eraseBase)/nrf_erase2.uf2")!,
		fileName: "nrf_erase2.uf2",
		sha256: "4b778a3def19854415db64cb51bfd29c15b11cc46006353dd518f62d09efe3fe"
	)

	static let imageS140_7_3_0 = MaintenanceUF2(
		url: URL(string: "\(eraseBase)/nrf_erase_sd7_3.uf2")!,
		fileName: "nrf_erase_sd7_3.uf2",
		sha256: "13941bedce009e61255c37b1524d11ca604e88c38e7588bb8b391e2998da468f"
	)

	static func image(for variant: SoftDeviceVariant) -> MaintenanceUF2 {
		switch variant {
		case .s140_6_1_1: return imageS140_6_1_1
		case .s140_7_3_0: return imageS140_7_3_0
		}
	}

	static func expectedFirstTargetAddress(for variant: SoftDeviceVariant) -> UInt32 {
		switch variant {
		case .s140_6_1_1: return appStartS140_6_1_1
		case .s140_7_3_0: return appStartS140_7_3_0
		}
	}

	/// Extracts the installed SoftDevice from INFO_UF2.TXT contents. The bootloader
	/// emits `SoftDevice: S140 7.3.0` read out of the MBR — the authoritative answer
	/// to which SoftDevice is actually in flash. Nil when the line is absent (a very
	/// old bootloader), the id is not S140, or the version is not one we ship an
	/// erase image for — every one of which refuses the erase rather than guessing.
	static func parseSoftDevice(fromInfoText text: String) -> SoftDeviceVariant? {
		for line in text.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.lowercased().hasPrefix("softdevice:") else { continue }
			let value = trimmed.dropFirst("softdevice:".count).trimmingCharacters(in: .whitespaces)
			let parts = value.split(separator: " ").filter { !$0.isEmpty }
			guard parts.count >= 2, parts[0].uppercased() == "S140" else { return nil }
			return SoftDeviceVariant(rawValue: String(parts[1]))
		}
		return nil
	}

	/// Reads the target flash address of the first UF2 block, or nil when the payload
	/// is not a UF2 image. Blocks are 512 bytes: magic 0x0A324655 at offset 0,
	/// little-endian target address at offset 12.
	static func uf2FirstTargetAddress(_ bytes: Data) -> UInt32? {
		guard bytes.count >= 512, le32(bytes, at: 0) == uf2Magic0 else { return nil }
		return le32(bytes, at: 12)
	}

	// MARK: - Bootloader-run erase

	/// The UF2 family ID the bootloader's built-in factory erase listens for ("MESH").
	static let bootloaderEraseFamilyID: UInt32 = 0x4D45_5348

	/// One 512-byte block for every nRF52 board whose bootloader reports
	/// `Factory-Erase:`. The `meshtastic_factory_erase.uf2` asset of OTAFIX release
	/// 0.9.2-OTAFIX2.4 (MIT).
	static let bootloaderImage = MaintenanceUF2(
		url: URL(string: "https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/0.9.2-OTAFIX2.4/meshtastic_factory_erase.uf2")!,
		fileName: "meshtastic_factory_erase.uf2",
		sha256: "6ef3146505c40079ee9e7e692448e40a793dad636f55d1545063299d28908f0d"
	)

	/// Extracts the family ID from the `Factory-Erase: UF2 family 0x4D455348` line the
	/// bootloader emits in INFO_UF2.TXT — the last `0x` token on the line. Nil when
	/// the line is absent (every bootloader before the feature) or carries no hex
	/// value; the caller then falls back to the SoftDevice-specific images.
	static func parseFactoryEraseFamily(fromInfoText text: String) -> UInt32? {
		for line in text.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.lowercased().hasPrefix("factory-erase:") else { continue }
			let tokens = trimmed.dropFirst("factory-erase:".count)
				.split(whereSeparator: \.isWhitespace)
				.filter { $0.lowercased().hasPrefix("0x") }
			guard let last = tokens.last else { return nil }
			return UInt32(last.dropFirst(2), radix: 16)
		}
		return nil
	}

	/// Reads the family ID of a UF2 block, or nil when the bytes are not a UF2 block
	/// that carries one: magic 0x0A324655 at offset 0, the family-ID-present flag
	/// (0x2000) at offset 8, little-endian family ID at offset 28.
	static func uf2FamilyID(_ bytes: Data) -> UInt32? {
		guard bytes.count >= 32, le32(bytes, at: 0) == uf2Magic0, le32(bytes, at: 8) & 0x2000 != 0 else { return nil }
		return le32(bytes, at: 28)
	}

	private static let uf2Magic0: UInt32 = 0x0A32_4655

	private static func le32(_ bytes: Data, at offset: Int) -> UInt32 {
		bytes.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian
	}
}

/// OTAFIX bootloader self-update images and the rules for resolving one safely.
///
/// The safety contract, unchanged from Android: the **Board-ID the device itself
/// reports** (in `INFO_UF2.TXT` on its mass-storage volume) is the only input
/// that selects an image. Product names cannot be correlated between the two
/// projects (`heltec_t114` vs `heltec-mesh-node-t114`), USB VID/PID collide
/// across boards, and the XIAO nRF52840 BLE / BLE Sense split differs *only* by
/// Board-ID — installing the wrong one over UF2 is unrecoverable without SWD.
/// The connected node's platformio target is a UX gate only: it decides whether
/// the upgrade is offered, never which image is written.
enum OTAFIXBootloader {

	/// Release the pinned images below were audited against.
	static let releaseTag = "0.9.2-OTAFIX2.3-BP1.5"

	private static let releaseBase =
		"https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/\(releaseTag)"

	private static func asset(board: String, sha256: String) -> MaintenanceUF2 {
		let name = "update-\(board)_bootloader-\(releaseTag)_nosd.uf2"
		// Force-unwrap is safe: releaseBase and every board string are
		// compile-time constants that form a valid URL, and the tests cover
		// every row in the map.
		return MaintenanceUF2(url: URL(string: "\(releaseBase)/\(name)")!, fileName: name, sha256: sha256)
	}

	/// Self-update images keyed by the Board-ID the device reports. Rows are
	/// mirrored verbatim from Meshtastic-Android's `OTAFIX_BY_BOARD_ID`
	/// (MaintenanceUf2.kt) so both apps ship the same audited pairings.
	static let imagesByBoardID: [String: MaintenanceUF2] = [
		"HT-n5262": asset(
			board: "heltec_t114",
			sha256: "ae92d3577cb58dd9b43c9b61ffb9bfffda05b0eca4113a0ec42a37cd8be53b19"
		),
		"MinewSemi-MX25LE01": asset(
			board: "minewsemi_mx25le01",
			sha256: "e09564fd8dd03fc25d76dcb732a0214c79653da3b130240949b783254d3dfc1b"
		),
		"TRACKER L1": asset(
			board: "wio_tracker_l1",
			sha256: "70fbce0eda9d70d7bd8a4367057badf5ec310838bf3221370d45a56f04956b9e"
		),
		"WisBlock-RAK4631-Board": asset(
			board: "wiscore_rak4631_board",
			sha256: "8741bc677a3c24f28422c5ffb80761de7d98a127a3b0191ba6585bf57ce9f305"
		),
		"WisMesh-Tag": asset(
			board: "wismesh_tag",
			sha256: "96d42e1990e17251e8c625e98a1551cac12c6e29111bc2e59ab7c9fe6dec8758"
		),
		"nRF52840-SeeedSenseCAPSolarP1-v1": asset(
			board: "sensecap_solar_p1",
			sha256: "9b4bce48c1b4830617715c5619457bce6b21f3079803e35e13433de7701290f5"
		),
		"nRF52840-SeeedXiao-v1": asset(
			board: "xiao_nrf52840_ble",
			sha256: "ff8a0916e98cceb394fd66590bccc17f63612c11ff56b086ef88bd436c8df67f"
		),
		"nRF52840-SeeedXiaoSense-v1": asset(
			board: "xiao_nrf52840_ble_sense",
			sha256: "fc233d83a1011419625fcb50b49084578460c25bbc0270374ca176757a3c40da"
		),
		"nRF52840-T1000-E-v1": asset(
			board: "t1000_e",
			sha256: "5c065e11b8acd5b0cefa9295f98bca1512306cfa478856aa76a871124a904cc4"
		),
		"nRF52840-TEcho-v1": asset(
			board: "lilygo_techo",
			sha256: "2ddb36188ffe521c270bb2ce8441d742d0fe45325c57e4db6475bf63162a59b0"
		),
		"nRF52840-ThinkNode-M3-v1": asset(
			board: "thinknode_m3",
			sha256: "bf90979f2f6adc96ef6ca09c280b2ab7e66cb8ce2654fc80da9b20407bfb8708"
		),
		"nRF52840-ThinkNodeM1-v1": asset(
			board: "thinknode_m1",
			sha256: "aa0721b573c60e0b179274d5a5296bac7a8436faf339cfc03116ebe8a4375795"
		),
		"nRF52840-ThinkNodeM6-v1": asset(
			board: "thinknode_m6",
			sha256: "aaf94953a540a18f3e48f4cdec0c78290ad3c5f8740aea26fa3b3ce3632a8d4a"
		),
		"nRF52840-promicro": asset(
			board: "promicro_nrf52840",
			sha256: "46ef3440f151d6f2606075bcd1aa83db25a660da7d25b988aeb47ef350c98794"
		)
	]

	/// Meshtastic platformio targets whose products OTAFIX lists as supported.
	///
	/// A UX gate only — it decides whether the upgrade action is offered, never
	/// which image is written. Deliberately excludes products that merely share
	/// a build target with a supported one (WISMESH Hub/Tap, Nomadstar Meteor
	/// Pro, RAK3401, T-Echo Plus/Lite): OTAFIX ships no bootloader for them, and
	/// their Board-IDs will refuse at resolution anyway.
	static let supportedTargets: Set<String> = [
		"rak4631",
		"rak_wismeshtag",
		"t-echo",
		"heltec-mesh-node-t114",
		"nrf52_promicro_diy_tcxo",
		"thinknode_m1",
		"thinknode_m3",
		"thinknode_m6",
		"tracker-t1000-e",
		"seeed_wio_tracker_L1",
		"seeed_wio_tracker_L1_eink",
		"seeed_solar_node",
		"seeed_xiao_nrf52840_kit"
	]

	static func supportsTarget(_ platformioTarget: String) -> Bool {
		supportedTargets.contains(platformioTarget.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	/// The image matching the Board-ID a device reported, or nil when
	/// unrecognized. Nil refuses the upgrade: an unrecognized Board-ID means the
	/// installed bootloader is not one we have a verified pairing for, and
	/// writing a bootloader built for other hardware is unrecoverable without a
	/// debug probe.
	static func image(forBoardID boardID: String) -> MaintenanceUF2? {
		imagesByBoardID[boardID.trimmingCharacters(in: .whitespaces)]
	}

	/// The file every Adafruit-family UF2 bootloader exposes on its volume.
	static let infoFileName = "INFO_UF2.TXT"

	/// Extracts the `Board-ID:` value from `INFO_UF2.TXT` contents. Format is
	/// fixed by the bootloader's ghostfat.c: CRLF-separated lines of
	/// `UF2 Bootloader <ver>` / `Model: <name>` / `Board-ID: <id>` / `Date: …`.
	/// Nil means the volume is not a UF2 bootloader drive — itself a reason to
	/// refuse the write.
	static func parseBoardID(fromInfoText text: String) -> String? {
		for line in text.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.lowercased().hasPrefix("board-id:") else { continue }
			let value = trimmed.dropFirst("board-id:".count).trimmingCharacters(in: .whitespaces)
			return value.isEmpty ? nil : value
		}
		return nil
	}
}
