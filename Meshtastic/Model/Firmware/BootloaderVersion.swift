//
//  BootloaderVersion.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/24/26.
//

import Foundation

/// The nRF52 bootloader version a radio reports in `DeviceMetadata.bootloader_version`, packed as
/// `major << 16 | minor << 8 | patch`. Meshtastic nRF52 Bootloader releases before 2.6.0 all report
/// 0.9.2, the same as stock Adafruit 0.9.2, so that value only means "older than 2.6.0".
struct BootloaderVersion: Equatable, Comparable {
	let major: Int
	let minor: Int
	let patch: Int

	/// What every Meshtastic release before 2.6.0, and stock Adafruit, reports.
	static let legacy = BootloaderVersion(major: 0, minor: 9, patch: 2)
	/// The first release that reports its real version.
	static let firstReported = BootloaderVersion(major: 2, minor: 6, patch: 0)

	init(major: Int, minor: Int, patch: Int) {
		self.major = major
		self.minor = minor
		self.patch = patch
	}

	/// Nil when the radio didn't report one: zero is a non-nRF52 radio or older firmware.
	init?(packed: UInt32) {
		guard packed != 0 else { return nil }
		self.init(major: Int(packed >> 16 & 0xFF), minor: Int(packed >> 8 & 0xFF), patch: Int(packed & 0xFF))
	}

	/// Parses a plain `x.y.z` release tag, such as the manifest's `otafixReleaseTag`.
	init?(tag: String) {
		let parts = tag.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
		guard parts.count == 3 else { return nil }
		let numbers = parts.compactMap { Int($0) }
		guard numbers.count == 3, numbers.allSatisfy({ (0...255).contains($0) }) else { return nil }
		self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
	}

	var isLegacy: Bool { self == Self.legacy }

	var description: String { "\(major).\(minor).\(patch)" }

	static func < (lhs: BootloaderVersion, rhs: BootloaderVersion) -> Bool {
		(lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
	}
}

/// What the firmware screen says about the installed bootloader, and whether it offers the upgrade.
struct BootloaderStatus: Equatable {
	enum Installed: Equatable {
		/// The radio reported 0.9.2: some release before 2.6.0, or stock Adafruit.
		case olderThanFirstReported
		case version(BootloaderVersion)
	}

	let installed: Installed
	/// Nil when the latest release tag doesn't parse; then there is no comparison.
	let latest: BootloaderVersion?

	/// Nil when the radio reported no bootloader version, so the screen shows nothing new.
	init?(packed: UInt32, latestTag: String) {
		guard let version = BootloaderVersion(packed: packed) else { return nil }
		installed = version.isLegacy ? .olderThanFirstReported : .version(version)
		latest = BootloaderVersion(tag: latestTag)
	}

	/// True when the installed bootloader is known to be at or past the latest release.
	var isUpToDate: Bool {
		guard let latest, case .version(let version) = installed else { return false }
		return version >= latest
	}
}
