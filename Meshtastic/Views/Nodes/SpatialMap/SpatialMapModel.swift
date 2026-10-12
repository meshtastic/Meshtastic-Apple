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
/// disk while the terrain is still building. The box is the square around the map's circle.
struct SpatialPlacement {
	let bounds: GeoBounds
	let geometry: SpatialTerrainGeometry?
	let flat: SpatialModelTransform
	let revision: Int

	var transform: SpatialModelTransform { geometry?.transform ?? flat }
	var footprint: SIMD2<Float> { transform.footprint }
	/// Radius of the round map in model units.
	var diskRadius: Float { transform.diskRadius }

	/// Nodes sit on the ground. Reported GPS altitude is too noisy, and often on another datum,
	/// to lift a pin off the terrain without it reading as a second layer floating over the map.
	func position(_ coordinate: CLLocationCoordinate2D) -> SIMD3<Float> {
		surface(coordinate)
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
	private(set) var isDownloadingTerrain = false
	/// Alert text for a failed download the user started.
	var terrainDownloadError: String?
	/// Caption for a failed automatic download, shown in the ornament with a retry button.
	private(set) var terrainDownloadNote: String?
	/// Keep the box covered by terrain without asking. Set from the window's setting.
	var autoDownloadTerrain = true
	private var terrainDownloadCancelled = false
	private var terrainDownloadAutomatic = false
	/// The manager took the download (it didn't refuse it up front).
	private var terrainDownloadBegan = false
	private var terrainDownloadTarget: GeoBounds?
	private(set) var backoff = SpatialTerrainBackoff()
	/// The box and region set the automatic check last ran for, so it runs once per settled box.
	private var autoCheckKey: String?
	/// How long the box must stay put before an automatic download starts.
	static let autoDownloadSettleInterval: TimeInterval = 20

	private var pinnedNodeNums: Set<Int64> = []
	private let terrainStore = TerrainStore()
	private let builder: SpatialTerrainBuilder
	private var buildTask: Task<Void, Never>?
	private var buildKey: String?
	private var placementRevision = 0
	/// The area shown; the placement's bounds are the square around it.
	private var circle: SpatialCircle?
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

		if let candidate = SpatialCircle.around(fetched.map(\.coordinate)),
		   let next = SpatialMapArea.next(current: circle, candidate: candidate, nodes: fetched.map(\.coordinate), lastChange: lastBoundsChange, now: Date()) {
			circle = next
			lastBoundsChange = Date()
			placementRevision += 1
			let frame = SpatialFrame(bounds: next.bounds)
			placement = SpatialPlacement(bounds: next.bounds, geometry: nil, flat: SpatialModelTransform(frame: frame, baseElevation: 0, maxElevation: 0), revision: placementRevision)
		}
		if let placement {
			rebuildTerrainIfNeeded(bounds: placement.bounds, layer: layer, dark: dark, contours: showContours)
		}
		autoDownloadIfNeeded()

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

	// MARK: - Terrain download

	/// What it would take to cover the box with terrain, ignoring the automatic retry rules. Nil
	/// while there is no box or its terrain is still building.
	func terrainDecision(manager: OfflineMapManager) -> SpatialTerrainAutoDecision? {
		guard let placement, placement.geometry != nil, !isBuildingTerrain else { return nil }
		return SpatialTerrainAutoDecision.make(
			box: placement.bounds, regions: manager.regions,
			isBusy: manager.isBusy, backoff: SpatialTerrainBackoff(), now: Date()
		)
	}

	/// Whether automatic downloads have stopped for this area (cancelled or failed too often).
	func autoDownloadGaveUp(on target: GeoBounds) -> Bool {
		backoff.gaveUp(on: target)
	}

	/// Starts a download by itself once the box has settled and the terrain doesn't cover it.
	private func autoDownloadIfNeeded() {
		guard autoDownloadTerrain, !isBuildingTerrain, !isDownloadingTerrain,
			  let placement, placement.geometry != nil,
			  let lastBoundsChange, Date().timeIntervalSince(lastBoundsChange) >= Self.autoDownloadSettleInterval else { return }
		let manager = OfflineMapManager.shared
		guard !manager.isBusy else { return }
		// The region set is part of the key: deleting a map (or the managed terrain) checks again.
		let regionKey = manager.regions.map { "\($0.id)\($0.terrain != nil)" }.joined(separator: ",")
		let bounds = placement.bounds
		let key = "\(bounds.minLon),\(bounds.minLat),\(bounds.maxLon),\(bounds.maxLat)|\(regionKey)"
		let retryDue = backoff.target.map { !backoff.gaveUp(on: $0) } == true && backoff.retryAfter.map { Date() >= $0 } == true
		guard key != autoCheckKey || retryDue else { return }
		autoCheckKey = key
		// The wait is over: check once, not on every refresh until the next attempt.
		if retryDue { backoff.retryAfter = nil }
		startTerrainDownload(automatic: true)
	}

	/// Downloads terrain so it covers the volume's box: a new app-managed region, or a bigger one
	/// that replaces it. When it finishes, the terrain generation in the build key changes and the
	/// next refresh rebuilds the model with relief. A manual start ignores the retry rules.
	func startTerrainDownload(automatic: Bool = false) {
		guard !isDownloadingTerrain, let bounds = placement?.bounds else { return }
		let manager = OfflineMapManager.shared
		manager.loadIfNeeded()
		if !automatic { backoff = SpatialTerrainBackoff() }
		let decision = SpatialTerrainAutoDecision.make(
			box: bounds, regions: manager.regions,
			isBusy: manager.isBusy, backoff: backoff, now: Date()
		)
		guard let target = decision.target else {
			Logger.services.debug("🧊 [Spatial] Terrain check: \(String(describing: decision), privacy: .public)")
			return
		}
		isDownloadingTerrain = true
		terrainDownloadCancelled = false
		terrainDownloadAutomatic = automatic
		terrainDownloadTarget = target
		terrainDownloadError = nil
		terrainDownloadNote = nil
		terrainDownloadBegan = false
		let estimate = ByteCountFormatter.string(fromByteCount: SpatialTerrainAutoDecision.estimatedBytes(target), countStyle: .file)
		Logger.services.info("🧊 [Spatial] Terrain download (\(automatic ? "automatic" : "manual", privacy: .public)): \(String(describing: decision), privacy: .public), about \(estimate, privacy: .public)")
		manager.downloadManagedTerrain(bounds: target, includeRegional: SpatialTerrainAutoDecision.includesRegional(target)) { [weak self] success in
			self?.finishTerrainDownload(success: success)
		}
		// Set after the call: a refusal up front completes synchronously, before this line.
		if isDownloadingTerrain, manager.activeDownload != nil { terrainDownloadBegan = true }
	}

	func cancelTerrainDownload() {
		guard isDownloadingTerrain else { return }
		terrainDownloadCancelled = true
		OfflineMapManager.shared.cancelDownload()
	}

	private func finishTerrainDownload(success: Bool) {
		guard isDownloadingTerrain else { return }
		isDownloadingTerrain = false
		Logger.services.info("🧊 [Spatial] Terrain download \(success ? "finished" : (self.terrainDownloadCancelled ? "cancelled" : "failed"), privacy: .public)")
		let target = terrainDownloadTarget
		terrainDownloadTarget = nil
		if success {
			backoff = SpatialTerrainBackoff()
			return
		}
		let manager = OfflineMapManager.shared
		let failed: String? = if case .failed(let message) = manager.activeDownload?.state { message } else { nil }
		// A download that started and ended without failing was cancelled, here or in Offline Maps.
		if terrainDownloadCancelled || (terrainDownloadBegan && failed == nil) {
			if let target { backoff.recordCancel(target) }
			return
		}
		if let target { backoff.recordFailure(target, now: Date()) }
		if failed != nil { manager.dismissDownload() }
		let message = failed ?? String(localized: "The terrain download could not start.", comment: "Spatial map: alert message when the manager refuses the terrain download")
		if terrainDownloadAutomatic {
			terrainDownloadNote = message
		} else {
			terrainDownloadError = message
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
