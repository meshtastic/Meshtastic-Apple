//
//  SpatialMapModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
#if os(visionOS)
import CoreGraphics
import CoreLocation
import Foundation
import Observation
import OSLog
import RealityKit
import SwiftData

/// Where things sit in the model: on the built terrain when it matches the current box, on a flat
/// disk while the terrain is still building. The box is the square around the map's circle.
struct SpatialPlacement {
	/// The circle the terrain was built for: the whole mesh, or a zoomed part of it.
	let circle: SpatialCircle
	var bounds: GeoBounds { circle.bounds }
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

/// The newest Site Planner estimate for a node, for the card's coverage menu.
struct SpatialCoverageFile: Equatable {
	let fileID: UUID
	let isActive: Bool
	let created: Date
}

/// A finished coverage image; CGImage is immutable, just not marked Sendable.
private struct SpatialCoverageImage: @unchecked Sendable {
	let image: CGImage
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
	/// Which Site Planner estimates are draped on the terrain. Set from the window's setting.
	var coverageMode: SpatialCoverageMode = .selected { didSet { rebuildCoverageIfNeeded() } }
	/// How see-through the coverage overlay is; changing it never rebuilds the overlay.
	var coverageOpacity: Float = 0.55
	private(set) var coverageEntity: ModelEntity?
	/// The placement the coverage overlay was built for.
	private(set) var coverageRevision: Int?
	private(set) var coverageLegend: [SpatialCoverageLegendEntry] = []
	/// The newest estimate per node, whether it is shown or not.
	private(set) var coverageByNode: [Int64: SpatialCoverageFile] = [:]
	/// Parsed estimates by file ID, so zooming never parses a file again.
	private var coverageCache: [UUID: SpatialCoverageEstimate] = [:]
	/// Files that held no estimate, so they are not read again.
	private var coverageUnreadable: Set<UUID> = []
	private var coverageKey: String?
	private var coverageTask: Task<Void, Never>?
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
	/// The circle around the whole mesh. Terrain downloads cover the square around it, so zooming
	/// in never starts a download.
	private(set) var fullCircle: SpatialCircle?
	/// How far the map is zoomed into the geography: 1 shows the whole mesh.
	private(set) var zoom: Double = 1
	/// What the zoomed circle is centered on; nil is the full circle's center.
	private(set) var zoomCenter: CLLocationCoordinate2D?
	/// A node to zoom in on once the next refresh has its position (Show in 3D).
	private var pendingFocusNodeNum: Int64?
	private var buildLayer: MapLayer = .standard
	private var buildDark = true
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
		rebuildCoverageIfNeeded()
	}

	/// Selects a node, keeps it on the terrain even when it lies outside the box, and zooms in on it.
	func focus(on nodeNum: Int64) {
		pinnedNodeNums.insert(nodeNum)
		select(nodeNum)
		pendingFocusNodeNum = nodeNum
	}

	// MARK: - Zoom

	var maximumZoom: Double {
		fullCircle.map { SpatialZoom.maximumZoom(fullRadiusMeters: $0.radiusMeters) } ?? 1
	}

	/// The circle the map should show now.
	var targetCircle: SpatialCircle? { circle(forZoom: zoom) }

	/// The circle a zoom would show around the current zoom center.
	func circle(forZoom zoom: Double) -> SpatialCircle? {
		fullCircle.map { SpatialZoom.circle(full: $0, zoom: zoom, center: zoomCenter) }
	}

	func clampedZoom(_ zoom: Double) -> Double {
		SpatialZoom.clamp(zoom, fullRadiusMeters: fullCircle?.radiusMeters ?? 0)
	}

	/// Zooms around the current center and rebuilds the terrain for the smaller circle. The center
	/// is kept where the circle actually ends up, so zooming back in carries on from what is shown.
	func setZoom(_ zoom: Double) {
		let zoom = clampedZoom(zoom)
		guard zoom != self.zoom else { return }
		self.zoom = zoom
		if zoom > 1, let circle = targetCircle {
			zoomCenter = CLLocationCoordinate2D(latitude: circle.latitude, longitude: circle.longitude)
		} else {
			zoomCenter = nil
		}
		applyArea()
	}

	/// Centers the map on a node, zoomed in at least as far as `SpatialZoom.focusZoom`.
	func zoomIn(on nodeNum: Int64) {
		guard let coordinate = nodesByNum[nodeNum]?.coordinate else { return }
		zoomCenter = coordinate
		zoom = clampedZoom(max(zoom, SpatialZoom.focusZoom))
		if zoom <= 1 { zoomCenter = nil }
		applyArea()
	}

	func resetZoom() {
		guard zoom != 1 || zoomCenter != nil else { return }
		zoom = 1
		zoomCenter = nil
		applyArea()
	}

	/// Starts building the terrain for the circle to show. Until it is built, the scene keeps the
	/// old terrain and previews the new circle on it; a first circle gets a flat disk right away.
	private func applyArea() {
		guard let target = targetCircle else { return }
		if placement == nil {
			placementRevision += 1
			placement = Self.flatPlacement(target, revision: placementRevision)
		}
		rebuildTerrainIfNeeded(circle: target, layer: buildLayer, dark: buildDark, contours: showContours)
		updateLabels()
	}

	private static func flatPlacement(_ circle: SpatialCircle, revision: Int) -> SpatialPlacement {
		let frame = SpatialFrame(bounds: circle.bounds)
		return SpatialPlacement(circle: circle, geometry: nil, flat: SpatialModelTransform(frame: frame, baseElevation: 0, maxElevation: 0), revision: revision)
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
		   let next = SpatialMapArea.next(current: fullCircle, candidate: candidate, nodes: fetched.map(\.coordinate), lastChange: lastBoundsChange, now: Date()) {
			fullCircle = next
			lastBoundsChange = Date()
			// The zoom is relative to the full circle; keep it within the new one's limits.
			zoom = clampedZoom(zoom)
			if zoom <= 1 { zoomCenter = nil }
		}
		if let pending = pendingFocusNodeNum, nodesByNum[pending] != nil {
			pendingFocusNodeNum = nil
			zoomIn(on: pending)
		}
		buildLayer = layer
		buildDark = dark
		applyArea()
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
		rebuildCoverageIfNeeded()
	}

	private func rebuildTerrainIfNeeded(circle: SpatialCircle, layer: MapLayer, dark: Bool, contours: Bool) {
		let bounds = circle.bounds
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
					circle: circle, geometry: model.geometry,
					flat: SpatialModelTransform(frame: model.geometry.transform.frame, baseElevation: 0, maxElevation: 0),
					revision: placementRevision
				)
				isBuildingTerrain = false
				rebuildCoverageIfNeeded()
			} catch is CancellationError {
			} catch {
				guard buildKey == key else { return }
				Logger.services.error("🧊 [Spatial] Terrain build failed: \(error.localizedDescription, privacy: .public)")
				terrainMessage = error.localizedDescription
				isBuildingTerrain = false
				// Without terrain, put the pins on a flat disk for the circle they belong to.
				if placement?.circle != circle {
					// The old terrain is for another circle.
					terrainEntity = nil
					placementRevision += 1
					placement = Self.flatPlacement(circle, revision: placementRevision)
				}
			}
		}
	}

	// MARK: - Terrain download

	/// What it would take to cover the box with terrain, ignoring the automatic retry rules. Nil
	/// while there is no box or its terrain is still building.
	func terrainDecision(manager: OfflineMapManager) -> SpatialTerrainAutoDecision? {
		guard let placement, placement.geometry != nil, !isBuildingTerrain, let fullCircle else { return nil }
		return SpatialTerrainAutoDecision.make(
			box: fullCircle.bounds, regions: manager.regions,
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
			  let placement, placement.geometry != nil, let fullCircle,
			  let lastBoundsChange, Date().timeIntervalSince(lastBoundsChange) >= Self.autoDownloadSettleInterval else { return }
		let manager = OfflineMapManager.shared
		guard !manager.isBusy else { return }
		// The region set is part of the key: deleting a map (or the managed terrain) checks again.
		let regionKey = manager.regions.map { "\($0.id)\($0.terrain != nil)" }.joined(separator: ",")
		let bounds = fullCircle.bounds
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
		// The square around the whole mesh, whatever the zoom.
		guard !isDownloadingTerrain, let bounds = fullCircle?.bounds else { return }
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
			// Only nodes on the disk: the rest are hidden, and would take label slots for nothing.
			let target = targetCircle
			let shown = target.map { circle in nodes.filter { SpatialZoom.isShown($0.coordinate, in: circle) } } ?? nodes
			let ranked = shown.sorted { a, b in
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
// MARK: - Coverage

extension SpatialMapModel {
	/// Rebuilds the coverage overlay when the terrain, the mode, the selection (in Selected mode)
	/// or the Site Planner files change. Files are parsed once and cached; the image is drawn off
	/// the main actor. Opacity is not part of the key: it only changes the material.
	private func rebuildCoverageIfNeeded() {
		let files = MapDataManager.shared.getUploadedFiles().filter { $0.source == .sitePlanner }
		updateCoverageByNode(files)
		let ids = Set(files.map(\.id))
		coverageCache = coverageCache.filter { ids.contains($0.key) }
		coverageUnreadable.formIntersection(ids)

		guard let placement, let geometry = placement.geometry else { return }
		let mode = coverageMode
		let selected = selectedNodeNum
		let fingerprint = files.map { "\($0.id)\($0.isActive)" }.joined(separator: ",")
		let key = "\(placement.revision)|\(mode.rawValue)|\(mode == .selected ? String(selected ?? 0) : "")|\(fingerprint)"
		guard key != coverageKey else { return }
		coverageKey = key
		coverageTask?.cancel()

		// In Selected mode only the selected node's files are worth reading.
		let candidates = files.filter { file in
			file.isActive && (mode == .all || (mode == .selected && selected != nil && file.coverage?.nodeNum == selected))
		}
		guard !candidates.isEmpty else {
			clearCoverage()
			return
		}
		let missing = candidates.filter { coverageCache[$0.id] == nil && !coverageUnreadable.contains($0.id) }
		let opacity = coverageOpacity
		coverageTask = Task {
			if !missing.isEmpty {
				let parsed = await Task.detached(priority: .userInitiated) { () -> [UUID: SpatialCoverageEstimate?] in
					// A fresh manager only to read the files: it holds nothing but the storage paths.
					let reader = MapDataManager()
					var parsed: [UUID: SpatialCoverageEstimate?] = [:]
					for file in missing {
						guard !Task.isCancelled else { break }
						parsed[file.id] = reader.loadFeatureCollectionForFiles([file]).flatMap { SpatialCoverageParser.estimate(collection: $0, metadata: file) }
					}
					return parsed
				}.value
				for (id, estimate) in parsed {
					if let estimate { coverageCache[id] = estimate } else { coverageUnreadable.insert(id) }
				}
			}
			guard !Task.isCancelled, coverageKey == key else { return }
			let estimates = candidates.compactMap { coverageCache[$0.id] }
			let visible = SpatialCoverageVisibility.visible(estimates, mode: mode, selected: selected, box: placement.bounds)
			guard !visible.isEmpty else {
				clearCoverage()
				return
			}
			let frame = geometry.transform.frame
			let rendered = await Task.detached(priority: .userInitiated) { () -> SpatialCoverageImage? in
				let size = SpatialTextureRenderer.pixelSize(for: frame, maxEdge: 1024)
				return SpatialCoverageTexture.render(visible, frame: frame, size: size).map(SpatialCoverageImage.init)
			}.value
			guard !Task.isCancelled, coverageKey == key, let rendered else { return }
			do {
				let entity = try await SpatialCoverageEntity.make(geometry: geometry, image: rendered.image, opacity: opacity)
				guard !Task.isCancelled, coverageKey == key else { return }
				coverageEntity = entity
				coverageRevision = placement.revision
				let legend = SpatialCoverageLegend.entries(visible)
				if legend != coverageLegend { coverageLegend = legend }
			} catch {
				Logger.services.error("🧊 [Spatial] Coverage overlay failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// Picks up a Site Planner file shown or hidden from the card now, not at the next refresh.
	func coverageFilesChanged() {
		rebuildCoverageIfNeeded()
	}

	private func clearCoverage() {
		if coverageEntity != nil { coverageEntity = nil }
		if coverageRevision != nil { coverageRevision = nil }
		if !coverageLegend.isEmpty { coverageLegend = [] }
	}

	/// The newest estimate per node, preferring one that is shown.
	private func updateCoverageByNode(_ files: [MapDataMetadata]) {
		var byNode: [Int64: SpatialCoverageFile] = [:]
		for file in files {
			guard let node = file.coverage?.nodeNum else { continue }
			let candidate = SpatialCoverageFile(fileID: file.id, isActive: file.isActive, created: file.uploadDate)
			if let current = byNode[node] {
				let better = (candidate.isActive && !current.isActive)
					|| (candidate.isActive == current.isActive && candidate.created > current.created)
				if !better { continue }
			}
			byNode[node] = candidate
		}
		if byNode != coverageByNode { coverageByNode = byNode }
	}
}
#endif
