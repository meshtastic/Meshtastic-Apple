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

	/// Reads the downloaded terrain and finds the summits in it. A call while a search is running
	/// waits for that one rather than starting another.
	func prepare() async {
		if let preparing {
			await preparing.value
			return
		}
		let search = Task { await self.search() }
		preparing = search
		await search.value
		preparing = nil
	}

	private func search() async {
		status = .searching
		let manager = OfflineMapManager.shared
		manager.loadIfNeeded()
		let sources = manager.terrainSources()
		Logger.services.info("🎬 [Cinema] Lookout: \(sources.count, privacy: .public) terrain sources among \(manager.regions.count, privacy: .public) offline regions")
		await store.configure(sources: sources)
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
		bounds = union
		sites = await LookoutPeakNames.named(await LookoutTerrain.sites(in: union, source: store))
		status = sites.isEmpty ? .noSummits : .ready
		Logger.services.info("🎬 [Cinema] Lookout sites: \(self.sites.count, privacy: .public) in the downloaded terrain \(union.minLat, privacy: .public)..\(union.maxLat, privacy: .public), \(union.minLon, privacy: .public)..\(union.maxLon, privacy: .public)")
	}

	func site(for id: String) -> LookoutSite? {
		sites.first { $0.id == id }
	}

	/// The terrain around `site` as an entity, or nil if it can't be built.
	func terrain(for site: LookoutSite, sun: (azimuth: Float, elevation: Float)) async -> ModelEntity? {
		guard let bounds else { return nil }
		guard let model = await LookoutTerrain.build(site: site, bounds: bounds, source: store, sun: sun) else { return nil }
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
				isRadio: node.num == radioNum
			))
		}
		found.sort { $0.distance < $1.distance }
		found = Array(found.prefix(Self.maxLabels))
		// Each label's ground: the position's altitude when it has one, else the terrain's height
		// there, else the eye's level, which puts it on the horizon.
		var placed: [LookoutLabel] = []
		for label in found {
			var ground = label.rise
			if ground <= 0 {
				let coordinate = Self.destination(from: site.coordinate, bearing: label.bearing, distance: label.distance)
				ground = await store.elevation(at: coordinate) ?? eye
			}
			placed.append(LookoutLabel(id: label.id, shortName: label.shortName, longName: label.longName, distance: label.distance, bearing: label.bearing, rise: ground - eye, isRadio: label.isRadio))
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
