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
