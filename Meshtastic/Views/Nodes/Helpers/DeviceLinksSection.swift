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
		// Fetch all links — we filter in the view since #Predicate doesn't support contains on arrays.
		_allLinks = Query(sort: [SortDescriptor(\DeviceLinkEntity.shortCode)])
	}

	/// Links that apply to this device, region-filtered for marketplaces.
	///
	/// Device association now comes straight from the msh.to API `Targets` field (stored on the
	/// entity), so the old prefix/suffix/`rak`-stripping heuristics are gone. A link matches when
	/// its `targets` contain this device's `platformioTarget`.
	private var matchingLinks: [DeviceLinkEntity] {
		let userRegion = Locale.current.region?.identifier ?? ""
		return allLinks.filter { $0.isVisible(forTarget: platformioTarget, userRegion: userRegion) }
		.sorted { lhs, rhs in
			// Vendor links first, marketplace links after; alphabetical within each group.
			if lhs.isMarketplace != rhs.isMarketplace { return !lhs.isMarketplace }
			return (lhs.linkDescription ?? lhs.shortCode) < (rhs.linkDescription ?? rhs.shortCode)
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
									.font(link.isMarketplace ? .subheadline : .body)
									.fontWeight(link.isMarketplace ? .regular : .semibold)
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
}

// MARK: - msh.to JSON Models

/// Classification of a msh.to short code, straight from the API's `Type` field.
enum MshToLinkType: String, Codable {
	/// Org/community links (GitHub, Discord, docs …) — never associated with a device.
	case internalLink = "Internal"
	/// Official manufacturer / vendor link.
	case vendor = "Vendor"
	/// Third-party retailer / reseller link, region-gated.
	case marketplace = "Marketplace"
}

/// Top-level payload from `https://msh.to/api/urls` (and the bundled `urls.json` fallback).
struct MshToUrlsFile: Codable {
	let routes: [MshToRoute]
	let marketplaces: [String: MshToMarketplace]

	enum CodingKeys: String, CodingKey {
		case routes = "Routes"
		case marketplaces = "Marketplaces"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		routes = try container.decodeIfPresent([MshToRoute].self, forKey: .routes) ?? []
		marketplaces = try container.decodeIfPresent([String: MshToMarketplace].self, forKey: .marketplaces) ?? [:]
	}
}

struct MshToRoute: Codable {
	let shortCode: String
	let description: String?
	let type: MshToLinkType
	/// Device `platformioTarget` values this short code applies to (empty for Internal links).
	let targets: [String]

	enum CodingKeys: String, CodingKey {
		case shortCode = "ShortCode"
		case description = "Description"
		case type = "Type"
		case targets = "Targets"
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		shortCode = try container.decode(String.self, forKey: .shortCode)
		description = try container.decodeIfPresent(String.self, forKey: .description)
		// Unknown/missing Type → Internal, so a future link type never matches a device by mistake.
		type = (try? container.decode(MshToLinkType.self, forKey: .type)) ?? .internalLink
		targets = (try? container.decodeIfPresent([String].self, forKey: .targets)) ?? []
	}
}

/// A retailer's shipping coverage. Empty `regions` = worldwide.
struct MshToMarketplace: Codable {
	let regions: [String]

	enum CodingKeys: String, CodingKey {
		case regions = "Regions"
	}
}
