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

struct MeshMap: View {
	private let denseMapPositionLimit = 700

	@Environment(\.modelContext) private var context
	@Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
	@Environment(\.openWindow) private var openWindow
	@EnvironmentObject var accessoryManager: AccessoryManager

	@ObservedObject
	var router: Router
	var showOpenWindowButton: Bool = true

	/// Parameters
	@State var showUserLocation: Bool = true
	/// Map State User Defaults
	@AppStorage("enableMapTraffic") private var showTraffic: Bool = false
	@AppStorage("enableMapPointsOfInterest") private var showPointsOfInterest: Bool = false
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .standard
	/// Map overlay configs
	@State private var enabledOverlayConfigs: Set<UUID> = []
	// Map Configuration
	@Namespace var mapScope
	@AppStorage("meshMapDistance") private var meshMapDistance: Double = 800000
	@State var mapStyle: MapStyle = MapStyle.standard(elevation: .flat, emphasis: MapStyle.StandardEmphasis.muted, pointsOfInterest: .excludingAll, showsTraffic: false)
	@State var position = MapCameraPosition.automatic
	@State private var distance = 10000.0
	@State private var visibleRegion: MKCoordinateRegion?
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
	/// Filter
	@StateObject var filters = NodeFilterParameters()
	/// Track whether a detached Mesh Map window is currently open.
	@State private var isMapWindowOpen = false

	/// The connected device's latest coordinate, used as a fallback origin
	/// for distance filtering when the phone's location services are unavailable.
	private var activeDeviceCoordinate: CLLocationCoordinate2D? {
		guard let num = accessoryManager.activeDeviceNum else { return nil }
		return getNodeInfo(id: num, context: context)?.latestPosition?.nodeCoordinate
	}

	@Query(filter: #Predicate<PositionEntity> { $0.nodePosition != nil && $0.latest == true && $0.nodePosition?.ignored != true })
	private var allLatestPositions: [PositionEntity]

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
	private var isMapVisible: Bool {
		showOpenWindowButton ? router.selectedTab == .map : true
	}

	/// Positions actually passed to the map — empty when the tab is off-screen
	/// so MapKit drops its annotation view trees and reduces memory.
	private var visiblePositions: [PositionEntity] {
		guard isMapVisible else { return [] }

		guard let visibleRegion else {
			guard filters.isFiltering || !filters.searchText.isEmpty else {
				return densityLimitedPositions(allLatestPositions)
			}
			return densityLimitedPositions(filteredPositions(from: allLatestPositions))
		}
		let positionsInRegion = allLatestPositions.filter { $0.isInMapRegion(visibleRegion, paddingMultiplier: 1.4) }
		// MapKit can briefly report a stale/empty camera region while restoring
		// the tab or handling deep links. Never blank all pins because of that.
		let positions = positionsInRegion.isEmpty ? allLatestPositions : positionsInRegion
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
		for position in positions.prefix(64) {
			combine(&key, position.nodePosition?.num ?? 0)
			combine(&key, Int64(position.latitudeI))
			combine(&key, Int64(position.longitudeI))
			combine(&key, Int64(position.precisionBits))
		}
		if let last = positions.last {
			combine(&key, last.nodePosition?.num ?? 0)
			combine(&key, Int64(last.latitudeI))
				combine(&key, Int64(last.longitudeI))
			}
		return MeshMapVisiblePositionState(positions: positions, key: key)
	}

	var body: some View {
		let positionState = visiblePositionState
		NavigationStack {
			ZStack {
			MapReader { reader in
					Map(
						position: $position,
						bounds: MapCameraBounds(minimumDistance: 1, maximumDistance: .infinity),
						scope: mapScope
					) {
						MeshMapContent(
							showUserLocation: $showUserLocation,
								showTraffic: $showTraffic,
								showPointsOfInterest: $showPointsOfInterest,
								selectedMapLayer: $selectedMapLayer,
								selectedNode: $selectedNode,
								selectedWaypoint: $selectedWaypoint,
								enabledOverlayConfigs: $enabledOverlayConfigs,
								positionSnapshots: visiblePositionSnapshots
						)
					}
					.id(meshMapDistance)
					.mapScope(mapScope)
					.mapStyle(mapStyle)
					.mapControls {
						MapScaleView(scope: mapScope)
							.mapControlVisibility(.automatic)
						MapPitchToggle(scope: mapScope)
							.mapControlVisibility(.automatic)
						MapCompass(scope: mapScope)
							.mapControlVisibility(.automatic)
					}
					.controlSize(.regular)
					.offset(y: 100)
						.onMapCameraChange(frequency: MapCameraUpdateFrequency.onEnd, { context in
							// distance is only used for long-press waypoint creation, so we don't need continuous updates which touch @State and force rerenders as we pan and (for distance in particular) zoom around the map. onEnd is more than enough.
							distance = context.camera.distance
							visibleRegion = context.region
						})
					.onTapGesture(count: 1, perform: { position in
						newWaypointCoord = reader.convert(position, from: .local) ?? CLLocationCoordinate2D.init()
					})
					.gesture(
						LongPressGesture(minimumDuration: 0.5)
							.sequenced(before: SpatialTapGesture(coordinateSpace: .local))
							.onEnded { value in
								switch value {
								case let .second(_, tapValue):
									guard let point = tapValue?.location else {
										Logger.services.error("Unable to retreive tap location from gesture data.")
										return
									}

									guard let coordinate = reader.convert(point, from: .local) else {
										Logger.services.error("Unable to convert local point to coordinate on map.")
										return
									}
									centerMapAt(coordinate: coordinate)

									newWaypointCoord = coordinate
									editingWaypoint = WaypointEntity()
									editingWaypoint!.name = "Waypoint Pin"
									editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
									editingWaypoint!.latitudeI = Int32((newWaypointCoord?.latitude ?? 0) * 1e7)
									editingWaypoint!.longitudeI = Int32((newWaypointCoord?.longitude ?? 0) * 1e7)
									editingWaypoint!.expire = Date.now.addingTimeInterval(60 * 480)
									editingWaypoint!.id = 0
									Logger.services.debug("Long press occured at Lat: \(coordinate.latitude, privacy: .public) Long: \(coordinate.longitude, privacy: .public)")
								default: return
								}
							}
					)
					.ignoresSafeArea()
				}
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
				.safeAreaInset(edge: .bottom, alignment: .trailing) {
					HStack(spacing: 12) {
						Spacer()
						Button(action: {
							withAnimation {
								editingFilters = !editingFilters
							}
						}) {
							Image(systemName: filters.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
						}
						.accessibilityLabel(editingFilters ? "Hide node filters" : "Show node filters")
						.accessibilityHint(editingFilters ? "Hides the node filter options." : "Shows the node filter options.")
						.glassButtonStyle()
						Button(action: {
							withAnimation {
								showLegend = !showLegend
							}
						}) {
							Image(systemName: showLegend ? "map.fill" : "map")
						}
						.accessibilityLabel(showLegend ? "Hide map legend" : "Show map legend")
						.accessibilityHint(showLegend ? "Hides the map legend." : "Shows the map legend.")
						.glassButtonStyle()
						Button(action: {
							withAnimation {
								editingSettings = !editingSettings
							}
						}) {
							Image(systemName: editingSettings ? "info.circle.fill" : "info.circle")
						}
						.glassButtonStyle()
					}
					.controlSize(.regular)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
				}
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
						}
						ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
					}
				}
			}
			.toolbarBackground(.hidden, for: .navigationBar)
		}
			.onChange(of: positionState.key) {
				refreshVisiblePositionSnapshots(from: positionState.positions)
				filters.fallbackLocation = activeDeviceCoordinate
			}
			.onChange(of: allLatestPositions) {
				filters.fallbackLocation = activeDeviceCoordinate
			}
			.onChange(of: accessoryManager.activeDeviceNum) {
				filters.fallbackLocation = activeDeviceCoordinate
			}
			.onAppear {
				UIApplication.shared.isIdleTimerDisabled = true
				filters.fallbackLocation = activeDeviceCoordinate
				refreshMapWindowOpenState()
			// Initialize enabled overlay configs with all active files
			let activeFiles = GeoJSONOverlayManager.shared.getUploadedFilesWithState().filter { $0.isActive }
			enabledOverlayConfigs = Set(activeFiles.map { $0.id })

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
			refreshVisiblePositionSnapshots(from: positionState.positions)
		}
		.onDisappear(perform: {
			UIApplication.shared.isIdleTimerDisabled = false
			GeoJSONOverlayManager.shared.clearCache()
			visiblePositionSnapshots = []
		})
		.onChange(of: router.selectedTab) { _, newTab in
			if newTab == .map {
				filters.fallbackLocation = activeDeviceCoordinate
				refreshMapWindowOpenState()
				UIApplication.shared.isIdleTimerDisabled = true
				refreshVisiblePositionSnapshots()
			} else {
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

	private func refreshMapWindowOpenState() {
		// One primary app window plus one detached window means > 1 attached scenes.
		let attachedScenes = UIApplication.shared.connectedScenes.filter { $0.activationState != .unattached }
		isMapWindowOpen = attachedScenes.count > 1
	}

	private var filterRefreshKey: Int64 {
		var key: Int64 = 0
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

		private func refreshVisiblePositionSnapshots() {
			visiblePositionSnapshots = makePositionSnapshots(from: visiblePositions)
		}

		private func refreshVisiblePositionSnapshots(from positions: [PositionEntity]) {
			visiblePositionSnapshots = makePositionSnapshots(from: positions)
		}

	private func makePositionSnapshots(from positions: [PositionEntity]) -> [MeshMapPositionSnapshot] {
		positions.compactMap { position -> MeshMapPositionSnapshot? in
			let coordinate: CLLocationCoordinate2D = if position.isPreciseLocation {
				position.nodeCoordinate ?? LocationsHandler.DefaultLocation
			} else {
				position.fuzzedNodeCoordinate ?? LocationsHandler.DefaultLocation
			}
			let precisionBits = position.precisionBits
			guard 12...15 ~= precisionBits || precisionBits == 32 else { return nil }
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
