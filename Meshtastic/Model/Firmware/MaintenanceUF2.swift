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
//  The pairings themselves no longer live here or in Android's Kotlin — both now
//  read `GET https://api.meshtastic.org/resource/maintenanceUf2`, seeded from
//  MaintenanceUf2ManifestSeed's bundled copy so a new OTAFIX release is one JSON
//  edit in `meshtastic/api`, not a hand-edit in every client. A fetch that fails
//  or doesn't decode is a no-op that keeps whatever manifest was already loaded.
//  See OTAFIXManifestStore below.
//

import CryptoKit
import Foundation
import OSLog

struct MaintenanceUF2: Sendable, Equatable {
	let url: URL
	let fileName: String
	/// Lowercase hex SHA-256 of the exact bytes at `url`.
	let sha256: String

	/// True when `data` hashes to the pinned digest. Any mismatch means the
	/// upstream bytes changed (or the download was tampered with) and the image
	/// must not be written.
	func matches(_ data: Data) -> Bool {
		data.sha256Hex == sha256
	}
}

extension Data {
	/// Lowercase hex SHA-256. What `MaintenanceUF2.matches(_:)` checks a downloaded image against.
	var sha256Hex: String {
		SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
	}
}

/// Decodes `resource/maintenanceUf2`'s JSON shape. Deliberately omits `manifestVersion` and
/// `erase` — this branch has no factory-erase flow yet, so there is nothing to wire it to, and an
/// undeclared key is simply ignored by `JSONDecoder` rather than needing an optional placeholder.
private struct MaintenanceUf2ManifestPayload: Decodable {
	struct Asset: Decodable {
		// OTAFIX's own release-asset board slug (e.g. "wiscore_rak4631_board") — deliberately NOT
		// named the same as Meshtastic's platformioTarget (e.g. "rak4631", in
		// otafixSupportedTargets below): the two vocabularies differ per board, and a shared name
		// here would invite exactly the confusion this file's own doc comments already spell out.
		let otafixBoardSlug: String
		let sha256: String
	}

	let otafixReleaseTag: String
	let otafixBase: String
	let otafixByBoardId: [String: Asset]
	let otafixSupportedTargets: [String]

	/// Builds the board-ID keyed image map, deriving each release asset's filename/URL from
	/// `otafixBase` + `otafixReleaseTag` the same way Android's `otafixAsset()` does — the JSON
	/// stores the digest and board slug per row, not a repeated URL.
	func imagesByBoardID() -> [String: MaintenanceUF2] {
		var result: [String: MaintenanceUF2] = [:]
		for (boardID, asset) in otafixByBoardId {
			let name = "update-\(asset.otafixBoardSlug)_bootloader-\(otafixReleaseTag)_nosd.uf2"
			guard let url = URL(string: "\(otafixBase)/\(name)") else { continue }
			result[boardID] = MaintenanceUF2(url: url, fileName: name, sha256: asset.sha256)
		}
		return result
	}

	/// Structural validation, not content pinning: the fetch is trusted the same way the
	/// firmware downloads are, but a payload that could produce an unsafe write path, a
	/// non-HTTPS download, or an unverifiable digest is refused wholesale and the store
	/// keeps what it had.
	var isStructurallyValid: Bool {
		guard !otafixReleaseTag.isEmpty,
			  otafixBase.hasPrefix("https://"),
			  !otafixByBoardId.isEmpty,
			  !otafixSupportedTargets.isEmpty else { return false }
		let safeSlug = { (slug: String) -> Bool in
			!slug.isEmpty && slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
		}
		let safeTag = !otafixReleaseTag.contains("/") && !otafixReleaseTag.contains("..")
		guard safeTag else { return false }
		return otafixByBoardId.values.allSatisfy { asset in
			safeSlug(asset.otafixBoardSlug)
				&& asset.sha256.count == 64
				&& asset.sha256.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) }
		}
	}
}

/// Thread-safe, mutable holder for the maintenance-UF2 manifest (currently: the OTAFIX board map
/// and its UX-gate target set). `OTAFIXBootloader`'s public API stays synchronous — it's called
/// from `BootloaderUpgradeView`'s non-async `fileImporter` completion handler — so this is a
/// lock-protected class rather than an actor, matching `MeshtasticAPI`'s own `@unchecked Sendable`
/// + manual-synchronization precedent instead of introducing a second concurrency style.
final class OTAFIXManifestStore: @unchecked Sendable {
	static let shared = OTAFIXManifestStore()

	private let lock = NSLock()
	private var _releaseTag: String
	private var _imagesByBoardID: [String: MaintenanceUF2]
	private var _supportedTargets: Set<String>

	private init() {
		_releaseTag = OTAFIXBootloader.bundledReleaseTag
		_imagesByBoardID = OTAFIXBootloader.bundledImagesByBoardID
		_supportedTargets = OTAFIXBootloader.bundledSupportedTargets
	}

	/// Decodes and validates `rawBytes` and, only then, replaces the live manifest. Returns
	/// whether it was applied. A decode or validation failure is a no-op — the store keeps
	/// whatever it already had (the bundled audited map, or an earlier successful fetch).
	@discardableResult
	func apply(rawBytes: Data) -> Bool {
		guard let decoded = try? JSONDecoder().decode(MaintenanceUf2ManifestPayload.self, from: rawBytes) else {
			Logger.services.warning("maintenanceUf2 manifest decode failed — ignoring")
			return false
		}
		guard decoded.isStructurallyValid else {
			Logger.services.warning("maintenanceUf2 manifest failed validation — ignoring")
			return false
		}
		lock.lock()
		_releaseTag = decoded.otafixReleaseTag
		_imagesByBoardID = decoded.imagesByBoardID()
		_supportedTargets = Set(decoded.otafixSupportedTargets)
		lock.unlock()
		return true
	}

	var releaseTag: String {
		lock.lock(); defer { lock.unlock() }
		return _releaseTag
	}

	var supportedTargets: Set<String> {
		lock.lock(); defer { lock.unlock() }
		return _supportedTargets
	}

	func image(forBoardID boardID: String) -> MaintenanceUF2? {
		lock.lock(); defer { lock.unlock() }
		return _imagesByBoardID[boardID]
	}

	#if DEBUG
	/// Test-only: the store is a process-wide singleton; suites that apply payloads
	/// restore the bundled seed so other suites read stable data.
	func resetToBundledSeedForTesting() {
		lock.lock(); defer { lock.unlock() }
		_releaseTag = OTAFIXBootloader.bundledReleaseTag
		_imagesByBoardID = OTAFIXBootloader.bundledImagesByBoardID
		_supportedTargets = OTAFIXBootloader.bundledSupportedTargets
	}
	#endif

	var imagesByBoardID: [String: MaintenanceUF2] {
		lock.lock(); defer { lock.unlock() }
		return _imagesByBoardID
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

	// MARK: Bundled audited seed
	//
	// The map the app ships with — human-readable, reviewable row by row, and pinned by
	// the fixture tests. Mirrored verbatim from Meshtastic-Android's MaintenanceUf2.kt
	// and re-verified against the release assets. The API refresh can only replace it
	// with a payload that passes structural validation.

	static let bundledReleaseTag = "0.9.2-OTAFIX2.3-BP1.5"

	private static let bundledBase =
		"https://github.com/meshtastic/Adafruit_nRF52_Bootloader_OTAFIX/releases/download/\(bundledReleaseTag)"

	private static func asset(board: String, sha256: String) -> MaintenanceUF2 {
		let name = "update-\(board)_bootloader-\(bundledReleaseTag)_nosd.uf2"
		// Force-unwrap is safe: compile-time constants forming a valid URL, covered row
		// by row by the audited-fixture tests.
		return MaintenanceUF2(url: URL(string: "\(bundledBase)/\(name)")!, fileName: name, sha256: sha256)
	}

	static let bundledImagesByBoardID: [String: MaintenanceUF2] = [
		"HT-n5262": asset(board: "heltec_t114", sha256: "ae92d3577cb58dd9b43c9b61ffb9bfffda05b0eca4113a0ec42a37cd8be53b19"),
		"MinewSemi-MX25LE01": asset(board: "minewsemi_mx25le01", sha256: "e09564fd8dd03fc25d76dcb732a0214c79653da3b130240949b783254d3dfc1b"),
		"TRACKER L1": asset(board: "wio_tracker_l1", sha256: "70fbce0eda9d70d7bd8a4367057badf5ec310838bf3221370d45a56f04956b9e"),
		"WisBlock-RAK4631-Board": asset(board: "wiscore_rak4631_board", sha256: "8741bc677a3c24f28422c5ffb80761de7d98a127a3b0191ba6585bf57ce9f305"),
		"WisMesh-Tag": asset(board: "wismesh_tag", sha256: "96d42e1990e17251e8c625e98a1551cac12c6e29111bc2e59ab7c9fe6dec8758"),
		"nRF52840-SeeedSenseCAPSolarP1-v1": asset(board: "sensecap_solar_p1", sha256: "9b4bce48c1b4830617715c5619457bce6b21f3079803e35e13433de7701290f5"),
		"nRF52840-SeeedXiao-v1": asset(board: "xiao_nrf52840_ble", sha256: "ff8a0916e98cceb394fd66590bccc17f63612c11ff56b086ef88bd436c8df67f"),
		"nRF52840-SeeedXiaoSense-v1": asset(board: "xiao_nrf52840_ble_sense", sha256: "fc233d83a1011419625fcb50b49084578460c25bbc0270374ca176757a3c40da"),
		"nRF52840-T1000-E-v1": asset(board: "t1000_e", sha256: "5c065e11b8acd5b0cefa9295f98bca1512306cfa478856aa76a871124a904cc4"),
		"nRF52840-TEcho-v1": asset(board: "lilygo_techo", sha256: "2ddb36188ffe521c270bb2ce8441d742d0fe45325c57e4db6475bf63162a59b0"),
		"nRF52840-ThinkNode-M3-v1": asset(board: "thinknode_m3", sha256: "bf90979f2f6adc96ef6ca09c280b2ab7e66cb8ce2654fc80da9b20407bfb8708"),
		"nRF52840-ThinkNodeM1-v1": asset(board: "thinknode_m1", sha256: "aa0721b573c60e0b179274d5a5296bac7a8436faf339cfc03116ebe8a4375795"),
		"nRF52840-ThinkNodeM6-v1": asset(board: "thinknode_m6", sha256: "aaf94953a540a18f3e48f4cdec0c78290ad3c5f8740aea26fa3b3ce3632a8d4a"),
		"nRF52840-promicro": asset(board: "promicro_nrf52840", sha256: "46ef3440f151d6f2606075bcd1aa83db25a660da7d25b988aeb47ef350c98794")
	]

	static let bundledSupportedTargets: Set<String> = [
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

	// MARK: Live accessors (store-backed)

	/// Release the currently-active pinned images were audited against.
	static var releaseTag: String { OTAFIXManifestStore.shared.releaseTag }

	/// Self-update images keyed by the Board-ID the device reports. Backed by
	/// `OTAFIXManifestStore`, seeded from the bundled manifest and updatable by a fetch from
	/// `resource/maintenanceUf2` — see `MeshtasticAPI.refreshMaintenanceUf2APIData()`.
	static var imagesByBoardID: [String: MaintenanceUF2] { OTAFIXManifestStore.shared.imagesByBoardID }

	/// Meshtastic platformio targets whose products OTAFIX lists as supported.
	///
	/// A UX gate only — it decides whether the upgrade action is offered, never
	/// which image is written. Deliberately excludes products that merely share
	/// a build target with a supported one (WISMESH Hub/Tap, Nomadstar Meteor
	/// Pro, RAK3401, T-Echo Plus/Lite): OTAFIX ships no bootloader for them, and
	/// their Board-IDs will refuse at resolution anyway.
	static var supportedTargets: Set<String> { OTAFIXManifestStore.shared.supportedTargets }

	static func supportsTarget(_ platformioTarget: String) -> Bool {
		OTAFIXManifestStore.shared.supportedTargets.contains(platformioTarget.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	/// The image matching the Board-ID a device reported, or nil when
	/// unrecognized. Nil refuses the upgrade: an unrecognized Board-ID means the
	/// installed bootloader is not one we have a verified pairing for, and
	/// writing a bootloader built for other hardware is unrecoverable without a
	/// debug probe.
	static func image(forBoardID boardID: String) -> MaintenanceUF2? {
		OTAFIXManifestStore.shared.image(forBoardID: boardID.trimmingCharacters(in: .whitespaces))
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
