//
//  SpatialMapModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import CoreLocation
import Foundation
import Observation
import OSLog
import RealityKit
import SwiftData

/// Where things sit in the model: on the built terrain when it matches the current box, on a flat
/// plane while the terrain is still building.
struct SpatialPlacement {
	let bounds: GeoBounds
	let geometry: SpatialTerrainGeometry?
	let flat: SpatialModelTransform
	let revision: Int

	var transform: SpatialModelTransform { geometry?.transform ?? flat }
	var footprint: SIMD2<Float> { transform.footprint }

	func position(_ coordinate: CLLocationCoordinate2D, altitude: Double?) -> SIMD3<Float> {
		if let geometry { return geometry.nodePosition(for: coordinate, reportedAltitude: altitude) }
		return flat.position(coordinate, altitude: flat.baseElevation)
	}

	func surface(_ coordinate: CLLocationCoordinate2D, clearance: Float = 0) -> SIMD3<Float> {
		if let geometry { return geometry.surfacePosition(for: coordinate, clearance: clearance) }
		var p = flat.position(coordinate, altitude: flat.baseElevation)
		p.y += clearance
		return p
	}
}

/// State for one spatial map volume: the nodes in the box, the terrain for it, routes and the
/// selection. Reads SwiftData on the main actor every couple of seconds like the 2D map does;
/// the scene only ever sees snapshots.
@MainActor @Observable
final class SpatialMapModel {
	static let labelLimit = 40

	private(set) var nodes: [SpatialNodeSnapshot] = []
	private(set) var nodesByNum: [Int64: SpatialNodeSnapshot] = [:]
	private(set) var outsideCount = 0
	private(set) var placement: SpatialPlacement?
	private(set) var terrainEntity: ModelEntity?
	private(set) var textureSource: SpatialTextureSource?
	private(set) var isBuildingTerrain = false
	private(set) var terrainMessage: String?
	private(set) var routes: [SpatialRouteSnapshot] = []
	private(set) var links: [SpatialLinkSnapshot] = []
	private(set) var labeledNodeNums: [Int64] = []
	private(set) var selectedNodeNum: Int64?
	var connectedNodeNum: Int64?
	var showLabels = true { didSet { updateLabels() } }
	var showLinks = true
	var showContours = false

	private var pinnedNodeNums: Set<Int64> = []
	private let terrainStore = TerrainStore()
	private let builder: SpatialTerrainBuilder
	private var buildTask: Task<Void, Never>?
	private var buildKey: String?
	private var placementRevision = 0
	private var lastBoundsChange: Date?
	private var refreshCount = 0

	init() {
		builder = SpatialTerrainBuilder(elevation: terrainStore)
	}

	func select(_ nodeNum: Int64?) {
		guard selectedNodeNum != nodeNum else { return }
		// A pin lasts only while the node is selected, so the box can shrink back afterwards.
		if let selectedNodeNum { pinnedNodeNums.remove(selectedNodeNum) }
		selectedNodeNum = nodeNum
		updateLabels()
	}

	/// Selects a node and keeps it on the terrain even when it lies outside the box.
	func focus(on nodeNum: Int64) {
		pinnedNodeNums.insert(nodeNum)
		select(nodeNum)
	}

	func refresh(context: ModelContext, filters: NodeFilterParameters, preciseOnly: Bool, layer: MapLayer, dark: Bool) {
		refreshCount += 1
		var fetched = SpatialMapNodeSource.snapshots(context: context, filters: filters, preciseOnly: preciseOnly, connectedNodeNum: connectedNodeNum)
		let anchor = fetched.first { $0.isConnectedRadio }?.coordinate
		let selection = SpatialMapArea.select(fetched.map(\.coordinate), anchor: anchor)
		var outside = 0
		if selection.outsideCount > 0 {
			let frame = anchor.map { SpatialFrame(bounds: GeoBounds(minLon: $0.longitude, minLat: $0.latitude, maxLon: $0.longitude, maxLat: $0.latitude)) }
			let total = fetched.count
			fetched = fetched.filter { node in
				if pinnedNodeNums.contains(node.id) { return true }
				guard let frame else { return true }
				let p = frame.localPosition(node.coordinate, altitude: 0)
				return Double((p.x * p.x + p.z * p.z).squareRoot()) <= SpatialMapArea.maxRadiusMeters
			}
			outside = total - fetched.count
		}
		if fetched != nodes {
			nodes = fetched
			nodesByNum = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		}
		if outsideCount != outside { outsideCount = outside }
		if let selectedNodeNum, nodesByNum[selectedNodeNum] == nil { select(nil) }

		if let candidate = GeoBounds.around(fetched.map(\.coordinate)),
		   let next = SpatialMapArea.next(current: placement?.bounds, candidate: candidate, nodes: fetched.map(\.coordinate), lastChange: lastBoundsChange, now: Date()) {
			lastBoundsChange = Date()
			placementRevision += 1
			let frame = SpatialFrame(bounds: next)
			placement = SpatialPlacement(bounds: next, geometry: nil, flat: SpatialModelTransform(frame: frame, baseElevation: 0, maxElevation: 0), revision: placementRevision)
		}
		if let placement {
			rebuildTerrainIfNeeded(bounds: placement.bounds, layer: layer, dark: dark, contours: showContours)
		}

		if showLinks, refreshCount % 10 == 1 {
			let fresh = SpatialRouteSource.routes(context: context)
			if fresh != routes {
				routes = fresh
				links = SpatialRouteSource.links(from: fresh)
			}
		} else if !showLinks, !routes.isEmpty {
			routes = []
			links = []
		}
		updateLabels()
	}

	private func rebuildTerrainIfNeeded(bounds: GeoBounds, layer: MapLayer, dark: Bool, contours: Bool) {
		// The terrain generation (every region's download stamp) is part of the key, so a terrain
		// download or delete rebuilds the model.
		let generation = OfflineMapManager.shared.regions
			.compactMap { $0.terrain.map { String(Int($0.downloadedAt.timeIntervalSince1970)) } }
			.sorted()
			.joined(separator: ",")
		let metric = Locale.current.measurementSystem == .metric
		let key = "\(bounds.minLon),\(bounds.minLat),\(bounds.maxLon),\(bounds.maxLat)|\(layer.rawValue)|\(dark)|\(contours)|\(metric)|\(generation)"
		guard key != buildKey else { return }
		buildKey = key
		buildTask?.cancel()
		isBuildingTerrain = true
		terrainMessage = nil
		let sources = OfflineMapManager.shared.terrainSources()
		var options = SpatialTerrainOptions()
		options.layer = layer
		options.dark = dark
		options.contours = contours
		options.metric = metric
		let builder = builder
		let store = terrainStore
		buildTask = Task {
			await store.configure(sources: sources)
			do {
				let model = try await builder.build(bounds: bounds, options: options)
				let entity = try await SpatialTerrainEntity.make(model)
				guard !Task.isCancelled, buildKey == key else { return }
				terrainEntity = entity
				textureSource = model.textureSource
				placementRevision += 1
				placement = SpatialPlacement(
					bounds: bounds, geometry: model.geometry,
					flat: SpatialModelTransform(frame: model.geometry.transform.frame, baseElevation: 0, maxElevation: 0),
					revision: placementRevision
				)
				isBuildingTerrain = false
			} catch is CancellationError {
			} catch {
				guard buildKey == key else { return }
				Logger.services.error("🧊 [Spatial] Terrain build failed: \(error.localizedDescription, privacy: .public)")
				terrainMessage = error.localizedDescription
				isBuildingTerrain = false
			}
		}
	}

	/// The selected node, the connected radio, favorites, then the most recently heard, capped.
	private func updateLabels() {
		var ordered: [Int64] = []
		if showLabels {
			let ranked = nodes.sorted { a, b in
				if a.isConnectedRadio != b.isConnectedRadio { return a.isConnectedRadio }
				if a.isFavorite != b.isFavorite { return a.isFavorite }
				if a.isOnline != b.isOnline { return a.isOnline }
				return (a.lastHeard ?? .distantPast) > (b.lastHeard ?? .distantPast)
			}
			ordered = ranked.prefix(Self.labelLimit).map(\.id)
		}
		if let selectedNodeNum, nodesByNum[selectedNodeNum] != nil {
			ordered.removeAll { $0 == selectedNodeNum }
			ordered.insert(selectedNodeNum, at: 0)
		}
		if ordered != labeledNodeNums { labeledNodeNums = ordered }
	}
}
#endif
