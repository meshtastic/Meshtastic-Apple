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

/// What the fire lookout, the castle tower, the lighthouse and the city rooftop can look out on:
/// the summits in the terrain downloaded for the spatial map, the headlands on its coast for the
/// lighthouse, or the tallest buildings in its basemaps for the rooftop; the terrain (and for a
/// rooftop, the city) around the one chosen; and the nodes placed by bearing and distance from it.
@MainActor
@Observable
final class LookoutScene {
	/// Why there are no sites yet, for the panel.
	enum Status: Equatable {
		case idle
		case searching
		case noTerrain
		case noSummits
		/// No building with a height in the downloaded basemaps, for the rooftop.
		case noBuildings
		case ready
	}

	/// The highest mountains in the downloaded terrain, highest first, for the lighthouse the
	/// headlands, best first, or for the rooftop the tallest buildings, tallest first. Empty with no
	/// terrain.
	private(set) var sites: [LookoutSite] = []
	/// What the sites are: summits or headlands, as the last `prepare()` asked.
	private(set) var kind: LookoutSiteKind = .summit
	private(set) var status: Status = .idle
	/// The nodes out the windows, for the site the terrain was built for.
	var labels: [LookoutLabel] = []
	/// How far the terrain being built has got, for the card in front of the seat. Nil when none is.
	private(set) var terrainProgress: SpatialTerrainProgress?
	/// Whether terrain is being built. Changes only as a build starts and ends, so a view can show
	/// the card on it without being redrawn for every step of the progress.
	private(set) var isBuildingTerrain = false
	/// Counts terrain builds, so an older one finishing doesn't clear a newer one's progress.
	private var terrainBuild = 0
	/// The ground read for the last site, or being read: what a turn of the room draws again
	/// without reading the tiles. A build that's cancelled for a turn leaves the read running.
	private var groundRead: (siteID: String, task: Task<LookoutGround?, Never>)?
	/// The rooftop's buildings and the ground under each, kept like the ground for its turns.
	private struct CityRead {
		let siteID: String
		let footprints: [SpatialBuildingFootprint]
		let grounds: [Double?]
	}
	private var cityRead: CityRead?
	private let store = TerrainStore.shared
	private var bounds: GeoBounds?
	/// How many nodes get a label; the nearest ones.
	private static let maxLabels = 40

	private var preparing: Task<Void, Never>?
	/// Bumped by `forgetSites()`, so a search that started before it doesn't put back what it found.
	private var generation = 0
	/// The area and kind of site the sites were found for, as `areaKey` writes it; nil before a search.
	private var searchedArea: String?

	/// Reads the downloaded terrain and finds the summits in it, inside `area`: the circle the 3D
	/// map shows around the mesh. The terrain download reaches well past that circle, and a summit
	/// out there isn't on the map. Nil searches all the terrain. `kind` says whether to look for
	/// summits, headlands or the tallest buildings. Does nothing when the sites for this area and
	/// kind are already found. A call while a search is running waits for that one rather than
	/// starting another.
	func prepare(area: SpatialCircle?, kind: LookoutSiteKind = .summit) async {
		let key = Self.areaKey(area) + "|" + kind.rawValue
		if key != searchedArea {
			forgetSites()
			searchedArea = key
			self.kind = kind
		}
		guard status == .idle || status == .searching else { return }
		if let preparing {
			await preparing.value
			return
		}
		let search = Task { await self.search(area: area, kind: kind) }
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

	private func search(area: SpatialCircle?, kind: LookoutSiteKind) async {
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
		let none: Status = kind == .rooftop || kind == .skyDeck ? .noBuildings : .noSummits
		if let kept = LookoutSiteCache.sites(for: maps, kind: kind) {
			sites = kept
			status = sites.isEmpty ? none : .ready
			Logger.services.info("🎬 [Cinema] Lookout sites: \(self.sites.count, privacy: .public) kept from the last search")
			return
		}
		let found: [LookoutSite]
		switch kind {
		case .skyDeck:
			found = await skyDecks(in: Self.rooftopBox(searchBox, area: area))
		case .summit:
			// The box around the circle has corners outside it; summits there aren't on the map either.
			let summits = await LookoutTerrain.sites(in: searchBox, source: store, area: area)
			guard generation == started, !Task.isCancelled else { return }
			found = await LookoutPeakNames.named(summits)
		case .coast:
			// A headland at the circle's edge looks out over sea past it, so the sea is read out to
			// the open-water walk's reach beyond the circle, as far as the terrain goes. The sites are
			// still kept inside the circle.
			found = await LookoutTerrain.coastSites(in: Self.padded(searchBox, by: LookoutCoast.reach, within: union), source: store, area: area)
		case .rooftop:
			found = await rooftops(in: Self.rooftopBox(searchBox, area: area))
		}
		guard generation == started, !Task.isCancelled else { return }
		sites = found
		LookoutSiteCache.store(sites, for: maps, kind: kind)
		status = sites.isEmpty ? none : .ready
		Logger.services.info("🎬 [Cinema] Lookout \(kind.rawValue, privacy: .public) sites: \(self.sites.count, privacy: .public) in the map's area \(searchBox.minLat, privacy: .public)..\(searchBox.maxLat, privacy: .public), \(searchBox.minLon, privacy: .public)..\(searchBox.maxLon, privacy: .public)")
	}

	/// `box` grown by `meters` on every side, cut to `limit`.
	private static func padded(_ box: GeoBounds, by meters: Double, within limit: GeoBounds) -> GeoBounds {
		let dLat = meters / SpatialFrame.metersPerDegreeLatitude
		let dLon = dLat / max(0.01, cos((box.minLat + box.maxLat) / 2 * .pi / 180))
		return GeoBounds(
			minLon: max(limit.minLon, box.minLon - dLon), minLat: max(limit.minLat, box.minLat - dLat),
			maxLon: min(limit.maxLon, box.maxLon + dLon), maxLat: min(limit.maxLat, box.maxLat + dLat)
		)
	}

	/// The tallest buildings in `box`, each standing on the terrain's ground there. Ones the terrain
	/// doesn't reach are left out, since there would be no ground to draw round them.
	private func rooftops(in box: GeoBounds) async -> [LookoutSite] {
		let files = OfflineMapManager.persistedRegionFiles()
		let tiles = Self.rooftopSearchTiles
		let search = Task.detached(priority: .userInitiated) {
			RooftopSites.search(in: box, maxTiles: tiles) { bounds, maxTiles in
				SpatialBuildings.decode(bounds: bounds, files: files, maxTiles: maxTiles)
			} ?? []
		}
		let tallest = await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
		let grounds = await store.elevations(at: tallest.map(\.coordinate))
		return zip(tallest, grounds).compactMap { rooftop, ground in
			ground.map { LookoutSite(latitude: rooftop.coordinate.latitude, longitude: rooftop.coordinate.longitude, elevation: Float($0), name: nil, rooftop: Float(rooftop.height)) }
		}
	}

	/// A sky deck hung off each of the tallest buildings in `box`, standing over the ground under
	/// its seat. Ones the terrain doesn't reach, or whose roof has no face wide enough, are left out.
	private func skyDecks(in box: GeoBounds) async -> [LookoutSite] {
		let files = OfflineMapManager.persistedRegionFiles()
		let tiles = Self.rooftopSearchTiles
		let search = Task.detached(priority: .userInitiated) {
			RooftopSites.searchWithNeighbors(in: box, maxTiles: tiles) { bounds, maxTiles in
				SpatialBuildings.decode(bounds: bounds, files: files, maxTiles: maxTiles)
			} ?? ([], [])
		}
		let (tallest, neighbors) = await withTaskCancellationHandler { await search.value } onCancel: { search.cancel() }
		// Faces are scored against every tall building near, not just the ones the picker keeps.
		let decks = tallest.compactMap { rooftop in RooftopSites.deck(on: rooftop, among: neighbors).map { (rooftop, $0) } }
		let grounds = await store.elevations(at: decks.map(\.1.coordinate))
		return zip(decks, grounds).compactMap { deck, ground in
			let (rooftop, place) = deck
			return ground.map { LookoutSite(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude, elevation: Float($0), name: nil, rooftop: Float(rooftop.height), facing: place.facing) }
		}
	}

	/// Tiles decoded in the first pass for the tallest buildings. The search drops to zoom 13, where
	/// only whole buildings are, before it gives up; the second pass fills in towers drawn in parts.
	private static let rooftopSearchTiles = 160
	/// The rooftop search covers at most this far from the area's center: a city's towers stand
	/// together, and a bigger box would have no zoom with buildings in few enough tiles.
	private static let rooftopSearchRadius = 12_000.0

	/// The box the rooftops are searched in: `box`, cut down round the area's center to
	/// `rooftopSearchRadius`.
	private static func rooftopBox(_ box: GeoBounds, area: SpatialCircle?) -> GeoBounds {
		let centerLatitude = area?.latitude ?? (box.minLat + box.maxLat) / 2
		let centerLongitude = area?.longitude ?? (box.minLon + box.maxLon) / 2
		let dLat = rooftopSearchRadius / SpatialFrame.metersPerDegreeLatitude
		let dLon = dLat / max(0.01, cos(centerLatitude * .pi / 180))
		return GeoBounds(
			minLon: max(box.minLon, centerLongitude - dLon), minLat: max(box.minLat, centerLatitude - dLat),
			maxLon: min(box.maxLon, centerLongitude + dLon), maxLat: min(box.maxLat, centerLatitude + dLat)
		)
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
		// The ground came from the maps that changed.
		groundRead?.task.cancel()
		groundRead = nil
		cityRead = nil
	}

	/// Starts reading the ground round `site`, so its terrain is ready sooner once it's asked for.
	func prewarm(_ site: LookoutSite) {
		guard let bounds else { return }
		_ = ground(for: site, bounds: bounds)
	}

	/// The read of the ground round `site`: the one kept or running for it, or a new one. Reading
	/// another site's ground stops the last one's.
	private func ground(for site: LookoutSite, bounds: GeoBounds) -> Task<LookoutGround?, Never> {
		if let groundRead, groundRead.siteID == site.id { return groundRead.task }
		groundRead?.task.cancel()
		let radius = LookoutTerrain.outerRadius(site: site, bounds: bounds)
		let center = site.coordinate
		let store = store
		let task = Task { [weak self] () -> LookoutGround? in
			// Off the main actor, and stopped with this task: leaving the lookout mid-read shouldn't
			// leave tiles decoding for a view nobody sees.
			let cover = Task.detached(priority: .userInitiated) {
				OfflineLandCoverMap.make(center: center, radius: radius, files: OfflineMapManager.persistedRegionFiles())
			}
			let landCover = await withTaskCancellationHandler { await cover.value } onCancel: { cover.cancel() }
			if Task.isCancelled { return nil }
			return await LookoutTerrain.ground(site: site, bounds: bounds, source: store, landCover: landCover) { progress in
				Task { @MainActor in
					guard let self else { return }
					self.show(progress, forBuild: self.terrainBuild)
				}
			}
		}
		groundRead = (site.id, task)
		return task
	}

	func site(for id: String) -> LookoutSite? {
		sites.first { $0.id == id }
	}

	/// The site with this id, or the one a new search found close to where it was: within 500 m for
	/// a summit, and 30 m for a rooftop or a sky deck, since the next tower over can be closer than 500 m.
	func site(near id: String, kind: LookoutSiteKind = .summit) -> LookoutSite? {
		site(for: id) ?? SpatialLookout.nearest(to: id, in: sites, within: kind == .summit || kind == .coast ? SpatialLookout.sameSiteDistance : 30) { $0.coordinate }
	}

	/// The terrain around `site` as an entity, or nil if it can't be built.
	func terrain(for site: LookoutSite, heading: Double, sun: (azimuth: Float, elevation: Float)) async -> ModelEntity? {
		guard let bounds else { return nil }
		terrainBuild += 1
		let token = terrainBuild
		terrainProgress = SpatialTerrainProgress(phase: .elevation(done: 0, total: 0))
		isBuildingTerrain = true
		defer {
			if terrainBuild == token {
				terrainProgress = nil
				isBuildingTerrain = false
			}
		}
		// The ground for a site already read, as after a turn, is drawn again without reading it.
		let reading = ground(for: site, bounds: bounds)
		let read = await reading.value
		if read == nil, groundRead?.task == reading {
			// Nothing to keep: the next build reads it again.
			groundRead = nil
		}
		guard let read, !Task.isCancelled else { return nil }
		show(SpatialTerrainProgress(phase: .drawing), forBuild: token)
		let drawing = Task.detached(priority: .userInitiated) {
			LookoutTerrain.model(from: read, heading: heading, sun: sun)
		}
		guard let model = await withTaskCancellationHandler(operation: { await drawing.value }, onCancel: { drawing.cancel() }) else { return nil }
		show(SpatialTerrainProgress(phase: .surface), forBuild: token)
		let entity: ModelEntity
		do {
			entity = try await LookoutTerrain.entity(for: model)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the lookout terrain: \(error.localizedDescription, privacy: .public)")
			return nil
		}
		if site.rooftop != nil, let city = await city(around: site, heading: heading, sun: sun) {
			entity.addChild(city)
		}
		if Task.isCancelled { return nil }
		return entity
	}

	/// Moves the card on to `progress` if it's for the build still running and far enough along to
	/// be worth drawing again.
	private func show(_ progress: SpatialTerrainProgress, forBuild token: Int) {
		guard terrainBuild == token, let current = terrainProgress, current.isWorthShowing(progress) else { return }
		terrainProgress = progress
	}

	/// The buildings round a rooftop, standing on the terrain. Nil when there are none to draw; the
	/// terrain shows without them.
	private func city(around site: LookoutSite, heading: Double, sun: (azimuth: Float, elevation: Float)) async -> ModelEntity? {
		let footprints: [SpatialBuildingFootprint]
		let grounds: [Double?]
		if let cityRead, cityRead.siteID == site.id {
			footprints = cityRead.footprints
			grounds = cityRead.grounds
		} else {
			let box = RooftopCity.bounds(around: site)
			let files = OfflineMapManager.persistedRegionFiles()
			let decode = Task.detached(priority: .userInitiated) {
				SpatialBuildings.decode(bounds: box, files: files, maxTiles: RooftopCity.maxTiles) ?? []
			}
			footprints = await withTaskCancellationHandler { await decode.value } onCancel: { decode.cancel() }
			guard !footprints.isEmpty, !Task.isCancelled else { return nil }
			// Each building stands on the ground at its first corner; the store is asked once for all.
			grounds = await store.elevations(at: footprints.map { $0.outline.first ?? site.coordinate })
			guard !Task.isCancelled else { return nil }
			cityRead = CityRead(siteID: site.id, footprints: footprints, grounds: grounds)
		}
		let build = Task.detached(priority: .userInitiated) {
			RooftopCity.build(site: site, footprints: footprints, grounds: grounds, heading: heading, sun: sun)
		}
		guard let model = await withTaskCancellationHandler(operation: { await build.value }, onCancel: { build.cancel() }) else { return nil }
		Logger.services.info("🎬 [Cinema] Rooftop city: \(model.buildings, privacy: .public) of \(footprints.count, privacy: .public) buildings")
		do {
			return try await RooftopCity.entity(for: model)
		} catch {
			Logger.services.error("🎬 [Cinema] Couldn't make the rooftop city: \(error.localizedDescription, privacy: .public)")
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
				longName: node.liveUser?.localLongName ?? String(format: "!%08x", UInt32(truncatingIfNeeded: node.num)),
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
