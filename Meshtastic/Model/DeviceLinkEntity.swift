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
	/// Region codes this marketplace ships to (empty = worldwide, nil = not a marketplace)
	var regions: [String]?

	init() {}

	init(
		shortCode: String,
		originalUrl: String = "",
		linkDescription: String? = nil,
		isVendor: Bool = false,
		isMarketplace: Bool = false,
		targets: [String] = [],
		regions: [String]? = nil
	) {
		self.shortCode = shortCode
		self.originalUrl = originalUrl
		self.linkDescription = linkDescription
		self.isVendor = isVendor
		self.isMarketplace = isMarketplace
		self.targets = targets
		self.regions = regions
	}
}
