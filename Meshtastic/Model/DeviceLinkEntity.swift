//
//  DeviceLinkEntity.swift
//  Meshtastic
//

import Foundation
import SwiftData

@Model
final class DeviceLinkEntity {
	/// Short code from the msh.to URL catalog
	@Attribute(.unique) var shortCode: String = ""
	/// Canonical msh.to redirect URL. The API no longer returns the destination directly,
	/// so this is `https://msh.to/{shortCode}` (the redirect service resolves the target).
	var originalUrl: String = ""
	/// Human-readable description from the catalog
	var linkDescription: String?
	/// True for `Type == "Vendor"` (official manufacturer link)
	var isVendor: Bool = false
	/// True for `Type == "Marketplace"` (third-party retailer/reseller link)
	var isMarketplace: Bool = false
	/// Device `platformioTarget` values this link applies to (from the API `Targets` field)
	var targets: [String] = []
	/// Region codes this marketplace ships to (empty = worldwide). Only meaningful when
	/// `isMarketplace` is true; non-marketplace links leave this empty.
	///
	/// NOTE: This is intentionally a non-optional `[String]`. SwiftData/Core Data cannot
	/// materialize an *optional* array of a value type (`[String]?`) — it faults with
	/// "Could not materialize Objective-C class named \"Array\" ...", which crashes any
	/// `context.save()` that flushes one of these rows (e.g. sending a message). The
	/// "is this a marketplace?" distinction that `nil` used to encode is carried by
	/// `isMarketplace` instead. See issue #1949.
	var regions: [String] = []

	init() {}

	init(
		shortCode: String,
		originalUrl: String = "",
		linkDescription: String? = nil,
		isVendor: Bool = false,
		isMarketplace: Bool = false,
		targets: [String] = [],
		regions: [String] = []
	) {
		self.shortCode = shortCode
		self.originalUrl = originalUrl
		self.linkDescription = linkDescription
		self.isVendor = isVendor
		self.isMarketplace = isMarketplace
		self.targets = targets
		self.regions = regions
	}

	/// Whether this link should be shown for a device with `platformioTarget` when the
	/// user is in `userRegion`. Marketplace links are region-gated (shown only where the
	/// retailer ships); vendor links and worldwide marketplaces (empty `regions`) always
	/// show for a matching target. Shared by `DeviceLinksSection` and its tests so the
	/// visibility rule has a single source of truth.
	func isVisible(forTarget platformioTarget: String, userRegion: String) -> Bool {
		guard targets.contains(platformioTarget) else { return false }
		guard isMarketplace, !regions.isEmpty else { return true }
		return regions.contains(userRegion)
	}
}
