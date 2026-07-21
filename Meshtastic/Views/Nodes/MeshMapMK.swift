//
//  MeshMap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/23.
//

import SwiftUI
@preconcurrency import SwiftData
import CoreLocation
import Foundation
import OSLog
import MapKit

private struct MeshMapVisiblePositionState {
	let positions: [PositionEntity]
	let key: Int64
}

struct MeshMapMK: View {
	private let denseMapPositionLimit = 700

	@Environment(\.modelContext) private var context
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
	@Environment(\.openWindow) private var openWindow
	@EnvironmentObject var accessoryManager: AccessoryManager

	@ObservedObject
	var router: Router
	var showOpenWindowButton: Bool = true

	/// Parameters
	/// Whether to draw the device's own location (blue dot) + show the user-tracking control.
	/// Persisted so the choice survives relaunch; gated on `isMapVisible` at the call site so the
	/// dot/tracking turns off while the tab is off-screen or the app is backgrounded.
	@AppStorage("enableMapUserLocation") private var showUserLocation: Bool = true
	/// Map State User Defaults
	@AppStorage("enableMapTraffic") private var showTraffic: Bool = false
	@AppStorage("enableMapPointsOfInterest") private var showPointsOfInterest: Bool = false
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .standard
	/// Offline tiles are an independent overlay (drawn on top of the selected base map), not a
	/// base layer -- so the styled offline box + coverage border work over Standard/Hybrid/Satellite.
	@AppStorage("enableOfflineTiles") private var enableOfflineTiles = false
	@AppStorage("enableMapClustering") private var enableMapClustering = true
	/// Hide nodes whose latest position is reduced-precision (the ones drawn with a precision circle).
	@AppStorage("enableMapPreciseLocationsOnly") private var preciseLocationsOnly = false
	/// Map overlay configs
	@State private var enabledOverlayConfigs: Set<UUID> = []
	// Map Configuration
	@Namespace var mapScope
	@AppStorage("meshMapDistance") private var meshMapDistance: Double = 800000
	// Persisted last-viewed camera region, so the map reopens where the user left it -- independent of
	// GPS / connected device / node availability at launch. This is what fixes the cold-open default
	// (0,0) "South Atlantic" view for a location-denied user with no positioned nodes. Stored as four
	// primitives because `MKCoordinateRegion` isn't `Codable`; a non-positive saved span means
	// "nothing saved yet".
	@AppStorage("meshMapRegionCenterLatitude") private var savedRegionCenterLatitude: Double = 0
	@AppStorage("meshMapRegionCenterLongitude") private var savedRegionCenterLongitude: Double = 0
	@AppStorage("meshMapRegionSpanLatitude") private var savedRegionSpanLatitude: Double = 0
	@AppStorage("meshMapRegionSpanLongitude") private var savedRegionSpanLongitude: Double = 0
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .flat, emphasis: MapStyle.StandardEmphasis.muted, pointsOfInterest: .excludingAll, showsTraffic: false)
	@State var position = MapCameraPosition.automatic
	@State private var distance = 10000.0
	@State private var visibleRegion: MKCoordinateRegion?
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	/// Vector overlays (accuracy circles + convex hull) — rebuilt on data change, stable between
	/// renders so ClusterMapView's overlay diff is a no-op when nothing changed.
	@State private var mapOverlays: [ClusterMapOverlay] = []
	/// Display-coordinate overrides for nodes that sit on (nearly) the same point, fanned out into
	/// a small ring so a stacked cluster always breaks into individual, tappable node circles.
	@State private var spreadOverrides: [Int64: CLLocationCoordinate2D] = [:]
	/// Guards the one-time initial camera framing (GPS-centered, zoomed out, ~100 miles max).
	@State private var didInitialFrame = false
	/// One-shot camera move fed to the map. Set ONCE by the initial framing; after that the user
	/// drives the camera and we never move it programmatically, so a flood of incoming positions
	/// can't re-frame the map mid-gesture.
	@State private var cameraCommand: ClusterMapCameraCommand?
	/// Offline basemap rendered as native MKOverlays (slate/cream vector content) -- matches the old
	/// SwiftUI map's look and aligns the coverage border/label exactly (no tile-grid mismatch).
	@StateObject private var offlineVectors = OfflineVectorTileProvider()
	/// Downloaded offline regions; observed so a new download re-points offlineVectors.
	@ObservedObject private var offlineMapManager = OfflineMapManager.shared
	@State private var offlineVectorOverlays: [ClusterMapOverlay] = []
	/// Route polylines + start/finish markers, rebuilt only when the route set changes.
	@State private var routeOverlays: [ClusterMapOverlay] = []
	@State private var routeDecorations: [ClusterMapDecoration] = []
	/// A single trace route drawn on the map (forward solid + return dashed polyline + endpoint
	/// markers), set when arriving via a `meshtastic:///map?tracerouteId=` deep link.
	@State private var selectedTraceRoute: TraceRouteEntity?
	@State private var tracerouteOverlays: [ClusterMapOverlay] = []
	@State private var tracerouteDecorations: [ClusterMapDecoration] = []
	@State private var lastTraceRouteKey = "init"
	/// Drives the guided 3D camera flythrough along the selected trace route.
	@StateObject private var flyover = TraceRouteFlyover()
	@AppStorage("enableMapWaypoints") private var showWaypoints = true
	@AppStorage("mapOverlaysEnabled") private var mapOverlaysEnabled = false
	@State private var waypointDecorations: [ClusterMapDecoration] = []
	/// User-uploaded GeoJSON overlays: lines/polygons -> overlays, points -> decorations.
	@State private var geoJSONOverlays: [ClusterMapOverlay] = []
	@State private var geoJSONDecorations: [ClusterMapDecoration] = []
	/// Geofence overlays: per-waypoint radius circles and bounding-box rectangles.
	@State private var geofenceOverlays: [ClusterMapOverlay] = []
	/// Last inputs each rebuild ran for; skip when unchanged so overlay objects stay stable (no flash).
	@State private var lastOfflineOverlaysKey = ""
	@State private var lastRouteKey = "init"
	@State private var lastWaypointKey = "init"
	@State private var lastGeoJSONKey = "init"
	@Environment(\.colorScheme) private var colorScheme
	@State private var editingSettings = false
	@State private var editingFilters = false
	@State var selectedNode: MeshMapSelectedNode?
	@State private var visiblePositionSnapshots: [MeshMapPositionSnapshot] = []
	@State var editingWaypoint: WaypointEntity?
	@State var selectedWaypoint: WaypointEntity?
	@State var selectedWaypointId: String?
	@State var newWaypointCoord: CLLocationCoordinate2D?
	@State var isMeshMap = true
	@State private var showLegend = false
	/// Site Planner coverage-estimate flow: the headless WebView+bridge runner and the form seed.
	@StateObject private var coverageRunner = CoverageEstimateRunner()
	@State private var coverageSeed: CoverageEstimateSeed?
	/// Filter
	@ObservedObject var filters = NodeFilterParameters.shared
	/// Track whether a detached Mesh Map window is currently open.
	@State private var isMapWindowOpen = false

	/// The connected device's latest coordinate, used as a fallback origin
	/// for distance filtering when the phone's location services are unavailable.
	private var activeDeviceCoordinate: CLLocationCoordinate2D? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)?.latestPosition?.nodeCoordinate
	}

	/// Update the distance-filter fallback location ONLY when it actually changes. `fallbackLocation`
	/// is `@Published` on the shared `filters` object, so an unconditional write publishes
	/// `objectWillChange` and re-renders `body` — which re-runs the heavy position filter and, because
	/// the filter depends on `fallbackLocation`, can spiral to 100% CPU on Mac Catalyst.
	private func syncFallbackLocation() {
		let coordinate = activeDeviceCoordinate
		guard !Self.coordinatesEqual(filters.fallbackLocation, coordinate) else { return }
		filters.fallbackLocation = coordinate
	}

	private static func coordinatesEqual(_ lhs: CLLocationCoordinate2D?, _ rhs: CLLocationCoordinate2D?) -> Bool {
		switch (lhs, rhs) {
		case (nil, nil): return true
		case let (a?, b?): return abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
		default: return false
		}
	}

	/// Latest positions, refreshed on a throttled cadence (see the `.task` in `body`) instead of a
	/// live `@Query`. Under heavy ingestion (large mesh, TCP replay, reconnect node-DB dump) a live
	/// query invalidates `body` on every position write, and each evaluation re-ran the
	/// filter + density sort over the whole set — pegging the main thread at ~100% CPU. A ~2s
	/// refresh is imperceptible on a map while pan/zoom/filter changes still refresh immediately.
	@State private var allLatestPositions: [PositionEntity] = []
	/// Change-detection key of the last applied position state; skips snapshot/overlay rebuilds
	/// when a periodic refresh finds nothing visibly different.
	@State private var appliedPositionStateKey: Int64 = .min

	private func fetchLatestPositions() -> [PositionEntity] {
		let descriptor = FetchDescriptor<PositionEntity>(
			predicate: #Predicate<PositionEntity> { $0.nodePosition != nil && $0.latest == true && $0.nodePosition?.ignored != true }
		)
		return (try? context.fetch(descriptor)) ?? []
	}

	/// Re-fetch positions, rebuild the derived state, and apply it when it actually changed.
	/// `force` bypasses the change-detection key (used when visibility flips, so snapshots are
	/// rebuilt after being dropped even though the underlying positions are unchanged).
	@MainActor
	private func refreshPositionState(force: Bool = false) {
		allLatestPositions = fetchLatestPositions()
		let state = visiblePositionState
		guard force || state.key != appliedPositionStateKey else { return }
		appliedPositionStateKey = state.key
		refreshVisiblePositionSnapshots(from: state.positions)
		syncFallbackLocation()
		decodeOfflineIfVisible()
	}

	/// Enabled saved routes drawn as polylines + start/finish markers (parity with the old map).
	@Query(filter: #Predicate<RouteEntity> { $0.enabled == true }, sort: \RouteEntity.name)
	private var routes: [RouteEntity]

	/// Saved waypoints, shown as tappable markers (tap -> form; long-press empty map -> create).
	@Query private var allWaypoints: [WaypointEntity]

	/// Positions filtered once per render using the full NodeFilterParameters.
	private func filteredPositions(from positions: [PositionEntity]) -> [PositionEntity] {
		let searchText = filters.searchText.lowercased()
		let onlineThreshold = filters.isOnline ? Date().addingTimeInterval(-7_200) : nil
		let distanceBounds = filters.currentDistanceBounds
		return positions.filter { position in
			guard let node = position.nodePosition else { return false }
			return filters.matches(
				node,
				latestPosition: position,
				normalizedSearchText: searchText,
				onlineThreshold: onlineThreshold,
				distanceBounds: distanceBounds
			)
		}
	}

	/// Keep the detached map window fully populated while still starving the
	/// main tabbed Mesh Map when it is off-screen.
	///
	/// Also drop all map content while the app is backgrounded (both the tab and the detached
	/// window). Otherwise the per-node `MapCircle` overlays stay live and MapKit/VectorKit
	/// re-invalidates the whole overlay layer on `willEnterForeground`, which can spin at ~100%
	/// CPU. The map repopulates on the next foreground.
	private var isMapVisible: Bool {
		guard !accessoryManager.isInBackground else { return false }
		return showOpenWindowButton ? router.selectedTab == .map : true
	}

	/// Latest positions eligible for the mesh map. When "Precise Locations Only" is enabled, drop
	/// reduced-precision positions (the same range `rebuildOverlays` draws the translucent precision
	/// circle for) so the imprecise pins and their circles hide together.
	private var mapEligiblePositions: [PositionEntity] {
		guard preciseLocationsOnly else { return allLatestPositions }
		return allLatestPositions.filter { !$0.isReducedPrecision }
	}

	/// Positions actually passed to the map — empty when the tab is off-screen
	/// so MapKit drops its annotation view trees and reduces memory.
	private var visiblePositions: [PositionEntity] {
		guard isMapVisible else { return [] }

		let eligiblePositions = mapEligiblePositions
		guard let visibleRegion else {
			guard filters.isFiltering || !filters.searchText.isEmpty else {
				return densityLimitedPositions(eligiblePositions)
			}
			return densityLimitedPositions(filteredPositions(from: eligiblePositions))
		}
		let positionsInRegion = eligiblePositions.filter { $0.isInMapRegion(visibleRegion, paddingMultiplier: 1.4) }
		// MapKit can briefly report a stale/empty camera region while restoring
		// the tab or handling deep links. Never blank all pins because of that.
		let positions = positionsInRegion.isEmpty ? eligiblePositions : positionsInRegion
		guard filters.isFiltering || !filters.searchText.isEmpty else {
			return densityLimitedPositions(positions)
		}
		return densityLimitedPositions(filteredPositions(from: positions))
	}

	private var visiblePositionState: MeshMapVisiblePositionState {
		let positions = visiblePositions
		var key = Int64(positions.count)
		if let visibleRegion {
			combine(&key, Int64((visibleRegion.center.latitude * 10_000).rounded(.towardZero)))
			combine(&key, Int64((visibleRegion.center.longitude * 10_000).rounded(.towardZero)))
			combine(&key, Int64((visibleRegion.span.latitudeDelta * 10_000).rounded(.towardZero)))
			combine(&key, Int64((visibleRegion.span.longitudeDelta * 10_000).rounded(.towardZero)))
		}
		combine(&key, filterRefreshKey)
		// Hash EVERY visible position: since the throttled refresh, this key is the only gate for
		// snapshot/overlay rebuilds, and a truncated sample would leave pins beyond it permanently
		// stale when a node moves without changing the set's count or ordering.
		for position in positions {
			combine(&key, Int64(truncatingIfNeeded: position.persistentModelID.hashValue))
			combine(&key, Int64(position.latitudeI))
			combine(&key, Int64(position.longitudeI))
			combine(&key, Int64(position.precisionBits))
		}
		return MeshMapVisiblePositionState(positions: positions, key: key)
	}

	/// Draw the heavy offline detail only while the coverage box is actually on screen (and not at
	/// Apple basemap type + controls fed to ClusterMapView (Phase 2).
	private var clusterConfiguration: ClusterMapConfiguration {
		ClusterMapConfiguration(
			layer: selectedMapLayer == .offline ? .standard : selectedMapLayer,
			showsTraffic: showTraffic,
			showsPointsOfInterest: showPointsOfInterest,
			showsUserLocation: showUserLocation && isMapVisible,
			controlsBottomInset: 72   // lift compass + pitch toggle above the bottom button bar
		)
	}

	/// All downloaded regions to render when offline tiles are enabled (pruned to on-disk regions at
	/// load). Empty when offline tiles are off or nothing is downloaded.
	private var offlineRegions: [OfflineMapRegion] {
		enableOfflineTiles ? offlineMapManager.regions : []
	}

	/// Archive URLs for every downloaded region — decoded + merged by `offlineVectors`.
	private var offlineRegionURLs: [URL] {
		offlineRegions.compactMap { offlineMapManager.fileURL(for: $0) }
	}

	/// Coverage box for each downloaded region (accent borders + capsules), shown once vectors load.
	private var offlineCoverageAreas: [GeoBounds] {
		offlineVectors.isAvailable ? offlineRegions.map { $0.bounds } : []
	}
	/// Cheap change-detector for the route set (drives rebuildRouteContent via onChange).
	/// Change-detector for the waypoint set (rebuild markers on add/remove/move/icon change).
	private var waypointsKey: String {
		allWaypoints.map { "\($0.id)|\($0.icon)|\($0.latitudeI)|\($0.longitudeI)|\($0.geofenceRadius)|\($0.hasBoundingBox ? 1 : 0)|\($0.boundingBoxLatitudeNorthI)|\($0.boundingBoxLatitudeSouthI)|\($0.boundingBoxLongitudeEastI)|\($0.boundingBoxLongitudeWestI)" }.joined(separator: ",")
	}
	private var routesKey: String {
		routes.map { "\($0.color)|\($0.locations.count)" }.joined(separator: ",")
	}
	/// True when the visible set is crowded -> draw lightweight dot pins instead of full pins.
	private var isDense: Bool { visiblePositionSnapshots.count > 500 }

	/// The map itself, extracted from `body` so the big generic expression type-checks on its own.
	@ViewBuilder private var meshClusterMapView: some View {
		ClusterMapView(
				items: visiblePositionSnapshots,
				coordinate: { spreadOverrides[$0.nodeNum] ?? $0.coordinate },
				region: $visibleRegion,
				cameraCommand: cameraCommand,
				clustering: enableMapClustering,
				onSelect: { snapshot in selectedWaypoint = nil; editingWaypoint = nil; selectedNode = MeshMapSelectedNode(id: snapshot.nodeNum) },
				configuration: clusterConfiguration,
				overlays: combinedMapOverlays(),
				coverageAreas: isMapVisible ? offlineCoverageAreas : [],
				decorations: combinedMapDecorations(),
				onMapLongPress: { coordinate in beginNewWaypoint(at: coordinate) },
				onMapCreated: { flyover.mapView = $0 },
				suppressRegionUpdates: flyover.isFlying
			) { snapshot in
				MeshMapMKNodePin(nodeNum: snapshot.nodeNum, shortName: snapshot.shortName, isOnline: snapshot.isOnline, calculatedDelay: snapshot.calculatedDelay, dense: isDense)
					.equatable()
			}
	}

	/// Banner shown while a trace route is drawn on the map, with controls to fly through and clear it.
	@ViewBuilder private var traceRouteBanner: some View {
		if let route = selectedTraceRoute {
			let fromName = getNodeInfo(id: route.fromNum, context: context)?.user?.shortName ?? route.fromNum.toHex()
			let toName = getNodeInfo(id: route.toNum, context: context)?.user?.shortName ?? route.toNum.toHex()
			let flyLegs = traceRouteFlyoverLegs(for: route)
			HStack(spacing: 10) {
				Image(systemName: "point.3.connected.trianglepath.dotted")
				Text("Trace Route: \(fromName) → \(toName)")
					.font(.callout)
					.fontWeight(.medium)
					.lineLimit(1)
				if flyLegs.contains(where: { $0.count >= 2 }) {
					// Speed toggle: cycle 1× (base/slow) → 1.5× → 2× → 2.5× → 3× → 4× → 5× (400% faster). Live-adjustable.
					Button {
						let steps: [Double] = [1, 1.5, 2, 2.5, 3, 4, 5]
						let next = (steps.firstIndex(of: flyover.speedMultiplier) ?? 0) + 1
						flyover.speedMultiplier = steps[next % steps.count]
					} label: {
						Text(String(format: "%g×", flyover.speedMultiplier))
							.font(.caption)
							.fontWeight(.semibold)
							.monospacedDigit()
							.frame(minWidth: 30)
					}
					.buttonStyle(.bordered)
					// Text(_:) localizes via the "Flyover speed %@" key; pass a language-agnostic "2×".
					.accessibilityLabel(Text("Flyover speed \(String(format: "%g×", flyover.speedMultiplier))"))
					Button {
						if flyover.isFlying {
							flyover.stop()
						} else {
							flyover.start(legs: flyLegs)
						}
					} label: {
						Image(systemName: flyover.isFlying ? "stop.circle.fill" : "play.circle.fill")
							.foregroundStyle(flyover.isFlying ? Color.red : Color.accentColor)
					}
					.buttonStyle(.plain)
					.accessibilityLabel(flyover.isFlying ? Text("Stop flyover") : Text("Start flyover"))
				}
				Button {
					clearTraceRoute()
				} label: {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
				.accessibilityLabel(String(localized: "Clear trace route", comment: "VoiceOver label for the clear trace route button"))
			}
			.padding(.horizontal, 14)
			.padding(.vertical, 8)
			.background(.thinMaterial, in: Capsule())
			.padding(.top, 8)
		}
	}

	/// The map + its sheets + the bottom button bar, split out of `body` so the long modifier
	/// chain type-checks in pieces (the whole thing in one `body` exceeded the solver budget).
	@ViewBuilder private var mapWithSheets: some View {
		meshClusterMapView
			.ignoresSafeArea()
			.overlay(alignment: .top) { traceRouteBanner }
				.sheet(item: $selectedNode) { selection in
					if let node = getNodeInfo(id: selection.id, context: context) {
						NavigationStack {
							NodeDetail(node: node, showMapLink: false)
						}
						#if targetEnvironment(macCatalyst)
							.overlay(alignment: .topLeading) {
								Button {
									selectedNode = nil
								} label: {
									Image(systemName: "xmark.circle.fill")
										.font(.system(size: 34))
									.symbolRenderingMode(.palette)
									.foregroundStyle(.white, Color(.systemGray3))
							}
							.buttonStyle(.plain)
							.padding(.top, 12)
							.padding(.leading, 14)
						}
						#endif
						.presentationDetents([.large])
						#if !targetEnvironment(macCatalyst)
						.presentationDragIndicator(.visible)
						#endif
					}
				}
				.sheet(item: $selectedWaypoint) { selection in
					WaypointForm(waypoint: selection)
						.presentationDetents([.large]) // full screen
						#if !targetEnvironment(macCatalyst)
						.presentationDragIndicator(.visible)
						#endif
				}
				.sheet(item: $editingWaypoint) { selection in
					WaypointForm(waypoint: selection, editMode: true)
						.presentationDetents([.large])
						#if !targetEnvironment(macCatalyst)
						.presentationDragIndicator(.visible)
						#endif
				}

				.sheet(isPresented: $editingSettings) {
					MapSettingsForm(traffic: $showTraffic, pointsOfInterest: $showPointsOfInterest, mapLayer: $selectedMapLayer, meshMap: $isMeshMap, enabledOverlayConfigs: $enabledOverlayConfigs)
				}
				.onChange(of: router.mapState) {
					guard case .map = router.selectedTab else { return }
					applyTraceRouteSelection()
					consumeCoverageEstimateState()
					// TODO: handle deep link for waypoints
				}
				.onChange(of: selectedMapLayer) { _, newMapLayer in
					switch selectedMapLayer {
					case .standard:
						UserDefaults.mapLayer = newMapLayer
						mapStyle = MapStyle.standard(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
					case .hybrid:
						UserDefaults.mapLayer = newMapLayer
						mapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
					case .satellite:
						UserDefaults.mapLayer = newMapLayer
						mapStyle = MapStyle.imagery(elevation: .realistic)
					case .offline:
						return
					}
				}
				.sheet(isPresented: $editingFilters) {
					NodeListFilter(
						filterTitle: "Map Filters",
						filters: filters
					)
				}
				.sheet(isPresented: $showLegend) {
					MapLegend(isMeshMap: true)
						.presentationDetents([.large])
						.presentationContentInteraction(.scrolls)
						#if !targetEnvironment(macCatalyst)
						.presentationDragIndicator(.visible)
						#endif
						.presentationBackgroundInteraction(.enabled(upThrough: .medium))
				}
				.sheet(item: $coverageSeed) { seed in
					CoverageEstimateForm(seed: seed, runner: coverageRunner)
						.presentationDetents([.large])
						#if !targetEnvironment(macCatalyst)
						.presentationDragIndicator(.visible)
						#endif
				}
				.safeAreaInset(edge: .bottom, alignment: .trailing) {
					HStack(spacing: 12) {
						Spacer()
						Button(action: {
							presentCoverageEstimateFromMap()
						}) {
							Image("custom.radio.tower")
						}
						.accessibilityLabel(String(localized: "Estimate coverage", comment: "VoiceOver label for the coverage estimate button"))
						.accessibilityHint(String(localized: "Runs a Site Planner coverage estimate and adds it to the map.", comment: "VoiceOver hint for the coverage estimate button"))
						.glassButtonStyle()
						Button(action: {
							withAnimation {
								editingFilters = !editingFilters
							}
						}) {
							Image(systemName: filters.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
						}
						.accessibilityLabel(editingFilters ? String(localized: "Hide node filters", comment: "VoiceOver label to hide map node filters") : String(localized: "Show node filters", comment: "VoiceOver label to show map node filters"))
						.accessibilityHint(editingFilters ? String(localized: "Hides the node filter options.", comment: "VoiceOver hint to hide map node filters") : String(localized: "Shows the node filter options.", comment: "VoiceOver hint to show map node filters"))
						.glassButtonStyle()
						Button(action: {
							withAnimation {
								showLegend = !showLegend
							}
						}) {
							Image(systemName: showLegend ? "map.fill" : "map")
						}
						.accessibilityLabel(showLegend ? String(localized: "Hide map legend", comment: "VoiceOver label to hide the map legend") : String(localized: "Show map legend", comment: "VoiceOver label to show the map legend"))
						.accessibilityHint(showLegend ? String(localized: "Hides the map legend.", comment: "VoiceOver hint to hide the map legend") : String(localized: "Shows the map legend.", comment: "VoiceOver hint to show the map legend"))
						.glassButtonStyle()
						Button(action: {
							withAnimation {
								editingSettings = !editingSettings
							}
						}) {
							Image(systemName: editingSettings ? "info.circle.fill" : "info.circle")
						}
						.accessibilityLabel(editingSettings ? String(localized: "Hide map settings", comment: "VoiceOver label to hide the map settings panel") : String(localized: "Show map settings", comment: "VoiceOver label to show the map settings panel"))
						.accessibilityHint(editingSettings ? String(localized: "Hides the map settings panel.", comment: "VoiceOver hint to hide the map settings panel") : String(localized: "Shows the map settings panel.", comment: "VoiceOver hint to show the map settings panel"))
						.glassButtonStyle()
					}
					.controlSize(.regular)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
				}
	}

	var body: some View {
		NavigationStack {
			ZStack {
			mapWithSheets
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					MeshtasticLogo()
				}
				ToolbarItem(placement: .topBarTrailing) {
					HStack {
						if supportsMultipleWindows && showOpenWindowButton && !isMapWindowOpen {
							Button {
								if router.selectedTab == .map {
									router.selectedTab = .nodes
								}
								openWindow(id: "meshmap-window")
								isMapWindowOpen = true
							} label: {
								Image(systemName: "macwindow.badge.plus")
							}
							.accessibilityLabel(String(localized: "Open map in new window", comment: "VoiceOver label for the open map in a new window button"))
						}
						ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
					}
				}
			}
			.toolbarBackground(.hidden, for: .navigationBar)
		}
			.task(id: isMapVisible) {
				// Throttled position refresh: re-derive the visible positions on a gentle
				// cadence instead of on every SwiftData write (see `allLatestPositions`).
				guard isMapVisible else { return }
				while !Task.isCancelled {
					refreshPositionState()
					try? await Task.sleep(for: .seconds(2))
				}
			}
			.onChange(of: offlineMapManager.regions) {
				reloadOfflineSource()
			}
			.onChange(of: overlayInputsKey) {
				rebuildAllMapContent()
			}
			.onChange(of: filterRefreshKey) {
				// Filter/search edits should reflect immediately, not on the next tick.
				refreshPositionState(force: true)
			}
			.onChange(of: regionRefreshKey) {
				// Pan/zoom settled: re-filter to the new region now; the state key dedupes
				// the rebuild when the visible set is unchanged.
				refreshPositionState()
				// Remember where the user is looking so the map reopens here next launch.
				persistVisibleRegion()
			}
			.onChange(of: accessoryManager.activeDeviceNum) {
				syncFallbackLocation()
			}
			.onChange(of: accessoryManager.isInBackground) {
				// Foreground/background flips isMapVisible; refresh so the overlay-bearing
				// snapshots are dropped when backgrounded and rebuilt when foregrounded.
				refreshPositionState(force: true)
			}
			.onChange(of: coverageRunner.importedResult) { _, result in
				guard let result else { return }
				applyImportedCoverage(result)
			}
			.onAppear {
				UIApplication.shared.isIdleTimerDisabled = true
				syncFallbackLocation()
				refreshMapWindowOpenState()
				consumeCoverageEstimateState()
			// Initialize enabled overlay configs with all active files
			// Migrate the legacy `.offline` base layer to the new independent offline-tiles overlay.
			if selectedMapLayer == .offline {
				selectedMapLayer = .standard
				enableOfflineTiles = true
			}
			let activeFiles = GeoJSONOverlayManager.shared.getUploadedFilesWithState().filter { $0.isActive }
			enabledOverlayConfigs = Set(activeFiles.map { $0.id })
			rebuildWaypointDecorations()
			rebuildGeoJSONOverlays()
			rebuildRouteContent()
			applyTraceRouteSelection()
			offlineMapManager.loadIfNeeded()
			reloadOfflineSource()
			rebuildOfflineVectorOverlays()

			switch selectedMapLayer {
			case .standard:
				mapStyle = MapStyle.standard(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
			case .hybrid:
				mapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
			case .satellite:
				mapStyle = MapStyle.imagery(elevation: .realistic)
			case .offline:
				mapStyle = MapStyle.hybrid(elevation: .realistic, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
			}
			refreshPositionState(force: true)
		}
		.onDisappear(perform: {
			UIApplication.shared.isIdleTimerDisabled = false
			GeoJSONOverlayManager.shared.clearCache()
			visiblePositionSnapshots = []
		})
		.onChange(of: router.selectedTab) { _, newTab in
			if newTab == .map {
				syncFallbackLocation()
				refreshMapWindowOpenState()
				UIApplication.shared.isIdleTimerDisabled = true
				refreshPositionState(force: true)
				applyTraceRouteSelection()
				consumeCoverageEstimateState()
			} else {
				flyover.stop(restoreCamera: false)
				UIApplication.shared.isIdleTimerDisabled = false
				GeoJSONOverlayManager.shared.clearCache()
				visiblePositionSnapshots = []
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: Foundation.Notification.Name.mapDataFileDeleted)) { notification in
			if let deletedFileId = notification.object as? UUID {
				enabledOverlayConfigs.remove(deletedFileId)
			}
		}
		.onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in
			refreshMapWindowOpenState()
		}
		.onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in
			refreshMapWindowOpenState()
		}
	}

	/// A successful import turns on the overlay master toggle, enables the imported file's config,
	/// refreshes the styled overlays, and recenters the map on the transmitter.
	private func applyImportedCoverage(_ result: CoverageEstimateResult) {
		GeoJSONOverlayManager.shared.clearCache()
		mapOverlaysEnabled = true
		enabledOverlayConfigs.insert(result.metadata.id)
		rebuildGeoJSONOverlays()
		cameraCommand = ClusterMapCameraCommand(
			id: UUID(),
			region: coverageRegion(for: result),
			animated: true
		)
	}

	/// Frame the map on the imported coverage: fit its bounding box with padding so the whole
	/// overlay is visible with breathing room. Falls back to a fixed span around the transmitter
	/// when the GeoJSON yielded no bounds.
	private func coverageRegion(for result: CoverageEstimateResult) -> MKCoordinateRegion {
		guard let box = result.boundingBox else {
			return MKCoordinateRegion(
				center: result.coordinate,
				span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
			)
		}
		let padding = 1.3 // ~15% margin on each side
		let center = CLLocationCoordinate2D(
			latitude: (box.minLatitude + box.maxLatitude) / 2,
			longitude: (box.minLongitude + box.maxLongitude) / 2
		)
		let span = MKCoordinateSpan(
			latitudeDelta: min(max((box.maxLatitude - box.minLatitude) * padding, 0.01), 180),
			longitudeDelta: min(max((box.maxLongitude - box.minLongitude) * padding, 0.01), 360)
		)
		return MKCoordinateRegion(center: center, span: span)
	}

	/// The connected radio's LoRa config, used to prefill frequency / power / sensitivity.
	private var connectedLoRaConfig: LoRaConfigEntity? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)?.loRaConfig
	}

	/// The connected radio's primary channel name (for the firmware-accurate frequency-slot hash).
	private var connectedPrimaryChannelName: String {
		guard let num = accessoryManager.activeDeviceNum,
			  let node = getNodeInfo(id: num, context: context) else { return "LongFast" }
		if let primary = node.myInfo?.channels.first(where: { $0.index == 0 || $0.role == 1 }),
		   let name = primary.name, !name.isEmpty {
			return name
		}
		if node.loRaConfig?.usePreset == false { return "Custom" }
		let preset = ModemPresets(rawValue: Int(node.loRaConfig?.modemPreset ?? 0)) ?? .longFast
		return preset.androidChannelName
	}

	/// Open the estimate form from the map toolbar, prefilled from the connected radio and located at
	/// the current map centre (falling back to device / connected-device GPS).
	private func presentCoverageEstimateFromMap() {
		let center = visibleRegion?.center
		let coordinate = center ?? LocationsHandler.currentLocation ?? activeDeviceCoordinate
		let params = SitePlannerParameters.prefilled(
			name: "",
			coordinate: coordinate,
			loRaConfig: connectedLoRaConfig,
			primaryChannelName: connectedPrimaryChannelName
		)
		coverageSeed = CoverageEstimateSeed(parameters: params, nodeCoordinate: nil, mapCenter: center)
	}

	/// Consume a `.coverageEstimate` map-state hand-off. Called from `onChange(of: router.mapState)`,
	/// `onChange(of: router.selectedTab)`, and `onAppear` — mirroring `applyTraceRouteSelection` — so a
	/// hand-off from node detail isn't dropped when the Map tab mounts fresh and misses the change.
	private func consumeCoverageEstimateState() {
		guard case .map = router.selectedTab else { return }
		if case let .coverageEstimate(nodeNum)? = router.mapState {
			presentCoverageEstimate(forNode: nodeNum)
		}
	}

	/// Open the estimate form for a specific node (node-detail handoff), prefilled from the connected
	/// radio and located at the node's latest position, and recenter the map on it. Consumes the
	/// `.coverageEstimate` map state.
	private func presentCoverageEstimate(forNode nodeNum: Int64) {
		defer { router.mapState = nil }
		guard let node = getNodeInfo(id: nodeNum, context: context) else { return }
		let coordinate = node.latestPosition?.nodeCoordinate
		let name = node.user?.displayLongName ?? node.user?.shortName ?? ""
		let params = SitePlannerParameters.prefilled(
			name: name,
			coordinate: coordinate,
			loRaConfig: connectedLoRaConfig,
			primaryChannelName: connectedPrimaryChannelName
		)
		coverageSeed = CoverageEstimateSeed(parameters: params, nodeCoordinate: coordinate, mapCenter: visibleRegion?.center)
		if let coordinate {
			cameraCommand = ClusterMapCameraCommand(
				id: UUID(),
				region: MKCoordinateRegion(
					center: coordinate,
					span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
				),
				animated: true
			)
		}
	}

	private func refreshMapWindowOpenState() {
		// One primary app window plus one detached window means > 1 attached scenes.
		let attachedScenes = UIApplication.shared.connectedScenes.filter { $0.activationState != .unattached }
		isMapWindowOpen = attachedScenes.count > 1
	}

	/// Quantized camera key so `.onChange` can react to pan/zoom settles even though
	/// `MKCoordinateRegion` isn't `Equatable`. Same quantization the position-state key uses.
	private var regionRefreshKey: Int64 {
		var key: Int64 = 0
		if let visibleRegion {
			combine(&key, Int64((visibleRegion.center.latitude * 10_000).rounded(.towardZero)))
			combine(&key, Int64((visibleRegion.center.longitude * 10_000).rounded(.towardZero)))
			combine(&key, Int64((visibleRegion.span.latitudeDelta * 10_000).rounded(.towardZero)))
			combine(&key, Int64((visibleRegion.span.longitudeDelta * 10_000).rounded(.towardZero)))
		}
		return key
	}

	private var filterRefreshKey: Int64 {
		var key: Int64 = 0
		combine(&key, preciseLocationsOnly ? 1 : 0)
		combine(&key, stableStringKey(filters.searchText.lowercased()))
		combine(&key, filters.isOnline ? 1 : 0)
		combine(&key, filters.isPkiEncrypted ? 1 : 0)
		combine(&key, filters.isFavorite ? 1 : 0)
		combine(&key, filters.isIgnored ? 1 : 0)
		combine(&key, filters.isEnvironment ? 1 : 0)
		combine(&key, filters.distanceFilter ? 1 : 0)
		combine(&key, Int64(filters.maxDistance.rounded(.towardZero)))
		combine(&key, Int64(filters.hopsAway.rounded(.towardZero)))
		combine(&key, filters.roleFilter ? 1 : 0)
		for role in filters.deviceRoles.sorted() {
			combine(&key, Int64(role))
		}
		combine(&key, filters.viaLora ? 1 : 0)
		combine(&key, filters.viaMqtt ? 1 : 0)
		return key
	}

		private func refreshVisiblePositionSnapshots(from positions: [PositionEntity]) {
			visiblePositionSnapshots = makePositionSnapshots(from: positions)
			spreadOverrides = computeSpreadOverrides(visiblePositionSnapshots)
			frameInitialRegionIfNeeded()
			rebuildOverlays()
		}

	/// Fan out nodes that sit on (nearly) the same spot into a small ring so a stacked cluster always
	/// breaks into individual, tappable node circles instead of an un-splittable pin. The accuracy
	/// circle stays at the true location; only the pin's display coordinate is offset.
	///
	/// Grouping is DISTANCE-based (not cell-quantized): any nodes within `mergeMeters` of each other
	/// are fanned out together. A fixed grid missed two real cases that produced un-splittable "2"
	/// clusters — pairs straddling a cell boundary, and same-site radios whose GPS fixes jitter a few
	/// meters apart — because they're far too close to ever separate by zooming. Union-find over a
	/// coarse neighbor grid keeps this ~O(n) on the density-limited snapshot set.
	private func computeSpreadOverrides(_ snaps: [MeshMapPositionSnapshot]) -> [Int64: CLLocationCoordinate2D] {
		guard snaps.count > 1 else { return [:] }
		let metersPerDegLat = 111_320.0
		/// Pins within this distance are treated as "stacked" and fanned out. Comfortably above GPS
		/// jitter and the old ~1 m cell so boundary/jitter pairs are reliably caught.
		let mergeMeters = 16.0

		// Project to a local meter plane (accurate enough at city scale) for distance + bucketing.
		let pts = snaps.map { snap -> (x: Double, y: Double) in
			let metersPerDegLon = metersPerDegLat * cos(snap.coordinate.latitude * .pi / 180)
			return (snap.coordinate.longitude * metersPerDegLon, snap.coordinate.latitude * metersPerDegLat)
		}
		// Coarse grid (cell == mergeMeters) so each node only compares against neighboring cells.
		func cellKey(_ gx: Int, _ gy: Int) -> Int64 { Int64(gx) &* 4_000_000 &+ Int64(gy) }
		let grid = pts.map { (Int(($0.x / mergeMeters).rounded(.down)), Int(($0.y / mergeMeters).rounded(.down))) }
		var buckets: [Int64: [Int]] = [:]
		for (i, cell) in grid.enumerated() { buckets[cellKey(cell.0, cell.1), default: []].append(i) }

		// Union-find: merge any pair within mergeMeters (checking the node's cell + its 8 neighbors).
		var parent = Array(0..<snaps.count)
		func find(_ a: Int) -> Int { var r = a; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
		func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb } }
		let mergeSq = mergeMeters * mergeMeters
		for i in 0..<snaps.count {
			let (gx, gy) = grid[i]
			for dx in -1...1 { for dy in -1...1 {
				guard let neighbors = buckets[cellKey(gx + dx, gy + dy)] else { continue }
				for j in neighbors where j > i {
					let ddx = pts[i].x - pts[j].x, ddy = pts[i].y - pts[j].y
					if ddx * ddx + ddy * ddy <= mergeSq { union(i, j) }
				}
			}}
		}

		// Collect groups by root, fan each group with >1 member around its centroid.
		var groups: [Int: [Int]] = [:]
		for i in 0..<snaps.count { groups[find(i), default: []].append(i) }
		var overrides: [Int64: CLLocationCoordinate2D] = [:]
		for members in groups.values where members.count > 1 {
			let sorted = members.sorted { snaps[$0].nodeNum < snaps[$1].nodeNum }
			let centerLat = sorted.reduce(0.0) { $0 + snaps[$1].coordinate.latitude } / Double(sorted.count)
			let centerLon = sorted.reduce(0.0) { $0 + snaps[$1].coordinate.longitude } / Double(sorted.count)
			let metersPerDegLon = max(1.0, metersPerDegLat * cos(centerLat * .pi / 180))
			// Grow the ring with crowd size so even a big pile stays individually tappable.
			let radius = 14.0 + Double(sorted.count) * 1.5
			for (index, member) in sorted.enumerated() {
				let angle = 2 * Double.pi * Double(index) / Double(sorted.count)
				overrides[snaps[member].nodeNum] = CLLocationCoordinate2D(
					latitude: centerLat + (radius * sin(angle)) / metersPerDegLat,
					longitude: centerLon + (radius * cos(angle)) / metersPerDegLon
				)
			}
		}
		return overrides
	}

	/// One-time initial camera framing. Centers on the phone's GPS (else the connected device's GPS,
	/// else the node centroid) and zooms out to fit nearby nodes -- capped at ~100 miles so we "start
	/// zoomed out but local." After it fires once the user drives the camera; we never re-frame, even
	/// as positions pour in.
	private func frameInitialRegionIfNeeded() {
		guard !didInitialFrame else { return }
		// Restore the user's last-viewed region first: anyone who has ever moved the map reopens
		// exactly where they left it, with no dependence on GPS / connected device / node data at
		// launch. This is the only branch that resolves the reported cold-open (0,0) default for a
		// location-denied user with no positioned nodes -- and it consumes the one-shot, so the user
		// still owns the camera immediately afterward.
		if let saved = savedMapRegion {
			didInitialFrame = true
			visibleRegion = saved
			cameraCommand = ClusterMapCameraCommand(id: UUID(), region: saved)
			return
		}
		// Frame from the same set the map actually shows, so "Precise Locations Only" doesn't start
		// the camera centered on hidden reduced-precision nodes.
		let nodeCoords = mapEligiblePositions.compactMap { $0.nodeCoordinate ?? $0.fuzzedNodeCoordinate }
		guard let center = LocationsHandler.currentLocation ?? activeDeviceCoordinate ?? coordinateCentroid(of: nodeCoords) else {
			return // No GPS and no nodes yet -- try again on the next refresh.
		}
		// ~100 miles is about 1.45 deg latitude; floor ~20 miles so a lone node still starts zoomed out.
		let maxSpan = 1.45, minSpan = 0.30
		var maxLat = 0.0, maxLon = 0.0
		for coord in nodeCoords {
			maxLat = max(maxLat, abs(coord.latitude - center.latitude))
			maxLon = max(maxLon, abs(coord.longitude - center.longitude))
		}
		let latDelta = min(max(maxLat * 2.5, minSpan), maxSpan)
		let lonDelta = min(max(maxLon * 2.5, minSpan), maxSpan)
		didInitialFrame = true
		let region = MKCoordinateRegion(
			center: center,
			span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
		)
		// Seed `visibleRegion` so content filtering reflects the frame immediately, and emit the
		// one-shot command that actually moves the map (the only programmatic camera move we make).
		visibleRegion = region
		cameraCommand = ClusterMapCameraCommand(id: UUID(), region: region)
	}

	/// The persisted last-viewed camera region, or `nil` when nothing valid has been saved yet
	/// (fresh install, or a degenerate/near-global region we deliberately never store).
	private var savedMapRegion: MKCoordinateRegion? {
		let latDelta = savedRegionSpanLatitude, lonDelta = savedRegionSpanLongitude
		guard latDelta > 0, lonDelta > 0 else { return nil }
		let lat = savedRegionCenterLatitude, lon = savedRegionCenterLongitude
		guard lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else {
			return nil
		}
		return MKCoordinateRegion(
			center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
			span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
		)
	}

	/// Persist the current camera region so the next launch reopens here. Deliberately skips the
	/// uninitialized/near-global region MapKit reports before the first real frame (its whole-world
	/// default approaches a 180-degree latitude span) so we never save the (0,0) cold-open we're
	/// fixing; genuine local pans/zooms always fall well under the guard.
	private func persistVisibleRegion() {
		guard let region = visibleRegion else { return }
		let latDelta = region.span.latitudeDelta, lonDelta = region.span.longitudeDelta
		guard latDelta > 0, latDelta < 90, lonDelta > 0, lonDelta < 180 else { return }
		let center = region.center
		guard center.latitude.isFinite, center.longitude.isFinite else { return }
		// Also reject MapKit's *intermediate* pre-interaction default, which parks a broad span on
		// (0,0). A wide region still centered at Null Island is the cold-open we're fixing -- never a
		// real data-driven frame (those are small-span) nor a user pan (whose center has moved off the
		// equator/prime meridian). A genuine local view near (0,0) is small-span and still saves.
		let nearNullIsland = abs(center.latitude) < 1 && abs(center.longitude) < 1
		guard !(nearNullIsland && (latDelta > 10 || lonDelta > 10)) else { return }
		savedRegionCenterLatitude = center.latitude
		savedRegionCenterLongitude = center.longitude
		savedRegionSpanLatitude = latDelta
		savedRegionSpanLongitude = lonDelta
	}

	/// Average of a coordinate list (nil when empty).
	private func coordinateCentroid(of coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
		guard !coords.isEmpty else { return nil }
		let lat = coords.reduce(0.0) { $0 + $1.latitude } / Double(coords.count)
		let lon = coords.reduce(0.0) { $0 + $1.longitude } / Double(coords.count)
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}

																/// Build user GeoJSON overlays: LineString/Polygon -> styled MKOverlay; Point -> a circle marker.
								/// Gated on the Map Overlays master toggle + the set of enabled uploaded files.
								/// Overlays passed to the map (empty off-screen so MapKit drops the trees). Built with += rather
								/// than a big `+` chain inside `body` so the SwiftUI type-checker doesn't time out.
								/// Single change-detector for everything that affects the vector overlays / markers, so one
								/// onChange rebuilds them all (keeps `body`'s modifier chain short enough to type-check).
								private var overlayInputsKey: String {
									var parts = [routesKey, waypointsKey]
									parts.append(showWaypoints ? "w1" : "w0")
									parts.append(showConvexHull ? "h1" : "h0")
									parts.append(mapOverlaysEnabled ? "o1" : "o0")
									parts.append(enableOfflineTiles ? "t1" : "t0")
									parts.append(colorScheme == .dark ? "d1" : "d0")
									parts.append(String(enabledOverlayConfigs.hashValue))
									parts.append(String(offlineVectors.revision))
									return parts.joined(separator: "|")
								}

								/// Rebuild every derived overlay/marker set (cheap; few items). Driven by overlayInputsKey.
								/// Re-bind the offline vector provider to the active archive (newest downloaded region, else the
								/// bundled demo) and decode it. Cheap no-op when the archive hasn't changed.
								private func reloadOfflineSource() {
									offlineVectors.reload(urls: offlineRegionURLs)
									decodeOfflineIfVisible()
								}

								/// Decode the offline region ONLY when it's on/near screen (lazy) — avoids the upfront
								/// 48-tile decode when the map opens somewhere else. updateIfNeeded() decodes once.
								private func decodeOfflineIfVisible() {
									if offlineRegionOnScreen() { offlineVectors.updateIfNeeded() }
								}

								/// Whether ANY offline vector coverage box intersects the current (padded) viewport.
								private func offlineRegionOnScreen() -> Bool {
									guard enableOfflineTiles, let region = visibleRegion, !offlineVectors.coverageAreas.isEmpty else { return false }
									let latPad = region.span.latitudeDelta * 0.75, lonPad = region.span.longitudeDelta * 0.75
									let vMinLat = region.center.latitude - latPad, vMaxLat = region.center.latitude + latPad
									let vMinLon = region.center.longitude - lonPad, vMaxLon = region.center.longitude + lonPad
									return offlineVectors.coverageAreas.contains { bounds in
										bounds.minLat <= vMaxLat && bounds.maxLat >= vMinLat && bounds.minLon <= vMaxLon && bounds.maxLon >= vMinLon
									}
								}

								private func rebuildAllMapContent() {
									reloadOfflineSource()
									rebuildOfflineVectorOverlays()
									rebuildRouteContent()
									rebuildWaypointDecorations()
									rebuildGeoJSONOverlays()
									rebuildOverlays()
								}

								private func combinedMapOverlays() -> [ClusterMapOverlay] {
									guard isMapVisible else { return [] }
									// Hide the offline vector basemap while a trace route is shown (jump + flyover) so
									// MapKit doesn't re-rasterize all that geometry at the new region; restored on clear.
									var result = selectedTraceRoute != nil ? [] : offlineVectorOverlays
									result += routeOverlays
									result += tracerouteOverlays
									result += mapOverlays
									result += geoJSONOverlays
									result += geofenceOverlays
									return result
								}

								private func combinedMapDecorations() -> [ClusterMapDecoration] {
									guard isMapVisible else { return [] }
									var result = routeDecorations
									result += tracerouteDecorations
									result += waypointDecorations
									result += geoJSONDecorations
									return result
								}

								private func rebuildGeoJSONOverlays() {
						let key = "\(mapOverlaysEnabled)|\(enabledOverlayConfigs.hashValue)"
						guard key != lastGeoJSONKey else { return }
						lastGeoJSONKey = key
									guard mapOverlaysEnabled, !enabledOverlayConfigs.isEmpty else {
										if !geoJSONOverlays.isEmpty { geoJSONOverlays = [] }
										if !geoJSONDecorations.isEmpty { geoJSONDecorations = [] }
										return
									}
									var overlays: [ClusterMapOverlay] = []
									var decorations: [ClusterMapDecoration] = []
									for styled in GeoJSONOverlayManager.shared.loadStyledFeaturesForConfigs(enabledOverlayConfigs) {
										let stroke = styled.strokeStyle
										let style = ClusterMapOverlayStyle(
											strokeUIColor: UIColor(styled.strokeColor),
											fillUIColor: UIColor(styled.fillColor),
											lineWidth: stroke.lineWidth,
											lineDash: stroke.dash.isEmpty ? nil : stroke.dash.map { NSNumber(value: Double($0)) },
											lineCap: stroke.lineCap
										)
										if let overlay = styled.createOverlay() {
											overlays.append(ClusterMapOverlay(id: "geojson-\(styled.id)", overlay: overlay, style: style))
										} else {
											// Point yields one marker; MultiPoint yields one per sub-coordinate.
											let radius = styled.feature.markerRadius
											for (index, coordinate) in styled.feature.markerCoordinates.enumerated() {
												decorations.append(ClusterMapDecoration(
													id: "geojson-pt-\(styled.id)-\(index)",
													coordinate: coordinate,
													content: AnyView(
														Circle()
															.fill(styled.fillColor)
															.overlay(Circle().stroke(styled.strokeColor, style: stroke))
															.frame(width: radius * 2, height: radius * 2)
													)
												))
											}
										}
									}
									geoJSONOverlays = overlays
									geoJSONDecorations = decorations
								}

/// Build tappable waypoint markers (icon bubble) from saved waypoints; tap -> open the form.
				private func rebuildWaypointDecorations() {
					let key = "\(showWaypoints)|\(waypointsKey)"
					guard key != lastWaypointKey else { return }
					lastWaypointKey = key
					guard showWaypoints else {
						if !waypointDecorations.isEmpty { waypointDecorations = [] }
						if !geofenceOverlays.isEmpty { geofenceOverlays = [] }
						return
					}
					let visibleWaypoints = allWaypoints.filter { $0.expire == nil || $0.expire! >= Date.now }
					geofenceOverlays = buildGeofenceOverlays(from: visibleWaypoints)
					waypointDecorations = visibleWaypoints.map { waypoint in
						let icon = String(UnicodeScalar(Int(waypoint.icon)) ?? "📍")
						return ClusterMapDecoration(
							id: "waypoint-\(waypoint.persistentModelID.hashValue)",
							coordinate: waypoint.mapCoordinate,
							content: AnyView(CircleText(text: icon, color: .orange, circleSize: 36)),
							onTap: { selectedNode = nil; editingWaypoint = nil; selectedWaypoint = waypoint }
						)
					}
				}

				/// Build geofence overlays (radius circle + bounding-box rectangle) for any waypoint
				/// that defines a geofence.
				private func buildGeofenceOverlays(from waypoints: [WaypointEntity]) -> [ClusterMapOverlay] {
					var result: [ClusterMapOverlay] = []
					let style = ClusterMapOverlayStyle(
						strokeUIColor: UIColor.systemOrange,
						fillUIColor: UIColor.systemOrange.withAlphaComponent(0.12),
						lineWidth: 2
					)
					for waypoint in waypoints {
						let key = waypoint.persistentModelID.hashValue
						if waypoint.geofenceRadius > 0, let center = waypoint.waypointCoordinate {
							result.append(ClusterMapOverlay(
								id: "geofence-circle-\(key)",
								overlay: MKCircle(center: center, radius: CLLocationDistance(waypoint.geofenceRadius)),
								style: style
							))
						}
						if var corners = waypoint.boundingBoxCoordinates {
							result.append(ClusterMapOverlay(
								id: "geofence-box-\(key)",
								overlay: MKPolygon(coordinates: &corners, count: corners.count),
								style: style
							))
						}
					}
					return result
				}

				/// Long-press on empty map -> a new in-memory waypoint at that point, opening the edit form.
				private func beginNewWaypoint(at coordinate: CLLocationCoordinate2D) {
					let waypoint = WaypointEntity()
					waypoint.latitudeI = Int32(coordinate.latitude * 1e7)
					waypoint.longitudeI = Int32(coordinate.longitude * 1e7)
					waypoint.expire = Date.now.addingTimeInterval(60 * 480)
					waypoint.id = 0
					selectedNode = nil
					selectedWaypoint = nil
					editingWaypoint = waypoint
				}

/// Build route polylines (route color) + start (green) / finish (black) markers from the enabled
		/// saved routes. Stable objects, rebuilt only when `routesKey` changes so the diff is a no-op.
		private func rebuildRouteContent() {
			guard routesKey != lastRouteKey else { return }
			lastRouteKey = routesKey
			var overlays: [ClusterMapOverlay] = []
			var decorations: [ClusterMapDecoration] = []
			for route in routes {
				let coords = route.locations.compactMap { $0.locationCoordinate }
				guard coords.count >= 2 else { continue }
				let key = route.persistentModelID.hashValue
				var line = coords
				overlays.append(ClusterMapOverlay(
					id: "route-\(key)",
					overlay: MKPolyline(coordinates: &line, count: line.count),
					style: ClusterMapOverlayStyle(strokeUIColor: UIColor(hex: UInt32(route.color)), fillUIColor: nil, lineWidth: 3, lineCap: .round)
				))
				if let start = coords.first {
					decorations.append(ClusterMapDecoration(id: "route-start-\(key)", coordinate: start,
					                                        content: AnyView(RouteEndpointMarker(color: .green))))
				}
				if let finish = coords.last {
					decorations.append(ClusterMapDecoration(id: "route-finish-\(key)", coordinate: finish,
					                                        content: AnyView(RouteEndpointMarker(color: .black))))
				}
			}
			routeOverlays = overlays
			routeDecorations = decorations
		}

	/// Resolve the trace route requested via `router.mapState` (a `meshtastic:///map?tracerouteId=`
	/// deep link), draw it, and frame the camera around it. Clears any drawn route when the map
	/// state moves elsewhere.
	private func applyTraceRouteSelection() {
		guard case .map = router.selectedTab else { return }
		if case let .traceRoute(id)? = router.mapState {
			let isNewSelection = selectedTraceRoute?.id != id
			if isNewSelection {
				selectedTraceRoute = getTraceRoute(id: id, context: context)
			}
			rebuildTraceRouteContent()
			frameTraceRoute()
		} else if selectedTraceRoute != nil {
			flyover.stop(restoreCamera: false)
			selectedTraceRoute = nil
			rebuildTraceRouteContent()
		}
	}

	/// Stop drawing the trace route and forget the deep-link selection.
	private func clearTraceRoute() {
		flyover.stop(restoreCamera: false)
		selectedTraceRoute = nil
		router.mapState = nil
		rebuildTraceRouteContent()
	}

	/// Ordered coordinates for a flythrough: out along the forward path, then back along the return
	/// path (skipping the shared target endpoint) so it reads as a round trip.
	/// The flyover legs for a route: the forward path, then (if present) the return path. The flyover
	/// flies them in turn with a slow landing between.
	private func traceRouteFlyoverLegs(for route: TraceRouteEntity) -> [[(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance)]] {
		var legs: [[(coordinate: CLLocationCoordinate2D, altitude: CLLocationDistance)]] = []
		let forward = route.forwardLocationPath
		if forward.count >= 2 { legs.append(forward) }
		let back = route.backLocationPath
		if back.count >= 2 { legs.append(back) }
		return legs
	}

	/// Build the forward (solid) + return (dashed) polylines and origin/target markers for the
	/// selected trace route. Each leg is colored by that hop's SNR using the same signal-meter math
	/// as the LoRa signal indicator (green/yellow/orange/red). Limited to nodes with a snapshot.
	private func rebuildTraceRouteContent() {
		let key = selectedTraceRoute.map { "\($0.id)|\($0.nodePositions.count)" } ?? "none"
		guard key != lastTraceRouteKey else { return }
		lastTraceRouteKey = key
		guard let route = selectedTraceRoute else {
			if !tracerouteOverlays.isEmpty { tracerouteOverlays = [] }
			if !tracerouteDecorations.isEmpty { tracerouteDecorations = [] }
			return
		}
		var overlays: [ClusterMapOverlay] = []
		var decorations: [ClusterMapDecoration] = []
		let idKey = route.persistentModelID.hashValue
		let modemPreset = ModemPresets(rawValue: UserDefaults.modemPreset) ?? .longFast

		// Forward (solid) — one polyline per leg, colored by the SNR measured at the node it arrives at.
		let forward = route.forwardSignalPath
		if forward.count >= 2 {
			for i in 1..<forward.count {
				var seg = [forward[i - 1].coordinate, forward[i].coordinate]
				overlays.append(ClusterMapOverlay(
					id: "traceroute-fwd-\(idKey)-\(i)",
					overlay: MKPolyline(coordinates: &seg, count: 2),
					style: ClusterMapOverlayStyle(strokeUIColor: UIColor(getSnrColor(snr: forward[i].snr, preset: modemPreset)), fillUIColor: nil, lineWidth: 4, lineCap: .round, directional: true)
				))
			}
		}
		// Return (dashed) — same per-leg signal coloring.
		let back = route.backSignalPath
		if back.count >= 2 {
			for i in 1..<back.count {
				var seg = [back[i - 1].coordinate, back[i].coordinate]
				overlays.append(ClusterMapOverlay(
					id: "traceroute-back-\(idKey)-\(i)",
					overlay: MKPolyline(coordinates: &seg, count: 2),
					style: ClusterMapOverlayStyle(strokeUIColor: UIColor(getSnrColor(snr: back[i].snr, preset: modemPreset)), fillUIColor: nil, lineWidth: 3, lineDash: [2, 8], lineCap: .round, directional: true)
				))
			}
		}
		let byNum = route.nodePositionsByNum
		if let origin = byNum[route.fromNum]?.coordinate {
			decorations.append(ClusterMapDecoration(id: "traceroute-origin-\(idKey)", coordinate: origin,
			                                        content: AnyView(RouteEndpointMarker(color: .green))))
		}
		if let target = byNum[route.toNum]?.coordinate {
			decorations.append(ClusterMapDecoration(id: "traceroute-target-\(idKey)", coordinate: target,
			                                        content: AnyView(RouteEndpointMarker(color: .red))))
		}
		tracerouteOverlays = overlays
		tracerouteDecorations = decorations
	}

	/// Center/zoom the camera to fit the selected trace route's nodes. Drives the MKMapView directly
	/// (not the `visibleRegion` binding) so the framing doesn't kick off a region-binding feedback
	/// loop that re-renders `body` repeatedly (which pegs the main thread on Mac Catalyst).
	private func frameTraceRoute() {
		guard let route = selectedTraceRoute else { return }
		let coords = route.forwardCoordinates + route.backCoordinates
		guard !coords.isEmpty else { return }
		let lats = coords.map { $0.latitude }, lons = coords.map { $0.longitude }
		guard let minLat = lats.min(), let maxLat = lats.max(),
		      let minLon = lons.min(), let maxLon = lons.max() else { return }
		let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
		let span = MKCoordinateSpan(
			latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
			longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
		)
		let region = MKCoordinateRegion(center: center, span: span)
		if let mapView = flyover.mapView {
			mapView.setRegion(region, animated: false)
		} else {
			visibleRegion = region
		}
	}

/// Build the offline basemap as native MKOverlays (earth fill + water/park fills + arterial roads)
	/// from the decoded vector tiles, using the same slate/cream palette as the old SwiftUI map. Stable
	/// objects, rebuilt only on toggle/appearance/decode so the overlay diff is a no-op between renders.
	private func rebuildOfflineVectorOverlays() {
		let key = "\(enableOfflineTiles)|\(offlineVectors.isAvailable)|\(offlineVectors.revision)|\(colorScheme == .dark)"
		guard key != lastOfflineOverlaysKey else { return }
		lastOfflineOverlaysKey = key
		guard enableOfflineTiles, offlineVectors.isAvailable, !offlineVectors.coverageAreas.isEmpty else {
			if !offlineVectorOverlays.isEmpty { offlineVectorOverlays = [] }
			return
		}
		let dark = colorScheme == .dark
		var result: [ClusterMapOverlay] = []

		// 1) Earth base fill for each coverage box (so gaps read as land, not the Apple basemap).
		for (index, bounds) in offlineVectors.coverageAreas.enumerated() {
			var earth = [
				CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.minLon),
				CLLocationCoordinate2D(latitude: bounds.minLat, longitude: bounds.maxLon),
				CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.maxLon),
				CLLocationCoordinate2D(latitude: bounds.maxLat, longitude: bounds.minLon)
			]
			result.append(ClusterMapOverlay(
				id: "offline-earth-\(index)",
				overlay: MKPolygon(coordinates: &earth, count: earth.count),
				style: ClusterMapOverlayStyle(strokeUIColor: nil, fillUIColor: Self.offlineEarthColor(dark: dark), lineWidth: 0, level: .aboveRoads)
			))
		}

		// 2) Water / park fills, batched per role (parks under water).
		let fillsByRole = Dictionary(grouping: offlineVectors.polygons, by: { $0.role })
		for role in [OfflineFeatureRole.park, .green, .water] {
			guard let polys = fillsByRole[role], let fill = Self.offlineFillColor(role, dark: dark) else { continue }
			let shapes = polys.compactMap { poly -> MKPolygon? in
				guard poly.coordinates.count >= 3 else { return nil }
				var coords = poly.coordinates
				return MKPolygon(coordinates: &coords, count: coords.count)
			}
			guard !shapes.isEmpty else { continue }
			result.append(ClusterMapOverlay(
				id: "offline-fill-\(role)",
				overlay: MKMultiPolygon(shapes),
				style: ClusterMapOverlayStyle(strokeUIColor: nil, fillUIColor: fill, lineWidth: 0, level: .aboveRoads)
			))
		}

		// 3) Roads, batched per role into MKMultiPolylines (keeps the dense grid to a few overlays).
		let roadsByRole = Dictionary(grouping: offlineVectors.roads, by: { $0.role })
		func roadMultiPolyline(_ role: OfflineFeatureRole) -> MKMultiPolyline? {
			guard let lines = roadsByRole[role] else { return nil }
			let shapes = lines.compactMap { line -> MKPolyline? in
				guard line.coordinates.count >= 2 else { return nil }
				var coords = line.coordinates
				return MKPolyline(coordinates: &coords, count: coords.count)
			}
			return shapes.isEmpty ? nil : MKMultiPolyline(shapes)
		}
		let roadClasses: [OfflineFeatureRole] = [.minorRoad, .mediumRoad, .majorRoad]
		// Casing pass (light mode only) gives the Apple white-road-with-outline look.
		for role in roadClasses {
			guard let casing = Self.offlineRoadCasingColor(role, dark: dark), let multi = roadMultiPolyline(role) else { continue }
			result.append(ClusterMapOverlay(
				id: "offline-road-casing-\(role)",
				overlay: multi,
				style: ClusterMapOverlayStyle(strokeUIColor: casing, fillUIColor: nil, lineWidth: Self.offlineRoadCasingWidth(role), lineCap: .round, level: .aboveRoads)
			))
		}
		// Fill pass — white centerlines (light) / lighter-than-land gray (dark).
		for role in roadClasses {
			guard let fill = Self.offlineRoadFillColor(role, dark: dark), let multi = roadMultiPolyline(role) else { continue }
			result.append(ClusterMapOverlay(
				id: "offline-road-fill-\(role)",
				overlay: multi,
				style: ClusterMapOverlayStyle(strokeUIColor: fill, fillUIColor: nil, lineWidth: Self.offlineRoadWidth(role), lineCap: .round, level: .aboveRoads)
			))
		}
		// Rail + admin boundaries (single dashed stroke, both modes).
		for role in [OfflineFeatureRole.rail, .boundary] {
			guard let color = Self.offlineLineColor(role, dark: dark), let multi = roadMultiPolyline(role) else { continue }
			result.append(ClusterMapOverlay(
				id: "offline-line-\(role)",
				overlay: multi,
				style: ClusterMapOverlayStyle(strokeUIColor: color, fillUIColor: nil, lineWidth: 1.0, lineDash: [2, 3], lineCap: .butt, level: .aboveRoads)
			))
		}

		offlineVectorOverlays = result
	}

	// MARK: Offline basemap palette (approximates Apple Maps Standard, light + dark)

	private static func offlineEarthColor(dark: Bool) -> UIColor {
		dark ? UIColor(red: 0.137, green: 0.137, blue: 0.145, alpha: 1)
			 : UIColor(red: 0.953, green: 0.945, blue: 0.929, alpha: 1)
	}

	private static func offlineFillColor(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		switch role {
		case .water: return dark ? UIColor(red: 0.094, green: 0.169, blue: 0.267, alpha: 1) : UIColor(red: 0.667, green: 0.831, blue: 0.953, alpha: 1)
		case .park, .green: return dark ? UIColor(red: 0.122, green: 0.176, blue: 0.133, alpha: 1) : UIColor(red: 0.776, green: 0.882, blue: 0.706, alpha: 1)
		case .land: return offlineEarthColor(dark: dark)
		default: return nil
		}
	}

	/// Road fill: white centerline (light) or a lighter-than-land gray (dark).
	private static func offlineRoadFillColor(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		switch role {
		case .majorRoad: return dark ? UIColor(red: 0.46, green: 0.46, blue: 0.49, alpha: 1) : .white
		case .mediumRoad: return dark ? UIColor(red: 0.38, green: 0.38, blue: 0.41, alpha: 1) : .white
		case .minorRoad: return dark ? UIColor(red: 0.31, green: 0.31, blue: 0.34, alpha: 1) : .white
		default: return nil
		}
	}

	/// Road casing (light mode only): a warm-gray outline that makes the white roads read on pale land.
	private static func offlineRoadCasingColor(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		guard !dark else { return nil }
		switch role {
		case .majorRoad, .mediumRoad, .minorRoad: return UIColor(red: 0.835, green: 0.824, blue: 0.800, alpha: 1)
		default: return nil
		}
	}

	private static func offlineRoadWidth(_ role: OfflineFeatureRole) -> CGFloat {
		switch role {
		case .majorRoad: return 3.0
		case .mediumRoad: return 2.2
		case .minorRoad: return 1.3
		default: return 1.0
		}
	}

	/// Casing is ~1.4 pt wider than the fill (about 0.7 pt of outline each side).
	private static func offlineRoadCasingWidth(_ role: OfflineFeatureRole) -> CGFloat {
		offlineRoadWidth(role) + 1.4
	}

	/// Rail / admin-boundary stroke color (single dashed line, both modes).
	private static func offlineLineColor(_ role: OfflineFeatureRole, dark: Bool) -> UIColor? {
		switch role {
		case .rail: return dark ? UIColor(red: 0.45, green: 0.46, blue: 0.49, alpha: 1) : UIColor(red: 0.62, green: 0.62, blue: 0.64, alpha: 1)
		case .boundary: return dark ? UIColor(red: 0.50, green: 0.46, blue: 0.56, alpha: 1) : UIColor(red: 0.66, green: 0.62, blue: 0.70, alpha: 1)
		default: return nil
		}
	}

/// Rebuild the vector overlays (accuracy circles + convex hull) from the current snapshots.
	/// Called on data change so the overlay objects are stable between renders. Ports the styling
	/// from MeshMapContent's reducedPrecisionMapCircles + convex hull.
	private func rebuildOverlays() {
		var result: [ClusterMapOverlay] = []

		// Reduced-precision accuracy circles, deduped by location + precision (lowest nodeNum wins).
		var lowestNumForKey: [ReducedPrecisionMapCircleKey: Int64] = [:]
		for snap in visiblePositionSnapshots where PositionEntity.reducedPrecisionBits ~= snap.precisionBits {
			let key = ReducedPrecisionMapCircleKey(latitudeI: snap.latitudeI, longitudeI: snap.longitudeI, precisionBits: snap.precisionBits)
			if let existing = lowestNumForKey[key] {
				if snap.nodeNum < existing { lowestNumForKey[key] = snap.nodeNum }
			} else {
				lowestNumForKey[key] = snap.nodeNum
			}
		}
		for (key, nodeNum) in lowestNumForKey {
			let radius = PositionPrecision(rawValue: Int(key.precisionBits))?.precisionMeters ?? 0
			guard radius > 0 else { continue }
			let center = CLLocationCoordinate2D(latitude: Double(key.latitudeI) / 1e7, longitude: Double(key.longitudeI) / 1e7)
			let color = UIColor(hex: UInt32(nodeNum))
			result.append(ClusterMapOverlay(
				id: "circle-\(nodeNum)",
				overlay: MKCircle(center: center, radius: radius),
				style: ClusterMapOverlayStyle(strokeUIColor: .white, fillUIColor: color.withAlphaComponent(0.25), lineWidth: 1)
			))
		}

		// Convex hull over LoRa (non-MQTT) nodes, when enabled.
		if showConvexHull {
			let loraCoords = visiblePositionSnapshots.filter { !$0.viaMqtt }.map(\.coordinate)
			if loraCoords.count > 2 {
				var hull = loraCoords.getConvexHull()
				if hull.count >= 3 {
					result.append(ClusterMapOverlay(
						id: "convexHull",
						overlay: MKPolygon(coordinates: &hull, count: hull.count),
						style: ClusterMapOverlayStyle(strokeUIColor: .systemBlue,
													  fillUIColor: UIColor.systemIndigo.withAlphaComponent(0.4),
													  lineWidth: 3)
					))
				}
			}
		}

		mapOverlays = result
	}

	private func makePositionSnapshots(from positions: [PositionEntity]) -> [MeshMapPositionSnapshot] {
		positions.compactMap { position -> MeshMapPositionSnapshot? in
			let coordinate: CLLocationCoordinate2D = if position.isPreciseLocation {
				position.nodeCoordinate ?? LocationsHandler.DefaultLocation
			} else {
				position.fuzzedNodeCoordinate ?? LocationsHandler.DefaultLocation
			}
			let precisionBits = position.precisionBits
			guard PositionEntity.reducedPrecisionBits ~= precisionBits || precisionBits == 32 else { return nil }
			let node = position.nodePosition
			let nodeNum = node?.num ?? 0
				return MeshMapPositionSnapshot(
					id: nodeNum,
					coordinate: coordinate,
					latitudeI: position.latitudeI,
					longitudeI: position.longitudeI,
				precisionBits: precisionBits,
				nodeNum: nodeNum,
				longName: node?.user?.longName ?? "?",
				shortName: node?.user?.shortName,
				isOnline: node?.isOnline ?? false,
				viaMqtt: node?.viaMqtt ?? true,
				calculatedDelay: Double(nodeNum.magnitude % 100) / 100.0 * 0.5
			)
		}
	}

	private func densityLimitedPositions(_ positions: [PositionEntity]) -> [PositionEntity] {
		guard positions.count > denseMapPositionLimit else { return positions }
		let activeNodeNum = Int64(accessoryManager.activeDeviceNum ?? 0)
		var pinnedPositions: [PositionEntity] = []
		var onlinePositions: [PositionEntity] = []
		var regularPositions: [PositionEntity] = []
		pinnedPositions.reserveCapacity(min(positions.count, denseMapPositionLimit))
		onlinePositions.reserveCapacity(min(positions.count, denseMapPositionLimit))
		regularPositions.reserveCapacity(positions.count)

		for position in positions.sorted(by: spatiallyPrecedes) {
			let node = position.nodePosition
			if node?.num == activeNodeNum || node?.favorite == true {
				pinnedPositions.append(position)
			} else if node?.isOnline == true {
				onlinePositions.append(position)
			} else {
				regularPositions.append(position)
			}
		}

		if pinnedPositions.count >= denseMapPositionLimit {
			return Array(pinnedPositions.prefix(denseMapPositionLimit))
		}

		let onlineLimit = denseMapPositionLimit - pinnedPositions.count
		let sampledOnline = evenlySampled(onlinePositions, limit: onlineLimit)
		let regularLimit = denseMapPositionLimit - pinnedPositions.count - sampledOnline.count
		return pinnedPositions + sampledOnline + evenlySampled(regularPositions, limit: regularLimit)
	}

	private func spatiallyPrecedes(_ lhs: PositionEntity, _ rhs: PositionEntity) -> Bool {
		let lhsLatitudeBucket = lhs.latitudeI / 50_000
		let rhsLatitudeBucket = rhs.latitudeI / 50_000
		if lhsLatitudeBucket != rhsLatitudeBucket {
			return lhsLatitudeBucket < rhsLatitudeBucket
		}
		let lhsLongitudeBucket = lhs.longitudeI / 50_000
		let rhsLongitudeBucket = rhs.longitudeI / 50_000
		if lhsLongitudeBucket != rhsLongitudeBucket {
			return lhsLongitudeBucket < rhsLongitudeBucket
		}
		return (lhs.nodePosition?.num ?? 0) < (rhs.nodePosition?.num ?? 0)
	}

	private func evenlySampled(_ positions: [PositionEntity], limit: Int) -> [PositionEntity] {
		guard limit > 0, positions.count > limit else { return positions }
		let stride = Double(positions.count) / Double(limit)
		var result: [PositionEntity] = []
		result.reserveCapacity(limit)
		var nextIndex = 0.0
		for (index, position) in positions.enumerated() where Double(index) >= nextIndex {
			result.append(position)
			nextIndex += stride
			if result.count == limit { break }
		}
		return result
	}

	private func stableStringKey(_ text: String) -> Int64 {
		var key: Int64 = 0
		for scalar in text.unicodeScalars {
			combine(&key, Int64(scalar.value))
		}
		return key
	}

	private func combine(_ key: inout Int64, _ value: Int64) {
		key = key &* 31 &+ value
	}

	// moves the map to a new coordinate
	private func centerMapAt(coordinate: CLLocationCoordinate2D) {
		withAnimation(.easeInOut(duration: 0.2), {
			position = .camera(
				MapCamera(
					centerCoordinate: coordinate, // Set new center
					distance: distance,          // Preserve current zoom distance
					heading: 0,                  // align north
					pitch: 0                     // set view to top down
				)
			)
		})
	}
}

private extension PositionEntity {
	func isInMapRegion(_ region: MKCoordinateRegion, paddingMultiplier: Double) -> Bool {
		let latitude = Double(latitudeI) / 1e7
		let longitude = Double(longitudeI) / 1e7
		let latitudeDelta = max(region.span.latitudeDelta * paddingMultiplier, 0.01)
		let longitudeDelta = max(region.span.longitudeDelta * paddingMultiplier, 0.01)
		let minLatitude = region.center.latitude - latitudeDelta / 2
		let maxLatitude = region.center.latitude + latitudeDelta / 2
		guard latitude >= minLatitude && latitude <= maxLatitude else { return false }

		let minLongitude = region.center.longitude - longitudeDelta / 2
		let maxLongitude = region.center.longitude + longitudeDelta / 2
		if minLongitude < -180 {
			return longitude >= minLongitude + 360 || longitude <= maxLongitude
		}
		if maxLongitude > 180 {
			return longitude >= minLongitude || longitude <= maxLongitude - 360
		}
		return longitude >= minLongitude && longitude <= maxLongitude
	}
}

// MARK: - Node pin (full pin, or a lightweight dot in dense mode)

/// Node annotation content. Renders the full animated pin normally, or a small colored dot when the
/// map is crowded (parity with the old map's densePositionAnnotations) to keep many pins cheap.
private struct MeshMapMKNodePin: View, Equatable {
	let nodeNum: Int64
	let shortName: String?
	let isOnline: Bool
	let calculatedDelay: Double
	let dense: Bool

	var body: some View {
		if dense {
			Circle()
				.fill(Color(UIColor(hex: UInt32(nodeNum))).opacity(isOnline ? 0.9 : 0.6))
				.overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
				.frame(width: isOnline ? 10 : 8, height: isOnline ? 10 : 8)
		} else {
			AnimatedNodePin(
				nodeColor: UIColor(hex: UInt32(nodeNum)),
				shortName: shortName,
				hasDetectionSensorMetrics: false,
				isOnline: isOnline,
				calculatedDelay: calculatedDelay,
				showsPulse: true
			)
		}
	}
}

// MARK: - Route start/finish marker

/// Small filled circle with a white border marking a route's start (green) or finish (black).
private struct RouteEndpointMarker: View {
	let color: Color

	var body: some View {
		Circle()
			.fill(color)
			.overlay(Circle().stroke(.white, lineWidth: 3))
			.frame(width: 15, height: 15)
	}
}
