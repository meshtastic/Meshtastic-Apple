//
//  DeviceLinksSection.swift
//  Meshtastic
//

import SwiftUI
import SwiftData

struct DeviceLinksSection: View {
	let platformioTarget: String
	@Query var allLinks: [DeviceLinkEntity]
	@Environment(\.openURL) private var openURL
	@State private var isExpanded: Bool = false

	init(platformioTarget: String) {
		self.platformioTarget = platformioTarget
		// Fetch all links — we filter in the view since #Predicate doesn't support contains/startsWith
		_allLinks = Query(sort: [SortDescriptor(\DeviceLinkEntity.shortCode)])
	}

	/// Known marketplace identifiers loaded from bundled marketplaces.json
	private static let marketplaceKeys: Set<String> = {
		guard let url = Bundle.main.url(forResource: "marketplaces", withExtension: "json"),
			  let data = try? Data(contentsOf: url),
			  let decoded = try? JSONDecoder().decode([String: MshToMarketplace].self, from: data) else {
			return []
		}
		return Set(decoded.keys)
	}()

	/// All known platformioTargets for excluding other devices from matching
	private static let allDeviceTargets: Set<String> = {
		guard let url = Bundle.main.url(forResource: "DeviceHardware", withExtension: "json"),
			  let data = try? Data(contentsOf: url) else {
			return Set<String>()
		}
		let devices: [DeviceHardwareMinimal] = (try? JSONDecoder().decode([DeviceHardwareMinimal].self, from: data)) ?? []
		return Set(devices.map(\.platformioTarget))
	}()

	/// Links matching this device
	/// Marketplace links are filtered by user's region
	private var matchingLinks: [DeviceLinkEntity] {
		let userRegion = Locale.current.region?.identifier ?? ""
		let targetVariants = Self.buildTargetVariants(platformioTarget)
		return allLinks.filter { link in
			let code = link.shortCode

			// Exact vendor match
			if code == platformioTarget { return true }

			// If this link is a vendor link for a DIFFERENT device, exclude it
			if link.isVendor && code != platformioTarget { return false }

			// Check prefix match: code starts with target (variants/marketplace suffixes)
			let matchesPrefix = targetVariants.contains { target in
				code.hasPrefix("\(target)_") || code.hasPrefix("\(target)-")
			}

			// Check known marketplace prefix match: marketplace-target
			let matchesMarketplacePrefix = targetVariants.contains { target in
				Self.marketplaceKeys.contains { mp in
					code == "\(mp)-\(target)" || code == "\(mp)_\(target)"
				}
			}

			let matchesDevice = matchesPrefix || matchesMarketplacePrefix
			guard matchesDevice else { return false }

			// If prefix-matched, make sure it's not actually another device's target
			if matchesPrefix {
				// Exclude if the short code itself is a different device's platformioTarget
				if Self.allDeviceTargets.contains(code) && code != platformioTarget { return false }
			}

			// Marketplace links: filter by region (empty regions = worldwide)
			guard let regions = link.regions else { return true }
			if regions.isEmpty { return true }
			return regions.contains(userRegion)
		}
		.sorted {
			// Vendor and variant links first, marketplace links after
			let aIsVendorOrVariant = $0.isVendor || !isMarketplaceLink($0)
			let bIsVendorOrVariant = $1.isVendor || !isMarketplaceLink($1)
			if aIsVendorOrVariant != bIsVendorOrVariant {
				return aIsVendorOrVariant
			}
			return false
		}
	}

	/// Check if a link is a marketplace link (has a known marketplace prefix or suffix)
	private func isMarketplaceLink(_ link: DeviceLinkEntity) -> Bool {
		let code = link.shortCode
		return Self.marketplaceKeys.contains { mp in
			code.hasPrefix("\(mp)-") || code.hasPrefix("\(mp)_") ||
			code.hasSuffix("-\(mp)") || code.hasSuffix("_\(mp)")
		}
	}

	var body: some View {
		if !matchingLinks.isEmpty {
			Section {
				Button {
					withAnimation {
						isExpanded.toggle()
					}
				} label: {
					HStack {
						Text("I want one")
							.font(.headline)
							.foregroundStyle(.primary)
						Spacer()
						Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
							.foregroundStyle(.accent)
							.font(.caption)
					}
				}
				if isExpanded {
					ForEach(matchingLinks, id: \.shortCode) { link in
						Button {
							if let url = URL(string: "https://msh.to/\(link.shortCode)") {
								openURL(url)
							}
						} label: {
							HStack {
						Text(link.linkDescription ?? link.shortCode)
							.font(link.isVendor || !isMarketplaceLink(link) ? .body : .subheadline)
							.fontWeight(link.isVendor || !isMarketplaceLink(link) ? .semibold : .regular)
									.foregroundStyle(.primary)
								Spacer()
								Image(systemName: "safari")
									.foregroundStyle(.accent)
							}
						}
					}
				}
			}
		}
	}

	// MARK: - Target Variant Builder

	/// Build alternate target strings for matching (e.g., "rak4631" also matches as "4631")
	private static func buildTargetVariants(_ target: String) -> [String] {
		var variants = [target]
		// Strip common hardware prefixes to handle short codes like "rokland-4631" matching "rak4631"
		let prefixes = ["rak", "rak-"]
		for prefix in prefixes where target.hasPrefix(prefix) {
			let stripped = String(target.dropFirst(prefix.count))
			if !stripped.isEmpty {
				variants.append(stripped)
			}
		}
		return variants
	}
}

// MARK: - msh.to JSON Models

struct MshToUrlsFile: Codable {
	let routes: [MshToRoute]

	enum CodingKeys: String, CodingKey {
		case routes = "Routes"
	}
}

struct MshToRoute: Codable {
	let shortCode: String
	let originalUrl: String
	let description: String?

	enum CodingKeys: String, CodingKey {
		case shortCode = "ShortCode"
		case originalUrl = "OriginalUrl"
		case description = "Description"
	}
}

struct MshToMarketplace: Codable {
	let regions: [String]
	let match: String // "prefix" or "suffix"
}

struct DeviceHardwareMinimal: Decodable {
	let platformioTarget: String
}
