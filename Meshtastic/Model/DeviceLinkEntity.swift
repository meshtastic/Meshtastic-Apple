//
//  DeviceLinkEntity.swift
//  Meshtastic
//

import Foundation
import SwiftData

@Model
final class DeviceLinkEntity {
	/// Short code from msh.to urls.json
	@Attribute(.unique) var shortCode: String = ""
	/// Destination URL from urls.json
	var originalUrl: String = ""
	/// Human-readable description from urls.json
	var linkDescription: String?
	/// True if this is a direct vendor link (exact match on platformioTarget), false for marketplace/retailer links
	var isVendor: Bool = false
	/// Region codes this marketplace ships to (empty = worldwide, nil = vendor/not applicable)
	var regions: [String]?

	init() {}

	init(shortCode: String, originalUrl: String, linkDescription: String? = nil, isVendor: Bool = false, regions: [String]? = nil) {
		self.shortCode = shortCode
		self.originalUrl = originalUrl
		self.linkDescription = linkDescription
		self.isVendor = isVendor
		self.regions = regions
	}
}
