//
//  MaintenanceUF2.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 8/19/26.
//
//  A content-verified UF2 image used by a maintenance flow (nRF52 factory erase,
//  OTAFIX bootloader upgrade). Unlike release firmware these images have no
//  versioned upstream the app can resolve against, so each one is paired with an
//  exact SHA-256 digest and the digest is verified before the image is ever
//  offered for writing.
//
//  The pairings no longer live here as compile-time constants. Both this app and
//  Meshtastic-Android read `GET https://api.meshtastic.org/resource/maintenanceUf2`,
//  so a new OTAFIX release is one JSON edit in `meshtastic/api` rather than a
//  hand-edit in every client — the hand-mirrored copy had already drifted two
//  releases behind and was missing five boards. What ships in the binary is a
//  bundled audited seed (below), replaced only by a fetched manifest that passes
//  structural validation. A fetch that fails, 404s or does not decode is a no-op
//  that keeps whatever manifest was already loaded.
//
//  See MaintenanceUf2ManifestStore, and MeshtasticAPI.refreshMaintenanceUf2APIData().
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

/// A factory-erase image plus the one header field that proves the row was authored
/// correctly. The digest proves the bytes; this proves the pairing — a swapped
/// filename/digest pair would still be internally consistent and still write a file
/// the drive cannot safely take.
///
/// Exactly one of the two is set per row, because the two erase paths have different
/// contracts: a SoftDevice-specific image is identified by the flash address its first
/// block writes to, and the board-agnostic bootloader-driven file by its UF2 family ID
/// (its target address is 0 by design, so an address check cannot apply to it).
struct EraseEntry: Sendable, Equatable {
	let image: MaintenanceUF2
	let expectedFirstTargetAddress: UInt32?
	let expectedFamilyID: UInt32?
}

/// The factory-erase rows of the manifest, resolved into images.
struct MaintenanceUf2EraseSet: Sendable, Equatable {
	/// Keyed by the SoftDevice version string the drive reports ("6.1.1", "7.3.0").
	let nrf52BySoftDevice: [String: EraseEntry]
	/// The board-agnostic file a bootloader that advertises `Factory-Erase:` consumes.
	let nrf52Bootloader: EraseEntry?
}

/// The only shape a manifest-supplied UF2 file name may take: a plain `<name>.uf2` of
/// unreserved characters.
///
/// Load-bearing rather than cosmetic. Every file name now arrives as a string from
/// `resource/maintenanceUf2` and is appended to the user-picked drive URL before the
/// write, so a row naming `../something` would write outside the drive. An allowlist
/// rather than a traversal blacklist: excluding separators outright makes `..` inert,
/// and nothing legitimate falls outside it. Same rule as Android's `SAFE_UF2_FILE_NAME`.
private let safeUf2FileName = /^[A-Za-z0-9._-]+\.uf2$/

private func isSafeUf2FileName(_ name: String) -> Bool {
	name.wholeMatch(of: safeUf2FileName) != nil
}

private func isLowercaseHexDigest(_ value: String) -> Bool {
	value.count == 64 && value.allSatisfy { $0.isHexDigit && (!$0.isLetter || $0.isLowercase) }
}

/// Decodes `resource/maintenanceUf2`'s JSON shape.
private struct MaintenanceUf2ManifestPayload: Decodable {

	struct Asset: Decodable {
		// OTAFIX's own release-asset board slug (e.g. "wiscore_rak4631_board") — deliberately NOT
		// named the same as Meshtastic's platformioTarget (e.g. "rak4631", in
		// otafixSupportedTargets below): the two vocabularies differ per board, and a shared name
		// here would invite exactly the confusion this file's own doc comments already spell out.
		let otafixBoardSlug: String
		let sha256: String
		/// Images keyed by platformioTarget for boards whose stock bootloader reports this row's
		/// Board-ID but need their own build (a stock Wio Tracker L1 Pro 1W reports `TRACKER L1`).
		let targetOverrides: [String: Override]?
	}

	struct Override: Decodable {
		let otafixBoardSlug: String
		let sha256: String
	}

	struct EraseRow: Decodable {
		let fileName: String
		let sha256: String
		let expectedFirstTargetAddress: UInt32?
		let expectedFamilyId: UInt32?
	}

	struct EraseSet: Decodable {
		let nrf52: [String: EraseRow]?
		let nrf52Bootloader: EraseRow?
		// rp2040 is decoded and ignored: this app has no RP2040 erase flow, and an undeclared
		// key would be dropped silently anyway. Named here only so the shape is documented.
		let rp2040: EraseRow?
	}

	let manifestVersion: Int
	let otafixReleaseTag: String
	let otafixBase: String
	let otafixByBoardId: [String: Asset]
	let otafixSupportedTargets: [String]
	let erase: EraseSet?

	/// Builds the board-ID keyed image map, deriving each release asset's filename/URL from
	/// `otafixBase` + `otafixReleaseTag` the same way Android's `otafixAsset()` does — the JSON
	/// stores the digest and board slug per row, not a repeated URL.
	func imagesByBoardID() -> [String: MaintenanceUF2] {
		var result: [String: MaintenanceUF2] = [:]
		for (boardID, asset) in otafixByBoardId {
			guard let image = image(slug: asset.otafixBoardSlug, sha256: asset.sha256) else { continue }
			result[boardID] = image
		}
		return result
	}

	/// Each row's `targetOverrides` as images, keyed by Board-ID then lowercased platformioTarget.
	func overrideImagesByBoardID() -> [String: [String: MaintenanceUF2]] {
		var result: [String: [String: MaintenanceUF2]] = [:]
		for (boardID, asset) in otafixByBoardId {
			for (target, override) in asset.targetOverrides ?? [:] {
				guard let image = image(slug: override.otafixBoardSlug, sha256: override.sha256) else { continue }
				result[boardID, default: [:]][target.lowercased()] = image
			}
		}
		return result
	}

	private func image(slug: String, sha256: String) -> MaintenanceUF2? {
		let name = "update-\(slug)_bootloader-\(otafixReleaseTag)_nosd.uf2"
		guard isSafeUf2FileName(name), let url = URL(string: "\(otafixBase)/\(name)") else { return nil }
		return MaintenanceUF2(url: url, fileName: name, sha256: sha256)
	}

	/// Resolves the erase rows into images served by the API's own asset route. A row whose
	/// file name fails the allowlist is dropped — refusing that one image, never the manifest.
	func eraseSet() -> MaintenanceUf2EraseSet {
		func entry(_ row: EraseRow?) -> EraseEntry? {
			guard let row, isSafeUf2FileName(row.fileName), isLowercaseHexDigest(row.sha256),
				  let url = URL(string: "\(MaintenanceUf2ManifestStore.eraseAssetBase)/\(row.fileName)") else {
				return nil
			}
			return EraseEntry(
				image: MaintenanceUF2(url: url, fileName: row.fileName, sha256: row.sha256),
				expectedFirstTargetAddress: row.expectedFirstTargetAddress,
				expectedFamilyID: row.expectedFamilyId
			)
		}
		var bySoftDevice: [String: EraseEntry] = [:]
		for (version, row) in erase?.nrf52 ?? [:] {
			// The start address belongs to the SoftDevice, not the manifest, so it is pinned in
			// code. A row for a SoftDevice we don't know, or whose address disagrees with the
			// pinned one, is dropped: the wrong image erases part of the SoftDevice.
			guard let variant = NRF52FactoryErase.SoftDeviceVariant(rawValue: version),
				  let resolved = entry(row),
				  resolved.expectedFirstTargetAddress == variant.applicationStartAddress else { continue }
			bySoftDevice[version] = resolved
		}
		// Likewise the bootloader row without a family ID: the family is the only contract that
		// proves those 512 bytes are the erase command and not something else.
		let bootloader = entry(erase?.nrf52Bootloader).flatMap { $0.expectedFamilyID == nil ? nil : $0 }
		return MaintenanceUf2EraseSet(nrf52BySoftDevice: bySoftDevice, nrf52Bootloader: bootloader)
	}

	/// Structural validation, not content pinning: the fetch is trusted the same way the
	/// firmware downloads are, but a payload that could produce an unsafe write path, a
	/// non-HTTPS download, or an unverifiable digest is refused wholesale and the store
	/// keeps what it had.
	var isStructurallyValid: Bool {
		guard manifestVersion == 1,
			  !otafixReleaseTag.isEmpty,
			  otafixBase.hasPrefix("https://"),
			  !otafixByBoardId.isEmpty,
			  !otafixSupportedTargets.isEmpty,
			  !otafixReleaseTag.contains("/"),
			  !otafixReleaseTag.contains("..") else {
			return false
		}
		let safeSlug = { (slug: String) -> Bool in
			!slug.isEmpty && slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
		}
		let overrides = otafixByBoardId.values.flatMap { ($0.targetOverrides ?? [:]).values }
		guard otafixByBoardId.values.allSatisfy({ safeSlug($0.otafixBoardSlug) && isLowercaseHexDigest($0.sha256) }),
			  // Checked as the file name it becomes, so an override that would be dropped later
			  // rejects the manifest instead of quietly falling back to the row's own image.
			  overrides.allSatisfy({
				  isSafeUf2FileName("update-\($0.otafixBoardSlug)_bootloader-\(otafixReleaseTag)_nosd.uf2")
					  && isLowercaseHexDigest($0.sha256)
			  })
		else {
			return false
		}
		// Every erase row that is present must be writable-safe and verifiable. A manifest with
		// no erase set at all is valid — the erase flow then simply has nothing to offer.
		let eraseRows = (erase?.nrf52.map { Array($0.values) } ?? []) + [erase?.nrf52Bootloader, erase?.rp2040].compactMap { $0 }
		return eraseRows.allSatisfy { isSafeUf2FileName($0.fileName) && isLowercaseHexDigest($0.sha256) }
	}
}

/// Thread-safe, mutable holder for the maintenance-UF2 manifest: the OTAFIX board map, its
/// UX-gate target set, and the factory-erase rows. `OTAFIXBootloader` and `NRF52FactoryErase`
/// keep synchronous APIs — both are called from non-async `fileImporter` completion handlers —
/// so this is a lock-protected class rather than an actor, matching `MeshtasticAPI`'s own
/// `@unchecked Sendable` + manual-synchronization precedent instead of introducing a second
/// concurrency style.
final class MaintenanceUf2ManifestStore: @unchecked Sendable {
	static let shared = MaintenanceUf2ManifestStore()

	/// Where the erase images themselves are served. The manifest carries a file name and a
	/// digest per row, not a URL — the images are vendored by `meshtastic/api` rather than
	/// fetched from a commit-pinned `raw.githubusercontent.com` path into web-flasher.
	static let eraseAssetBase = "https://api.meshtastic.org/resource/maintenanceUf2/asset"

	private let lock = NSLock()
	private var _releaseTag: String
	private var _imagesByBoardID: [String: MaintenanceUF2]
	private var _overrideImagesByBoardID: [String: [String: MaintenanceUF2]] = [:]
	private var _supportedTargets: Set<String>
	private var _eraseSet: MaintenanceUf2EraseSet
	private var lastRefreshAttempt: Date = .distantPast

	private init() {
		_releaseTag = OTAFIXBootloader.bundledReleaseTag
		_imagesByBoardID = OTAFIXBootloader.bundledImagesByBoardID
		_supportedTargets = OTAFIXBootloader.bundledSupportedTargets
		_eraseSet = NRF52FactoryErase.bundledEraseSet
	}

	/// Decodes and validates `rawBytes` and, only then, replaces the live manifest. Returns
	/// whether it was applied. A decode or validation failure is a no-op — the store keeps
	/// whatever it already had (the bundled audited seed, or an earlier successful fetch).
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
		_overrideImagesByBoardID = decoded.overrideImagesByBoardID()
		_supportedTargets = Set(decoded.otafixSupportedTargets)
		_eraseSet = decoded.eraseSet()
		lock.unlock()
		return true
	}

	/// Records a refresh attempt and returns whether one is due. Kept in memory with the manifest:
	/// a saved throttle would outlive the fetched manifest and keep a relaunched app on the seed.
	func claimRefreshAttempt(now: Date = Date()) -> Bool {
		lock.lock(); defer { lock.unlock() }
		guard MaintenanceUf2RefreshPolicy.shouldRefresh(lastAttempt: lastRefreshAttempt, now: now) else { return false }
		lastRefreshAttempt = now
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

	var imagesByBoardID: [String: MaintenanceUF2] {
		lock.lock(); defer { lock.unlock() }
		return _imagesByBoardID
	}

	var eraseSet: MaintenanceUf2EraseSet {
		lock.lock(); defer { lock.unlock() }
		return _eraseSet
	}

	/// The row's override for `platformioTarget` when it has one, else the row's own image.
	func image(forBoardID boardID: String, platformioTarget: String? = nil) -> MaintenanceUF2? {
		lock.lock(); defer { lock.unlock() }
		if let target = platformioTarget?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !target.isEmpty,
		   let override = _overrideImagesByBoardID[boardID]?[target] {
			return override
		}
		return _imagesByBoardID[boardID]
	}

	#if DEBUG
	/// Test-only: a fresh store seeded from the bundled map, isolated from `shared`.
	///
	/// Tests exercise `apply(rawBytes:)` against one of these rather than the singleton. Swift
	/// Testing runs suites in parallel, so mutating the process-wide store would race the suites
	/// that pin the seed's own rows — a flake that reports as a digest mismatch and reproduces
	/// only under load.
	static func isolatedForTesting() -> MaintenanceUf2ManifestStore {
		MaintenanceUf2ManifestStore()
	}
	#endif
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
/// A drive that advertises a `Factory-Erase:` family the manifest does not carry falls
/// through to the SoftDevice path rather than refusing — the same rule Android documents
/// on `MaintenanceVolume.factoryEraseFamily`, and safe because that path is separately
/// gated on a SoftDevice match, the digest, and the start-address cross-check.
enum NRF52FactoryErase {

	enum SoftDeviceVariant: String, Sendable, CaseIterable {
		case s140_6_1_1 = "6.1.1"
		case s140_7_3_0 = "7.3.0"

		/// Where the application region starts for this SoftDevice, and so the address the first
		/// block of its erase image must write to. Fixed by the SoftDevice's flash layout, so it
		/// stays in code rather than coming from the manifest.
		var applicationStartAddress: UInt32 {
			switch self {
			case .s140_6_1_1: 0x26000
			case .s140_7_3_0: 0x27000
			}
		}
	}

	// MARK: Bundled audited seed
	//
	// Transcribed from `resource/maintenanceUf2` and re-verified against the served assets.
	// Only the offline fallback: a successful fetch replaces it.

	private static func eraseAsset(fileName: String, sha256: String) -> MaintenanceUF2 {
		// Force-unwrap is safe: both components are compile-time constants forming a valid URL,
		// and the seed fixture tests assert every row round-trips.
		MaintenanceUF2(
			url: URL(string: "\(MaintenanceUf2ManifestStore.eraseAssetBase)/\(fileName)")!,
			fileName: fileName,
			sha256: sha256
		)
	}

	static let bundledEraseSet = MaintenanceUf2EraseSet(
		nrf52BySoftDevice: [
			"6.1.1": EraseEntry(
				image: eraseAsset(fileName: "nrf_erase2.uf2", sha256: "4b778a3def19854415db64cb51bfd29c15b11cc46006353dd518f62d09efe3fe"),
				expectedFirstTargetAddress: SoftDeviceVariant.s140_6_1_1.applicationStartAddress,
				expectedFamilyID: nil
			),
			"7.3.0": EraseEntry(
				image: eraseAsset(fileName: "nrf_erase_sd7_3.uf2", sha256: "13941bedce009e61255c37b1524d11ca604e88c38e7588bb8b391e2998da468f"),
				expectedFirstTargetAddress: SoftDeviceVariant.s140_7_3_0.applicationStartAddress,
				expectedFamilyID: nil
			)
		],
		nrf52Bootloader: EraseEntry(
			image: eraseAsset(
				fileName: "meshtastic_factory_erase.uf2",
				sha256: "6ef3146505c40079ee9e7e692448e40a793dad636f55d1545063299d28908f0d"
			),
			expectedFirstTargetAddress: nil,
			expectedFamilyID: 0x4D455348
		)
	)

	// MARK: Live accessors (store-backed)

	/// The erase row for a SoftDevice the drive reported, or nil when the manifest carries
	/// none. Nil refuses the erase: without the row there is no digest to verify against and
	/// no start address to cross-check, and guessing erases part of the SoftDevice.
	static func eraseEntry(for variant: SoftDeviceVariant) -> EraseEntry? {
		MaintenanceUf2ManifestStore.shared.eraseSet.nrf52BySoftDevice[variant.rawValue]
	}

	/// The board-agnostic bootloader-driven erase row, when the drive advertises the family
	/// the manifest expects.
	///
	/// Both sides must be present and equal. A bootloader advertising no family silently
	/// ignores the file (every bootloader before OTAFIX PR #41), and a row with no expected
	/// family cannot be verified against the bytes — so neither resolves here, and the caller
	/// falls through to the SoftDevice-specific path unchanged.
	static func bootloaderEraseEntry(forVolumeFamily volumeFamily: UInt32?) -> EraseEntry? {
		guard let volumeFamily, let entry = MaintenanceUf2ManifestStore.shared.eraseSet.nrf52Bootloader,
			  entry.expectedFamilyID == volumeFamily else {
			return nil
		}
		return entry
	}

	// MARK: INFO_UF2.TXT parsing and UF2 headers

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

	/// Reads the target flash address of the first UF2 block, or nil when the payload
	/// is not a UF2 image. Blocks are 512 bytes: magic 0x0A324655 at offset 0,
	/// little-endian target address at offset 12.
	static func uf2FirstTargetAddress(_ bytes: Data) -> UInt32? {
		guard bytes.count >= 512, le32(bytes, at: 0) == uf2Magic0 else { return nil }
		return le32(bytes, at: 12)
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
/// The connected node's platformio target decides whether the upgrade is offered,
/// and picks between images only where a Board-ID row lists `targetOverrides`.
enum OTAFIXBootloader {

	// MARK: Bundled audited seed
	//
	// The map the app ships with — human-readable, reviewable row by row, and pinned by the
	// fixture tests. Transcribed from `resource/maintenanceUf2` and spot-checked against the
	// release assets. The API refresh can only replace it with a payload that passes
	// structural validation.

	static let bundledReleaseTag = "2.6.1"

	private static let bundledBase =
		"https://github.com/meshtastic/nRF52_Bootloader/releases/download/\(bundledReleaseTag)"

	private static func asset(board: String, sha256: String) -> MaintenanceUF2 {
		let name = "update-\(board)_bootloader-\(bundledReleaseTag)_nosd.uf2"
		// Force-unwrap is safe: compile-time constants forming a valid URL, covered row
		// by row by the audited-fixture tests.
		return MaintenanceUF2(url: URL(string: "\(bundledBase)/\(name)")!, fileName: name, sha256: sha256)
	}

	static let bundledImagesByBoardID: [String: MaintenanceUF2] = [
		"HT-n5262": asset(
			board: "heltec_t114",
			sha256: "fa8e7efbccba744b1a4b3d4e91bffe88e41c105996b1808b84d6e24bf601f7d8"
		),
		"Heltec-T096-v1": asset(
			board: "heltec_t096",
			sha256: "527bc37852690686b6497e1065899148d8afcc2f8cdcd518f3f8dbd8f26584eb"
		),
		"Heltec-T1": asset(
			board: "heltec_t1",
			sha256: "407ae61720d6007d967a74e747ac31a1c96802d6effed811f9b4695f7ed49dce"
		),
		"MinewSemi-MX25LE01": asset(
			board: "minewsemi_mx25le01",
			sha256: "9a94b7d894b71c670cebd706d3a644ae4b5096c0e9289eb656d2d36e7298e84a"
		),
		"TRACKER L1": asset(
			board: "wio_tracker_l1",
			sha256: "14328aa2af2ede884d99e89b7a446bdd922c9d1b69b0f6c265f4e1f1fe1d4bc2"
		),
		"WisBlock-RAK3401-Board": asset(
			board: "wiscore_rak3401",
			sha256: "097de52d21f8b74a3a0faba1721655e801c532073880a4e00b71bed676bfef04"
		),
		"WisBlock-RAK4631-Board": asset(
			board: "wiscore_rak4631_board",
			sha256: "7df05403183a13bad75c216be956509566e427d84a5dbf157ab2f407ad76f61b"
		),
		"WisMesh-Tag": asset(
			board: "wismesh_tag",
			sha256: "0c5ae06d6672f4b9cfbcb7af92c58c13e7d51c872ab540b087297e1bd2a7d5fc"
		),
		"muzi-Base-Board": asset(
			board: "muzi_base",
			sha256: "2d9b63183a14b13b20bfb43d2fff5ed33632dae769e5e31b6884927505b379e6"
		),
		"nRF52840-MeshTracker-X1": asset(
			board: "mesh_tracker_x1",
			sha256: "1f42d23eb5b9f6152200e074c2be91a4b1e668de6da3090c8104874561ebf064"
		),
		"nRF52840-MeshTracker-X1-v1": asset(
			board: "mesh_tracker_x1",
			sha256: "1f42d23eb5b9f6152200e074c2be91a4b1e668de6da3090c8104874561ebf064"
		),
		"nRF52840-Meshtastic-Generic-S140v6": asset(
			board: "meshtastic_6.1.1",
			sha256: "20009bd55cde06f4d8f413eb83554db8182a5494a995ca4ff2856fddc4d25a20"
		),
		"nRF52840-Meshtastic-Generic-S140v7": asset(
			board: "meshtastic_7.3.0",
			sha256: "28d926742b47342a7c87bcc3cbb27c7eeb0eec9b983fd979f86c06061b8a6f30"
		),
		"nRF52840-SeeedSenseCAPSolarP1-v1": asset(
			board: "sensecap_solar_p1",
			sha256: "74ad71fbdc532fc070bc786c1338c4b8adbc8ae3c0baa5a91ae51250b412d95f"
		),
		"nRF52840-SeeedXiao-v1": asset(
			board: "xiao_nrf52840_ble",
			sha256: "2f6b164099ef0858a88d8f6432b70a76306cc6e6cd68788d62727a825f94f5ad"
		),
		"nRF52840-SeeedXiaoSense-v1": asset(
			board: "xiao_nrf52840_ble_sense",
			sha256: "188360565da4c2cab3f72de4508a9b8df21cfbe33ceda66c754d0f13ceacd292"
		),
		"nRF52840-T1000-E-v1": asset(
			board: "t1000_e",
			sha256: "54997a4fbd7b8560415e4fac54602d19abc23b717e92a405ba849f5db37b589c"
		),
		"nRF52840-TEcho-v1": asset(
			board: "lilygo_techo",
			sha256: "e8b6f1387000636dc694c63eef3f4de93c8f1f3845f1138bc96b3c4921eb26a3"
		),
		"nRF52840-ThinkNode-M3-v1": asset(
			board: "thinknode_m3",
			sha256: "8123f035ee12803679db37b331e714d8ebd0a8af57c9546a2dd47ea8aec05773"
		),
		"nRF52840-ThinkNodeM1-v1": asset(
			board: "thinknode_m1",
			sha256: "1e0c509b17689f3458676100201e277c74e18dd4bb47d44a738bb1e2a3dfc2c2"
		),
		"nRF52840-ThinkNodeM6-v1": asset(
			board: "thinknode_m6",
			sha256: "3fc3c5fcc0c7132e9e345477237aebc812e2e436e2daff006d2c0067b2df340d"
		),
		"nRF52840-WioTracker-L1-Pro-1W": asset(
			board: "wio_tracker_l1_pro_1w",
			sha256: "cc34b8d2177a3049e71b1ee84586dbc0ab7ecac58c7625e334fca6e750529a47"
		),
		"nRF52840-promicro": asset(
			board: "promicro_nrf52840",
			sha256: "d6d358cf84dc4ebd50e22d1ee505e5532d0c1b2b4a0de243d4f622a880d5a035"
		)
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
		"seeed_wio_tracker_L1_Pro_1W",
		"seeed_solar_node",
		"seeed_xiao_nrf52840_kit",
		"seeed_mesh_tracker_X1",
		"muzi-base",
		"heltec-mesh-node-t096",
		"heltec-mesh-node-t1"
	]

	// MARK: Live accessors (store-backed)

	/// Release the currently-active images were audited against.
	static var releaseTag: String { MaintenanceUf2ManifestStore.shared.releaseTag }

	/// Self-update images keyed by the Board-ID the device reports. Backed by
	/// `MaintenanceUf2ManifestStore`, seeded from the bundled map and updatable by a fetch
	/// from `resource/maintenanceUf2` — see `MeshtasticAPI.refreshMaintenanceUf2APIData()`.
	static var imagesByBoardID: [String: MaintenanceUF2] { MaintenanceUf2ManifestStore.shared.imagesByBoardID }

	/// Meshtastic platformio targets whose products OTAFIX lists as supported.
	///
	/// A UX gate only — it decides whether the upgrade action is offered, never
	/// which image is written. Products that merely share a build target with a
	/// supported one (WISMESH Hub/Tap, Nomadstar Meteor Pro, T-Echo Plus/Lite) are
	/// excluded: OTAFIX ships no bootloader for them, and their Board-IDs refuse at
	/// resolution anyway. The set is manifest-supplied now, so which products are
	/// listed is an `api` data decision rather than one made here.
	static var supportedTargets: Set<String> { MaintenanceUf2ManifestStore.shared.supportedTargets }

	static func supportsTarget(_ platformioTarget: String) -> Bool {
		supportedTargets.contains(platformioTarget.trimmingCharacters(in: .whitespacesAndNewlines))
	}

	/// The image matching the Board-ID a device reported, or nil when
	/// unrecognized. Nil refuses the upgrade: an unrecognized Board-ID means the
	/// installed bootloader is not one we have a verified pairing for, and
	/// writing a bootloader built for other hardware is unrecoverable without a
	/// debug probe.
	///
	/// `platformioTarget` is the connected node's build target. It only picks between images a
	/// row already lists; a target alone never selects an image.
	static func image(forBoardID boardID: String, platformioTarget: String? = nil) -> MaintenanceUF2? {
		MaintenanceUf2ManifestStore.shared.image(
			forBoardID: boardID.trimmingCharacters(in: .whitespaces),
			platformioTarget: platformioTarget
		)
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

	/// Extracts the `Last-Fault: id=0x.. pc=0x.. info=0x..` line a 2.6.0+ bootloader adds
	/// for a SoftDevice or SDK fault it recorded before this boot. Nil when the line is
	/// absent or any of the three values is missing or not hex.
	static func parseLastFault(fromInfoText text: String) -> BootloaderFault? {
		for line in text.split(whereSeparator: \.isNewline) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			guard trimmed.lowercased().hasPrefix("last-fault:") else { continue }
			var values: [String: UInt32] = [:]
			for token in trimmed.dropFirst("last-fault:".count).split(whereSeparator: \.isWhitespace) {
				let pair = token.split(separator: "=", maxSplits: 1)
				guard pair.count == 2, pair[1].lowercased().hasPrefix("0x"),
					  let value = UInt32(pair[1].dropFirst(2), radix: 16) else { continue }
				values[pair[0].lowercased()] = value
			}
			guard let id = values["id"], let pc = values["pc"], let info = values["info"] else { return nil }
			return BootloaderFault(id: id, pc: pc, info: info)
		}
		return nil
	}
}

/// A fault the nRF52 bootloader recorded and printed once in `INFO_UF2.TXT`. For an SDK
/// error `info` is the error code.
struct BootloaderFault: Equatable, Sendable {
	let id: UInt32
	let pc: UInt32
	let info: UInt32

	/// The values as the bootloader prints them, for logs and bug reports.
	var summary: String {
		"id=0x\(String(id, radix: 16)) pc=0x\(String(pc, radix: 16)) info=0x\(String(info, radix: 16))"
	}
}
