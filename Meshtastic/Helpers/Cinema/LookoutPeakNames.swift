//
//  LookoutPeakNames.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import CoreLocation
import Foundation
import GISTools
import MVTTools

/// Names for the lookout's summits from the downloaded basemaps. A peak point on the summit names
/// it. The basemap has no point for a volcano, though, and its summit features are things like
/// Columbia Crest and Cathedral Spire; the park or wilderness named for the mountain does better,
/// so one named "Mount …" or "… Peak" names the highest summit near its label.
enum LookoutPeakNames {
	/// A peak point this close to the summit, at the summit's height, is the summit.
	private static let peakReach: CLLocationDistance = 400
	private static let peakDrop = 80.0
	/// A park or wilderness label this far from a summit can name it.
	private static let reserveReach: CLLocationDistance = 10_000
	private static let reserveKinds: Set<String> = ["nature_reserve", "national_park", "protected_area"]
	/// What a reserve's name ends with, after the mountain's.
	private static let reserveSuffixes = [
		" National Park", " National Volcanic Monument", " National Monument", " National Recreation Area",
		" Recreation Area", " Wilderness Area", " Wilderness", " Provincial Park", " State Park", " Nature Reserve"
	]
	private static let mountainPrefixes = ["Mount ", "Mt. ", "Mt ", "Mont ", "Monte ", "Cerro ", "Pico ", "Volcán ", "Volcan "]
	private static let mountainSuffixes = [" Peak", " Mountain", " Volcano"]

	/// `sites` with the name of the mountain each stands on, where a downloaded basemap has one.
	static func named(_ sites: [LookoutSite]) async -> [LookoutSite] {
		let files = OfflineMapManager.persistedRegionFiles().filter { $0.region.hasBasemap }
		guard !files.isEmpty else { return sites }
		return await Task.detached(priority: .utility) {
			lookUp(sites, in: files)
		}.value
	}

	private struct Candidate {
		let name: String
		let distance: CLLocationDistance
	}

	/// A named point in a tile.
	private struct NamedPoint {
		let name: String
		let coordinate: CLLocationCoordinate2D
		let properties: [String: Sendable]
	}

	nonisolated private static func lookUp(_ sites: [LookoutSite], in files: [OfflineMapRegionFile]) -> [LookoutSite] {
		let sources = files.compactMap { file in
			OfflineTileSourceFactory.source(for: file.url).map { (source: $0, bounds: file.region.bounds) }
		}
		var tiles: [String: VectorTile?] = [:]
		func tile(_ source: any OfflineTileSource, z: Int, x: Int, y: Int) -> VectorTile? {
			let key = "\(z)/\(x)/\(y)"
			if let cached = tiles[key] { return cached }
			let made = source.tileData(z: UInt8(z), x: UInt32(x), y: UInt32(y))
				.flatMap { VectorTile(data: $0, x: x, y: y, z: z, projection: .epsg4326) }
			tiles[key] = made
			return made
		}
		/// Named points in the tile the summit is in and the eight around it, so one just over an edge counts.
		func points(near site: LookoutSite, source: any OfflineTileSource, zoom: Int, kinds: (String) -> Bool) -> [NamedPoint] {
			let center = tileIndex(for: site.coordinate, zoom: zoom)
			var found: [NamedPoint] = []
			for dx in -1...1 {
				for dy in -1...1 {
					guard let vector = tile(source, z: zoom, x: center.x + dx, y: center.y + dy) else { continue }
					for feature in vector.features(for: "pois") {
						let kind = (feature.properties["kind"] as? String) ?? (feature.properties["pmap:kind"] as? String) ?? ""
						guard kinds(kind), let name = feature.properties["name"] as? String, !name.isEmpty,
							  let point = feature.geometry as? Point else { continue }
						found.append(NamedPoint(name: name, coordinate: CLLocationCoordinate2D(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude), properties: feature.properties))
					}
				}
			}
			return found
		}

		// Highest first, so a reserve names the highest summit near its label and no other.
		let order = sites.indices.sorted { sites[$0].elevation > sites[$1].elevation }
		var named = sites
		var usedReserveNames: Set<String> = []
		for index in order {
			let site = sites[index]
			guard site.name == nil, let source = sources.first(where: { $0.bounds.contains(site.coordinate) }) else { continue }
			let reserveZoom = min(11, Int(source.source.tileMaxZoom))
			var reserve: Candidate?
			for point in points(near: site, source: source.source, zoom: reserveZoom, kinds: { reserveKinds.contains($0) }) {
				let distance = point.coordinate.distance(from: site.coordinate)
				guard distance <= reserveReach, let mountain = mountainName(inReserve: point.name), !usedReserveNames.contains(mountain),
					  distance < (reserve?.distance ?? .greatestFiniteMagnitude) else { continue }
				reserve = Candidate(name: mountain, distance: distance)
			}
			if let reserve {
				usedReserveNames.insert(reserve.name)
				named[index] = LookoutSite(latitude: site.latitude, longitude: site.longitude, elevation: site.elevation, name: reserve.name)
				continue
			}
			let peakZoom = min(13, Int(source.source.tileMaxZoom))
			var peak: Candidate?
			for point in points(near: site, source: source.source, zoom: peakZoom, kinds: { $0 == "peak" || $0 == "volcano" }) {
				let distance = point.coordinate.distance(from: site.coordinate)
				guard distance <= peakReach, let elevation = number(point.properties["elevation"]) ?? number(point.properties["ele"]),
					  abs(elevation - Double(site.elevation)) <= peakDrop, distance < (peak?.distance ?? .greatestFiniteMagnitude) else { continue }
				peak = Candidate(name: point.name, distance: distance)
			}
			if let peak {
				named[index] = LookoutSite(latitude: site.latitude, longitude: site.longitude, elevation: site.elevation, name: peak.name)
			}
		}
		return named
	}

	/// The mountain a reserve is named for, if its name is the mountain's plus a park or wilderness
	/// suffix: "Mount Hood Wilderness", "Glacier Peak Wilderness", "Mount Rainier National Park".
	static func mountainName(inReserve name: String) -> String? {
		guard let suffix = reserveSuffixes.first(where: { name.hasSuffix($0) }) else { return nil }
		let mountain = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
		guard !mountain.isEmpty, !mountain.contains("-"), !mountain.contains("/") else { return nil }
		guard mountainPrefixes.contains(where: { mountain.hasPrefix($0) }) || mountainSuffixes.contains(where: { mountain.hasSuffix($0) }) else { return nil }
		return mountain
	}

	/// A tile property as a number, whichever way the decoder typed it.
	private static func number(_ value: Any?) -> Double? {
		switch value {
		case let double as Double: double
		case let float as Float: Double(float)
		case let int as Int: Double(int)
		case let int64 as Int64: Double(int64)
		case let uint as UInt: Double(uint)
		case let uint64 as UInt64: Double(uint64)
		case let string as String: Double(string)
		default: nil
		}
	}

	/// The slippy tile holding `coordinate` at `zoom`.
	private static func tileIndex(for coordinate: CLLocationCoordinate2D, zoom: Int) -> (x: Int, y: Int) {
		let n = pow(2.0, Double(zoom))
		let x = Int((coordinate.longitude + 180) / 360 * n)
		let latitude = coordinate.latitude * .pi / 180
		let y = Int((1 - log(tan(latitude) + 1 / cos(latitude)) / .pi) / 2 * n)
		return (x, y)
	}
}
#endif
