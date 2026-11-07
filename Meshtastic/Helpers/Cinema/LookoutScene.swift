//
//  LookoutScene.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/30/26.
//
#if os(visionOS)
import CoreLocation
import Foundation
import OSLog
import RealityKit
import SwiftData

/// What the fire lookout can look out on: the summits in the terrain downloaded for the spatial
/// map, the terrain around the one chosen, and the nodes placed by bearing and distance from it.
@MainActor
@Observable
final class LookoutScene {
	/// Why there are no sites yet, for the panel.
	enum Status: Equatable {
		case idle
		case searching
		case noTerrain
		case noSummits
		case ready
	}

	/// The highest mountains in the downloaded terrain, highest first. Empty with no terrain.
	private(set) var sites: [LookoutSite] = []
	private(set) var status: Status = .idle
	/// The nodes out the windows, for the site the terrain was built for.
	var labels: [LookoutLabel] = []
	private let store = TerrainStore()
	private var bounds: GeoBounds?
	/// How many nodes get a label; the nearest ones.
	private static let maxLabels = 40

	private var preparing: Task<Void, Never>?
	/// Bumped by `forgetSites()`, so a search that started before it doesn't put back what it found.
	private var generation = 0
	/// The area the summits were found in, as `areaKey` writes it; nil before a search.
	private var searchedArea: String?

	/// Reads the downloaded terrain and finds the summits in it, inside `area`: the circle the 3D
	/// map shows around the mesh. The terrain download reaches well past that circle, and a summit
	/// out there isn't on the map. Nil searches all the terrain. Does nothing when the summits for
	/// this area are already found. A call while a search is running waits for that one rather
	/// than starting another.
	func prepare(area: SpatialCircle?) async {
		let key = Self.areaKey(area)
		if key != searchedArea {
			forgetSites()
			searchedArea = key
		}
		guard status == .idle || status == .searching else { return }
		if let preparing {
			await preparing.value
			return
		}
		let search = Task { await self.search(area: area) }
		preparing = search
		await search.value
		// A search started after `forgetSites()` may be the one running now.
		if preparing == search { preparing = nil }
	}

	/// The area as a string to compare and keep with the summits, rounded so a node moving a
	/// little doesn't start a new search.
	static func areaKey(_ area: SpatialCircle?) -> String {
		guard let area else { return "all" }
		return String(format: "%.2f,%.2f,%.0f", area.latitude, area.longitude, (area.radiusMeters / 1_000).rounded())
	}

	private func search(area: SpatialCircle?) async {
		let started = generation
		status = .searching
		let manager = OfflineMapManager.shared
		manager.loadIfNeeded()
		let sources = manager.terrainSources()
		Logger.services.info("🎬 [Cinema] Lookout: \(sources.count, privacy: .public) terrain sources among \(manager.regions.count, privacy: .public) offline regions")
		await store.configure(sources: sources)
		guard generation == started, !Task.isCancelled else { return }
		var union: GeoBounds?
		for source in sources {
			union = union.map { $0.union(source.bounds) } ?? source.bounds
		}
		guard let union else {
			bounds = nil
			sites = []
			status = .noTerrain
			return
		}
		// The terrain out the windows is all of it; the summits are searched for only inside the map's circle.
		bounds = union
		var searchBox = union
		if let area {
			let box = area.bounds
			guard union.intersects(box) else {
				sites = []
				status = .noSummits
				return
			}
			searchBox = GeoBounds(
				minLon: max(union.minLon, box.minLon), minLat: max(union.minLat, box.minLat),
				maxLon: min(union.maxLon, box.maxLon), maxLat: min(union.maxLat, box.maxLat)
			)
		}
		// The files the search and the peak names read, so a list found in files that have since
		// gone isn't kept.
		let terrainFiles = Set(sources.flatMap { [$0.globalURL.lastPathComponent] + $0.regionalURLs.map(\.lastPathComponent) })
		let basemapFiles = Set(OfflineMapManager.persistedRegionFiles().filter { $0.region.hasBasemap }.map(\.url.lastPathComponent))
		let maps = LookoutSiteCacheKey.maps(in: manager.regions, terrainFiles: terrainFiles, basemapFiles: basemapFiles) + "\n" + Self.areaKey(area)
		if let kept = LookoutSiteCache.sites(for: maps) {
			sites = kept
			status = sites.isEmpty ? .noSummits : .ready
			Logger.services.info("🎬 [Cinema] Lookout sites: \(self.sites.count, privacy: .public) kept from the last search")
			return
		}
		// The box around the circle has corners outside it; summits there aren't on the map either.
		let summits = await LookoutTerrain.sites(in: searchBox, source: store, area: area)
		guard generation == started, !Task.isCancelled else { return }
		let found = await LookoutPeakNames.named(summits)
		guard generation == started, !Task.isCancelled else { return }
		sites = found
		LookoutSiteCache.store(sites, for: maps)
		status = sites.isEmpty ? .noSummits : .ready
		Logger.services.info("🎬 [Cinema] Lookout sites: \(self.sites.count, privacy: .public) in the map's area \(searchBox.minLat, privacy: .public)..\(searchBox.maxLat, privacy: .public), \(searchBox.minLon, privacy: .public)..\(searchBox.maxLon, privacy: .public)")
	}

	/// Drops the summits found so far, after the downloaded maps changed, so the next
	/// `prepare()` searches what's there now.
	func forgetSites() {
		generation += 1
		// The old search's results would be thrown away; stop it rather than let it run beside the next one.
		preparing?.cancel()
		preparing = nil
		sites = []
		bounds = nil
		status = .idle
		searchedArea = nil
	}

	func site(for id: String) -> LookoutSite? {
		sites.first { $0.id == id }
	}

	/// The terrain around `site` as an entity, or nil if it can't be built.
	func terrain(for site: LookoutSite, heading: Double, sun: (azimuth: Float, elevation: Float)) async -> ModelEntity? {
		guard let bounds else { return nil }
		let radius = LookoutTerrain.outerRadius(site: site, bounds: bounds)
		let center = site.coordinate
		// Off the main actor, and stopped with this task: leaving the lookout mid-build shouldn't leave
		// tiles decoding for a view nobody sees.
		let build = Task.detached(priority: .userInitiated) {
			OfflineLandCoverMap.make(center: center, radius: radius, files: OfflineMapManager.persistedRegionFiles())
		}
		let landCover = await withTaskCancellationHandler { await build.value } onCancel: { build.cancel() }
		if Task.isCancelled { return nil }
		guard let model = await LookoutTerrain.build(site: site, bounds: bounds, source: store, landCover: landCover, heading: heading, sun: sun) else { return nil }
		do {
			return try await LookoutTerrain.entity(for: model)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the lookout terrain: \(error.localizedDescription, privacy: .public)")
			return nil
		}
	}

	/// The nodes with a position nearest `site`, placed as seen from its cab.
	func labels(for site: LookoutSite, context: ModelContext, radioNum: Int64?) async -> [LookoutLabel] {
		var descriptor = FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.lastHeard != nil },
			sortBy: [SortDescriptor(\.lastHeard, order: .reverse)]
		)
		descriptor.fetchLimit = 400
		guard let nodes = try? context.fetch(descriptor) else { return [] }
		let positions = NodeInfoEntity.latestPositions(for: nodes, context: context)
		let eye = LookoutTerrain.eyeElevation(for: site)
		var found: [LookoutLabel] = []
		for node in nodes {
			guard let position = positions[node.persistentModelID], let coordinate = position.nodeCoordinate else { continue }
			let distance = site.coordinate.distance(from: coordinate)
			guard distance > 30, distance < 150_000 else { continue }
			found.append(LookoutLabel(
				id: node.num,
				shortName: node.liveUser?.shortName ?? String(String(format: "!%08x", UInt32(truncatingIfNeeded: node.num)).suffix(4)),
				longName: node.liveUser?.longName ?? String(format: "!%08x", UInt32(truncatingIfNeeded: node.num)),
				distance: distance,
				bearing: Self.bearing(from: site.coordinate, to: coordinate),
				rise: Double(position.altitude),
				altitude: nil,
				isRadio: node.num == radioNum
			))
		}
		found.sort { $0.distance < $1.distance }
		found = Array(found.prefix(Self.maxLabels))
		// Each label's ground: the position's altitude when it has one, else the terrain's height
		// there, else the eye's level, which puts it on the horizon.
		var placed: [LookoutLabel] = []
		for label in found {
			var altitude: Double? = label.rise > 0 ? label.rise : nil
			if altitude == nil {
				let coordinate = Self.destination(from: site.coordinate, bearing: label.bearing, distance: label.distance)
				altitude = await store.elevation(at: coordinate)
			}
			placed.append(LookoutLabel(id: label.id, shortName: label.shortName, longName: label.longName, distance: label.distance, bearing: label.bearing, rise: (altitude ?? eye) - eye, altitude: altitude, isRadio: label.isRadio))
		}
		return placed
	}

	/// True bearing from `a` to `b`, degrees 0..<360.
	private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
		let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
		let dLon = (b.longitude - a.longitude) * .pi / 180
		let y = sin(dLon) * cos(lat2)
		let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
		let degrees = atan2(y, x) * 180 / .pi
		return (degrees + 360).truncatingRemainder(dividingBy: 360)
	}

	/// The point `distance` meters from `start` along `bearing`.
	private static func destination(from start: CLLocationCoordinate2D, bearing: Double, distance: Double) -> CLLocationCoordinate2D {
		let radius = 6_371_000.0
		let lat1 = start.latitude * .pi / 180, lon1 = start.longitude * .pi / 180
		let angle = bearing * .pi / 180, ratio = distance / radius
		let lat2 = asin(sin(lat1) * cos(ratio) + cos(lat1) * sin(ratio) * cos(angle))
		let lon2 = lon1 + atan2(sin(angle) * sin(ratio) * cos(lat1), cos(ratio) - sin(lat1) * sin(lat2))
		return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
	}
}
#endif
