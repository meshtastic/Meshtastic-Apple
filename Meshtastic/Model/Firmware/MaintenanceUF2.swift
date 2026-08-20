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
//  edit in `meshtastic/api`, not a hand-edit in every client. This still gates an
//  irreversible write, so a fetched response is trusted only when its raw bytes
//  hash to `OTAFIXBootloader.expectedManifestSHA256` — a mismatch (stale pin,
//  compromised/misconfigured server) keeps whatever was already trusted and never
//  adopts the new bytes. See OTAFIXManifestStore below.
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
	/// Lowercase hex SHA-256. The one hashing implementation every digest check in this file
	/// (per-image and per-manifest) goes through.
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
		let seed = Self.decodeSeed()
		_releaseTag = seed.otafixReleaseTag
		_imagesByBoardID = seed.imagesByBoardID()
		_supportedTargets = Set(seed.otafixSupportedTargets)
	}

	/// Decodes the bundled seed. A decode failure here would mean a corrupt build — the seed is a
	/// tool-generated, compile-time-constant payload — so this fails loudly rather than silently
	/// starting from an empty manifest, matching `MaintenanceUf2ManifestSeed.rawJSON`'s own
	/// fatalError posture for the same reason.
	private static func decodeSeed() -> MaintenanceUf2ManifestPayload {
		do {
			return try JSONDecoder().decode(MaintenanceUf2ManifestPayload.self, from: MaintenanceUf2ManifestSeed.rawJSON)
		} catch {
			fatalError("MaintenanceUf2ManifestSeed.rawJSON failed to decode: \(error)")
		}
	}

	/// Verifies `rawBytes` against `expectedSHA256` and, only on a match, replaces the live
	/// manifest. Returns whether it was applied. A mismatch or decode failure is a no-op — the
	/// store keeps whatever it already trusted (the bundled seed, or an earlier successful fetch).
	@discardableResult
	func apply(rawBytes: Data, expectedSHA256: String) -> Bool {
		guard rawBytes.sha256Hex == expectedSHA256 else {
			Logger.services.warning("maintenanceUf2 manifest digest mismatch — ignoring fetched response")
			return false
		}
		guard let decoded = try? JSONDecoder().decode(MaintenanceUf2ManifestPayload.self, from: rawBytes) else {
			Logger.services.warning("maintenanceUf2 manifest digest matched but decode failed — ignoring")
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

	/// Pinned SHA-256 of `api.meshtastic.org/resource/maintenanceUf2`'s raw response bytes,
	/// matching `MaintenanceUf2ManifestSeed.rawJSON`'s digest exactly (asserted by
	/// `MaintenanceUf2ManifestSeedTests`). A fetch whose bytes don't hash to this is rejected by
	/// `OTAFIXManifestStore.apply` — bump this alongside a bundled-seed update, never separately.
	static let expectedManifestSHA256 = "73315bced19dc4ed31029a6c734b24420c96673f1666b9d046f96b55f629dc10"

	/// Release the currently-active pinned images were audited against.
	static var releaseTag: String { OTAFIXManifestStore.shared.releaseTag }

	/// Self-update images keyed by the Board-ID the device reports. Backed by
	/// `OTAFIXManifestStore`, seeded from the bundled manifest and updatable by a verified fetch
	/// from `resource/maintenanceUf2` — see `MeshtasticAPI.refreshMaintenanceUf2APIData()`.
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
