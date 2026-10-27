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
	/// The built texture is the offline fallback because the Apple map image could not be fetched.
	private(set) var imageryUnavailable = false
	private(set) var isBuildingTerrain = false
	private(set) var terrainMessage: String?
	private(set) var routes: [SpatialRouteSnapshot] = []
	/// The trace route picked in the trace route menu. It stays drawn after the flyover lands, so its
	/// badges and SNR can be read, until it is cleared.
	var shownRoute: SpatialRouteSnapshot?
	/// Direct links between the nodes on the map, newest first; empty while `showLinks` is off.
	private(set) var links: [SpatialLinkSnapshot] = []
	/// Set from the window's setting.
	var showLinks = false {
		// Read the reports again right away when the links are turned back on.
		didSet { if showLinks && !oldValue { reportsReadAt = .distantPast } }
	}
	/// Saved neighbor reports, re-read every 15 s rather than on every 2 s refresh.
	@ObservationIgnored private var reports: [NodeLinkReportRow] = []
	@ObservationIgnored private var reportsReadAt = Date.distantPast
	private(set) var labeledNodeNums: [Int64] = []
	private(set) var selectedNodeNum: Int64?
	var connectedNodeNum: Int64?
	var showLabels = true { didSet { updateLabels() } }
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
	/// Drape NOAA rain over the terrain. Set from the window's setting, shared with the 2D map.
	var showWeatherRadar = false { didSet { if showWeatherRadar != oldValue { rebuildWeatherRadarIfNeeded() } } }
	/// The radar is offered where the device is (the lower 48). Set from the window.
	var weatherRadarOffered = false { didSet { if weatherRadarOffered != oldValue { rebuildWeatherRadarIfNeeded() } } }
	/// Set from the window's connectivity monitor. The radar is fetched only online and cleared offline.
	var networkAvailable = true { didSet { if networkAvailable != oldValue { rebuildWeatherRadarIfNeeded() } } }
	private(set) var weatherRadarEntity: ModelEntity?
	/// The placement the weather radar overlay was built for.
	private(set) var weatherRadarRevision: Int?
	private var weatherRadarKey: String?
	private var weatherRadarTask: Task<Void, Never>?
	/// The last radar image fetched, so a terrain rebuilt for the same box is draped without a fetch.
	private var weatherRadarCache: SpatialWeatherRadarCache?
	/// The image on the drape that is up, so one image is never draped twice on the same terrain.
	private var weatherRadarDraped: CGImage?
	/// The key whose failed fetch was tried again, so each is tried again once.
	private var weatherRadarRetriedKey: String?
	private var weatherRadarRetryTask: Task<Void, Never>?
	/// Set by the window when the volume closes. A terrain build that finishes after that must
	/// not start a radar fetch for a table no one sees.
	var isClosed = false {
		didSet {
			guard isClosed, !oldValue else { return }
			weatherRadarTask?.cancel()
			weatherRadarRetryTask?.cancel()
			weatherRadarKey = nil
			Logger.services.info("🧊 [Spatial] Volume closing; the weather radar stops fetching")
		}
	}
	/// The download and its retry rules live in the keeper, shared with the app's own check.
	private let keeper = SpatialTerrainKeeper.shared
	var isDownloadingTerrain: Bool { keeper.isDownloading }
	/// Alert text for a failed download the user started.
	var terrainDownloadError: String?
	/// Caption for a failed automatic download, shown in the ornament with a retry button.
	var terrainDownloadNote: String? { keeper.note }
	/// Keep the box covered by terrain without asking. Set from the window's setting.
	var autoDownloadTerrain = true
	/// The box and region set the automatic check last ran for, so it runs once per settled box.
	private var autoCheckKey: String?
	/// How long the box must stay put before an automatic download starts.
	static let autoDownloadSettleInterval: TimeInterval = 20

	private var pinnedNodeNums: Set<Int64> = []
	private let terrainStore = TerrainStore()
	private let builder: SpatialTerrainBuilder
	private var buildTask: Task<Void, Never>?
	private var buildKey: String?
	/// Whether each imported basemap holds vector tiles, by region ID. A raster import can't be
	/// drawn as the Offline layer, so it never offers it.
	private var vectorBasemaps: [UUID: Bool] = [:]
	@ObservationIgnored private var vectorCheckTask: Task<Void, Never>?
	private var placementRevision = 0
	/// The circle around the whole mesh. Terrain downloads cover the square around it, so zooming
	/// in never starts a download.
	private(set) var fullCircle: SpatialCircle?
	/// The area to show while no node has a position: around the newest map the user downloaded.
	var downloadedMapCircle: SpatialCircle?
	/// The full circle is `downloadedMapCircle`, not the mesh. No automatic download then: the
	/// user picked that map themselves.
	private(set) var showingDownloadedMap = false
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
	private var routeTask: Task<Void, Never>?

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

	/// Centers and zooms the map so all the coordinates fit on the disk, as far out as the whole mesh.
	func fit(_ coordinates: [CLLocationCoordinate2D]) {
		guard let full = fullCircle, let fit = SpatialZoom.fit(coordinates, full: full) else { return }
		zoom = fit.zoom
		zoomCenter = fit.center
		applyArea()
	}

	func resetZoom() {
		guard zoom != 1 || zoomCenter != nil else { return }
		zoom = 1
		zoomCenter = nil
		applyArea()
	}

	private func clearArea() {
		buildTask?.cancel()
		buildKey = nil
		isBuildingTerrain = false
		terrainEntity = nil
		textureSource = nil
		placement = nil
		fullCircle = nil
		showingDownloadedMap = false
		zoom = 1
		zoomCenter = nil
	}

	/// A `newArea` starts zoomed out on its center; otherwise the zoom carries over.
	private func setFullCircle(_ circle: SpatialCircle, newArea: Bool = false) {
		fullCircle = circle
		lastBoundsChange = Date()
		if newArea {
			zoom = 1
			zoomCenter = nil
			return
		}
		// The zoom is relative to the full circle; keep it within the new one's limits.
		zoom = clampedZoom(zoom)
		if zoom <= 1 { zoomCenter = nil }
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
		let all = SpatialMapNodeSource.snapshots(context: context, filters: filters, preciseOnly: preciseOnly, connectedNodeNum: connectedNodeNum)
		let (fetched, outside) = SpatialMapArea.fit(all, pinned: pinnedNodeNums)
		if fetched != nodes {
			nodes = fetched
			nodesByNum = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		}
		if outsideCount != outside { outsideCount = outside }
		if let selectedNodeNum, nodesByNum[selectedNodeNum] == nil { select(nil) }

		let coordinates = fetched.map(\.coordinate)
		if let candidate = SpatialCircle.around(coordinates) {
			// Leaving a downloaded map for the mesh is a new area, not the mesh moving, so it doesn't
			// wait for the rules that keep the mesh's circle steady.
			let next = showingDownloadedMap
				? candidate
				: SpatialMapArea.next(current: fullCircle, candidate: candidate, nodes: coordinates, lastChange: lastBoundsChange, now: Date())
			if let next {
				setFullCircle(next, newArea: showingDownloadedMap)
				showingDownloadedMap = false
			}
		} else if let downloaded = downloadedMapCircle, downloaded != fullCircle {
			setFullCircle(downloaded, newArea: true)
			showingDownloadedMap = true
		} else if downloadedMapCircle == nil, showingDownloadedMap {
			// The downloaded map was deleted and there are still no positions: back to an empty table.
			clearArea()
		}
		if let pending = pendingFocusNodeNum, nodesByNum[pending] != nil {
			pendingFocusNodeNum = nil
			zoomIn(on: pending)
		}
		buildLayer = layer
		buildDark = dark
		applyArea()
		autoDownloadIfNeeded()

		if refreshCount % 10 == 1 { refreshRoutes(container: context.container) }
		let now = Date.now
		if showLinks && now.timeIntervalSince(reportsReadAt) >= 15 {
			reports = NodeLinks.reportRows(context: context, now: now)
			reportsReadAt = now
		}
		let freshLinks = showLinks
			? SpatialLinkLayout.links(nodes: fetched, connectedNum: connectedNodeNum, reports: reports, now: now)
			: []
		if freshLinks != links { links = freshLinks }
		updateLabels()
		rebuildCoverageIfNeeded()
		rebuildWeatherRadarIfNeeded()
	}

	/// Reads the routes in the background and publishes them here. A read still running is left
	/// to finish rather than starting another.
	private func refreshRoutes(container: ModelContainer) {
		guard routeTask == nil else { return }
		routeTask = Task { [weak self] in
			let fresh = await SpatialRouteReader.routes(container: container)
			guard let self else { return }
			routeTask = nil
			if fresh != routes { routes = fresh }
		}
	}

	/// Reads the routes now and waits for them, for a route asked for by id that may be newer than
	/// the last read.
	func reloadRoutes(container: ModelContainer) async {
		let fresh = await SpatialRouteReader.routes(container: container)
		if fresh != routes { routes = fresh }
	}

	/// Whether a downloaded basemap covers the box being shown, so the Offline layer can be picked.
	func offlineLayerAvailable(regions: [OfflineMapRegion]) -> Bool {
		guard let bounds = targetCircle?.bounds else { return false }
		return offlineBasemapCovers(bounds, regions: regions)
	}

	private func offlineBasemapCovers(_ bounds: GeoBounds, regions: [OfflineMapRegion]) -> Bool {
		checkImportedBasemaps(regions)
		return SpatialOfflineMap.covers(bounds, basemaps: SpatialOfflineMap.basemapBounds(regions, checked: vectorBasemaps))
	}

	/// Reads the tile type of imported basemaps not checked yet, then rebuilds in case Offline is
	/// now available.
	private func checkImportedBasemaps(_ regions: [OfflineMapRegion]) {
		guard vectorCheckTask == nil else { return }
		let unchecked = regions.filter { SpatialOfflineMap.isVectorBasemap($0, checked: vectorBasemaps) == nil }
		guard !unchecked.isEmpty else { return }
		let files = unchecked.compactMap { region in OfflineMapManager.shared.fileURL(for: region).map { OfflineMapRegionFile(region: region, url: $0) } }
		vectorCheckTask = Task { [weak self] in
			let found = await Task.detached(priority: .utility) { SpatialOfflineMap.checkVectorTiles(files) }.value
			guard let self else { return }
			// A file that can't be read counts as not vector, so it isn't checked again.
			for region in unchecked { vectorBasemaps[region.id] = found[region.id] ?? false }
			vectorCheckTask = nil
			applyArea()
		}
	}

	private func rebuildTerrainIfNeeded(circle: SpatialCircle, layer storedLayer: MapLayer, dark: Bool, contours: Bool) {
		let bounds = circle.bounds
		OfflineMapManager.shared.loadIfNeeded()
		let regions = OfflineMapManager.shared.regions
		let offlineBasemap = offlineBasemapCovers(bounds, regions: regions)
		let layer = SpatialOfflineMap.buildLayer(storedLayer, offlineAvailable: offlineBasemap)
		// The terrain generation (every region's download stamp) is part of the key, so a terrain
		// download or delete rebuilds the model.
		let terrainGeneration = regions
			.compactMap { $0.terrain.map { String(Int($0.downloadedAt.timeIntervalSince1970)) } }
			.sorted()
			.joined(separator: ",")
		let metric = Locale.current.measurementSystem == .metric
		// The Offline layer, and an Apple layer drawn from the offline map because imagery failed,
		// also rebuild when a basemap is downloaded, updated or replaced. The Apple layers otherwise
		// rebuild only when the area gains or loses a basemap (`offlineBasemap`).
		func makeKey(usedFallback: Bool) -> String {
			let basemaps = SpatialOfflineMap.basemapGeneration(regions, layer: layer, usedFallback: usedFallback)
			return "\(bounds.minLon),\(bounds.minLat),\(bounds.maxLon),\(bounds.maxLat)|\(layer.rawValue)|\(dark)|\(contours)|\(metric)|\(offlineBasemap)|\(terrainGeneration)|\(basemaps)"
		}
		let key = makeKey(usedFallback: imageryUnavailable)
		guard key != buildKey else { return }
		buildKey = key
		buildTask?.cancel()
		isBuildingTerrain = true
		terrainMessage = nil
		let sources = OfflineMapManager.shared.terrainSources()
		var options = SpatialTerrainOptions()
		options.layer = layer
		options.offlineBasemap = offlineBasemap
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
				imageryUnavailable = model.imageryUnavailable
				// Key the build by what it drew, so falling back (or not) doesn't rebuild it again.
				buildKey = makeKey(usedFallback: model.imageryUnavailable)
				placementRevision += 1
				placement = SpatialPlacement(
					circle: circle, geometry: model.geometry,
					flat: SpatialModelTransform(frame: model.geometry.transform.frame, baseElevation: 0, maxElevation: 0),
					revision: placementRevision
				)
				isBuildingTerrain = false
				rebuildCoverageIfNeeded()
				rebuildWeatherRadarIfNeeded()
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

	/// Builds the current area again after the network comes back, so an Apple layer that fell
	/// back to the offline map for lack of imagery gets its imagery.
	func retryImagery() {
		guard imageryUnavailable else { return }
		buildKey = nil
		applyArea()
	}

	// MARK: - Terrain download

	/// What it would take to cover the box with terrain, ignoring the automatic retry rules. Nil
	/// while there is no box or its terrain is still building.
	func terrainDecision(manager: OfflineMapManager) -> SpatialTerrainAutoDecision? {
		guard let placement, placement.geometry != nil, !isBuildingTerrain, let fullCircle else { return nil }
		return SpatialTerrainAutoDecision.make(
			box: fullCircle.bounds, regions: manager.regions,
			isBusy: manager.isBusy, backoff: SpatialTerrainBackoff(), now: Date(),
			streetsTooLarge: keeper.streetsTooLarge
		)
	}

	/// The street map for the box was over the per-map limit, so the volume has terrain only.
	var streetsLeftOut: Bool {
		guard let box = fullCircle?.bounds, let area = keeper.streetsTooLarge else { return false }
		return area.contains(box)
	}

	/// Whether automatic downloads have stopped for this area (cancelled or failed too often).
	func autoDownloadGaveUp(on target: GeoBounds) -> Bool {
		keeper.gaveUp(on: target)
	}

	/// Starts a download by itself once the box has settled and the terrain doesn't cover it.
	private func autoDownloadIfNeeded() {
		guard autoDownloadTerrain, !showingDownloadedMap, !isBuildingTerrain, !isDownloadingTerrain,
			  let placement, placement.geometry != nil, let fullCircle,
			  let lastBoundsChange, Date().timeIntervalSince(lastBoundsChange) >= Self.autoDownloadSettleInterval else { return }
		let manager = OfflineMapManager.shared
		guard !manager.isBusy else { return }
		// The region set is part of the key: deleting a map (or the managed terrain) checks again.
		let regionKey = manager.regions.map { "\($0.id)\($0.terrain != nil)\($0.hasBasemap)" }.joined(separator: ",")
		let bounds = fullCircle.bounds
		let key = "\(bounds.minLon),\(bounds.minLat),\(bounds.maxLon),\(bounds.maxLat)|\(regionKey)"
		// The wait is over: check once, not on every refresh until the next attempt.
		let retryDue = keeper.takeRetryDue()
		guard key != autoCheckKey || retryDue else { return }
		autoCheckKey = key
		startTerrainDownload(automatic: true)
	}

	/// Downloads terrain so it covers the volume's box. When it finishes, the terrain generation in
	/// the build key changes and the next refresh rebuilds the model with relief. A manual start
	/// ignores the retry rules.
	func startTerrainDownload(automatic: Bool = false) {
		// The square around the whole mesh, whatever the zoom.
		guard let bounds = fullCircle?.bounds else { return }
		if !automatic { terrainDownloadError = nil }
		keeper.start(box: bounds, automatic: automatic, onFailure: automatic ? nil : { [weak self] message in
			self?.terrainDownloadError = message
		})
	}

	func cancelTerrainDownload() {
		keeper.cancel()
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

// MARK: - Weather radar

extension SpatialMapModel {
	/// Rebuilds the weather radar overlay when the terrain, the five-minute period or whether to
	/// fetch at all changes. The image is fetched and decoded off the main actor and kept, so a
	/// terrain rebuilt for the same box (dark map, contours, another layer) is draped again without
	/// a fetch, and a new period on the same terrain only swaps the drape's image. A failed fetch
	/// keeps the rain that is up for one more period, or with nothing up tries once more; going
	/// offline clears it.
	private func rebuildWeatherRadarIfNeeded() {
		guard !isClosed, let placement, let geometry = placement.geometry else { return }
		let center = CLLocationCoordinate2D(latitude: placement.circle.latitude, longitude: placement.circle.longitude)
		let fetch = SpatialWeatherRadar.shouldFetch(show: showWeatherRadar, offered: weatherRadarOffered, networkAvailable: networkAvailable, center: center)
		let period = WeatherRadar.refreshPeriod()
		let key = SpatialWeatherRadar.key(revision: placement.revision, refreshPeriod: period, fetch: fetch)
		guard key != weatherRadarKey else { return }
		weatherRadarKey = key
		weatherRadarTask?.cancel()
		weatherRadarRetryTask?.cancel()
		guard fetch else {
			clearWeatherRadar()
			return
		}
		let bounds = placement.bounds
		let frame = geometry.transform.frame
		let retried = weatherRadarRetriedKey == key
		weatherRadarTask = Task {
			var image = weatherRadarCache?.current(bounds: bounds, refreshPeriod: period)
			if image == nil {
				do {
					let fetched = try await SpatialWeatherRadar.fetch(SpatialWeatherRadar.plan(for: frame, refreshPeriod: period))
					guard !Task.isCancelled, weatherRadarKey == key else { return }
					weatherRadarCache = SpatialWeatherRadarCache(bounds: bounds, refreshPeriod: period, image: fetched.image)
					image = fetched.image
					Logger.services.info("🧊 [Spatial] Weather radar fetched for period \(period, privacy: .public), terrain \(placement.revision, privacy: .public)")
				} catch is CancellationError {
					return
				} catch {
					guard !Task.isCancelled, weatherRadarKey == key else { return }
					Logger.services.info("🧊 [Spatial] Weather radar fetch failed: \(error.localizedDescription, privacy: .public)")
					switch SpatialWeatherRadar.afterFailedFetch(cache: weatherRadarCache, bounds: bounds, refreshPeriod: period, retried: retried) {
					case .keep(let kept):
						image = kept
					case .retry:
						clearWeatherRadar()
						retryWeatherRadar(key: key)
						return
					case .clear:
						clearWeatherRadar()
						return
					}
				}
			}
			guard let image else { return }
			// The same image is already draped on this terrain.
			if weatherRadarRevision == placement.revision, weatherRadarDraped === image { return }
			do {
				if let entity = weatherRadarEntity, weatherRadarRevision == placement.revision {
					// A new period on the same terrain: only the image changes.
					let texture = try await SpatialOverlayEntity.texture(for: image)
					guard !Task.isCancelled, weatherRadarKey == key else { return }
					SpatialOverlayEntity.setTexture(texture, on: entity)
				} else {
					let entity = try await SpatialWeatherRadarEntity.make(geometry: geometry, image: image)
					guard !Task.isCancelled, weatherRadarKey == key else { return }
					weatherRadarEntity = entity
					weatherRadarRevision = placement.revision
				}
				weatherRadarDraped = image
			} catch {
				Logger.services.error("🧊 [Spatial] Weather radar overlay failed: \(error.localizedDescription, privacy: .public)")
			}
		}
	}

	/// A failed fetch left nothing on the table: fetch again after a short wait rather than leave
	/// it bare until the next period. Dropping the key makes the next check fetch again.
	private func retryWeatherRadar(key: String) {
		weatherRadarRetriedKey = key
		weatherRadarRetryTask?.cancel()
		weatherRadarRetryTask = Task {
			guard (try? await Task.sleep(for: .seconds(SpatialWeatherRadar.retryDelay))) != nil, weatherRadarKey == key else { return }
			weatherRadarKey = nil
			rebuildWeatherRadarIfNeeded()
		}
	}

	/// Takes the drape down and drops the kept image: it is of a box that is not shown, too old,
	/// or not wanted any more.
	private func clearWeatherRadar() {
		if weatherRadarEntity != nil { weatherRadarEntity = nil }
		if weatherRadarRevision != nil { weatherRadarRevision = nil }
		weatherRadarDraped = nil
		weatherRadarCache = nil
	}
}
#endif
