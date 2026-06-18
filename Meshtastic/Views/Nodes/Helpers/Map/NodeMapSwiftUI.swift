//
//  NodeMapSwiftUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/11/23.
//

import SwiftUI
import SwiftData
import CoreLocation
import MapKit

struct NodeMapContentSignature: Equatable {
	// Used to decide if NodeMapContent needs to be reevaluated.
	// Only include fields that are used within NodeMapContent (or approximations like positionCount and lastPositionTime).
	let nodeNum: Int64
	let positionCount: Int
	let lastPositionTime: Date?
	let showNodeHistory: Bool
	let showRouteLines: Bool
	let showConvexHull: Bool
	let favorite: Bool
}

private struct NodeMapContentEquatableWrapper<Content: View>: View, Equatable {
	// Prevent slow, needless recomputation of NodeMapContent if the NodeMapContentSignature hasn't changed.
	let signature: NodeMapContentSignature
	@ViewBuilder let content: () -> Content
	static func == (lhs: NodeMapContentEquatableWrapper<Content>, rhs: NodeMapContentEquatableWrapper<Content>) -> Bool { lhs.signature == rhs.signature }
	var body: some View { content() }
}

struct NodeMapSwiftUI: View {
	private let visiblePositionLimit = 1_000

	@Environment(\.modelContext) private var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	/// Parameters
	@Bindable var node: NodeInfoEntity
	@State var showUserLocation: Bool = false
	@State private var positions: [PositionEntity] = []
	@State private var totalPositionCount = 0
	@State private var mostRecentPosition: PositionEntity?
	/// Map State User Defaults
	@AppStorage("meshMapShowNodeHistory") private var showNodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var showRouteLines = false
	@AppStorage("enableMapConvexHull") private var showConvexHull = false
	@AppStorage("enableMapTraffic") private var showTraffic: Bool = false
	@AppStorage("enableMapPointsOfInterest") private var showPointsOfInterest: Bool = false
	@AppStorage("mapLayer") private var selectedMapLayer: MapLayer = .hybrid
	// Map Configuration
	@Namespace var mapScope
	@State var mapStyle: MapStyle = MapStyle.hybrid(elevation: .flat, pointsOfInterest: .all, showsTraffic: true)
	@State var position = MapCameraPosition.automatic
	@State var distance = 10000.0
	@State var scene: MKLookAroundScene?
	@State var isLookingAround = false
	@State var isShowingAltitude = false
	@State var isEditingSettings = false
	@State var isShowingLegend = false
	@State var isMeshMap = false
	@State var enabledOverlayConfigs: Set<UUID> = Set()

	@State private var mapRegion = MKCoordinateRegion.init()

	var body: some View {
		if node.modelContext != nil {
			Group {
				if totalPositionCount > 0 {
					mapWithNavigation
				} else {
					ContentUnavailableView("No Positions", systemImage: "mappin.slash")
				}
			}
			.onChange(of: node) {
				handleNodeChange()
				refreshPositions()
			}
			.onAppear {
				handleAppear()
			}
		}
	}

	private var mapWithNavigation: some View {
		ZStack {
			MapReader { _ in
				configuredMap
			}
		}
		.navigationBarTitle(String((node.user?.shortName ?? "Unknown".localized) + (" \(totalPositionCount) points")), displayMode: .inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				ConnectedDevice(deviceConnected: accessoryManager.isConnected, name: accessoryManager.activeConnection?.device.shortName ?? "?")
			}
		}
	}

	private var configuredMap: some View {
		baseMap
			.overlay(alignment: .bottom) {
				lookAroundView
			}
			.overlay(alignment: .bottom) {
				altitudeView
			}
			.sheet(isPresented: $isEditingSettings) {
				MapSettingsForm(traffic: $showTraffic, pointsOfInterest: $showPointsOfInterest, mapLayer: $selectedMapLayer, meshMap: $isMeshMap, enabledOverlayConfigs: $enabledOverlayConfigs)
			}
			.sheet(isPresented: $isShowingLegend) {
				MapLegend(isMeshMap: false)
					.presentationDetents([.medium, .large])
					.presentationContentInteraction(.scrolls)
					#if !targetEnvironment(macCatalyst)
					.presentationDragIndicator(.visible)
					#endif
					.presentationBackgroundInteraction(.enabled(upThrough: .medium))
			}
			.onChange(of: selectedMapLayer) { _, newMapLayer in
				updateMapStyle(for: newMapLayer)
			}
			.onChange(of: showNodeHistory) {
				refreshPositions()
			}
			.onChange(of: showRouteLines) {
				refreshPositions()
			}
			.onChange(of: showConvexHull) {
				refreshPositions()
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				controlButtons
			}
			.onDisappear {
				UIApplication.shared.isIdleTimerDisabled = false
			}
	}

	private var mapContentSignature: NodeMapContentSignature {
		let positionCount = positions.count
		let lastPositionTime = positions.first?.time
		return NodeMapContentSignature(nodeNum: node.num, positionCount: positionCount, lastPositionTime: lastPositionTime, showNodeHistory: showNodeHistory, showRouteLines: showRouteLines, showConvexHull: showConvexHull, favorite: node.favorite)
	}

	private var baseMap: some View {
		NodeMapContentEquatableWrapper(signature: mapContentSignature) {
			Map(position: $position, bounds: MapCameraBounds(minimumDistance: 0, maximumDistance: .infinity), scope: mapScope) {
				NodeMapContent(node: node, positions: positions)
			}
		}
		.mapScope(mapScope)
		.mapStyle(mapStyle)
		.mapControls {
			MapScaleView(scope: mapScope)
				.mapControlVisibility(.visible)
			if showUserLocation {
				MapUserLocationButton(scope: mapScope)
					.mapControlVisibility(.visible)
			}
			MapPitchToggle(scope: mapScope)
				.mapControlVisibility(.visible)
			MapCompass(scope: mapScope)
				.mapControlVisibility(.visible)
		}
		.controlSize(.regular)
		.transaction { $0.animation = nil }
	}

	private var lookAroundView: some View {
		Group {
			if scene != nil && isLookingAround {
				LookAroundPreview(initialScene: scene)
					.frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 250 : 400)
					.clipShape(RoundedRectangle(cornerRadius: 12))
					.padding(.horizontal, 20)
			}
		}
	}

	private var altitudeView: some View {
		Group {
			if !isLookingAround && isShowingAltitude {
				PositionAltitudeChart(node: node)
					.frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 250 : 400)
					.clipShape(RoundedRectangle(cornerRadius: 12))
					.padding(.horizontal, 20)
			}
		}
	}

	private var controlButtons: some View {
		HStack {
			Button(action: {
				withAnimation {
					isShowingLegend = !isShowingLegend
				}
			}) {
				Image(systemName: isShowingLegend ? "map.fill" : "map")
			}
			.accessibilityLabel(isShowingLegend ? Text("Hide legend") : Text("Show legend"))
			.accessibilityHint(Text("Toggles the map legend"))
			.glassButtonStyle()

			Button(action: {
				withAnimation {
					isEditingSettings = !isEditingSettings
				}
			}) {
				Image(systemName: isEditingSettings ? "info.circle.fill" : "info.circle")
			}
			.glassButtonStyle()

			if scene != nil {
				Button(action: {
					if isShowingAltitude {
						isShowingAltitude = false
					}
					isLookingAround = !isLookingAround
				}) {
					Image(systemName: isLookingAround ? "binoculars.fill" : "binoculars")
				}
				.glassButtonStyle()
			}

			if totalPositionCount > 1 {
				Button(action: {
					if isLookingAround {
						isLookingAround = false
					}
					isShowingAltitude = !isShowingAltitude
				}) {
					Image(systemName: isShowingAltitude ? "mountain.2.fill" : "mountain.2")
				}
				.glassButtonStyle()
			}
		}
		.controlSize(.regular)
		.padding(5)
	}

	private func updateMapStyle(for layer: MapLayer) {
		UserDefaults.mapLayer = layer
		switch layer {
		case .standard:
			mapStyle = MapStyle.standard(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
		case .hybrid:
			mapStyle = MapStyle.hybrid(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
		case .satellite:
			mapStyle = MapStyle.imagery(elevation: .flat)
		case .offline:
			break
		}
	}

	/// Returns a camera distance that ensures the precision circle is fully visible.
	/// For precise positions (precisionBits == 32 or 0), returns the default distance.
	/// For imprecise positions, scales the precision radius so the circle fits comfortably.
	private func cameraDistanceForPrecision(_ position: PositionEntity?) -> Double {
		guard let position,
			  12...24 ~= position.precisionBits,
			  let pp = PositionPrecision(rawValue: Int(position.precisionBits)) else {
			return distance
		}
		// Camera distance needs to be roughly 4× the circle diameter to show it with padding
		let needed = pp.precisionMeters * 10.0
		return max(distance, needed)
	}

	private func handleNodeChange() {
		refreshPositions()
		isLookingAround = false
		isShowingAltitude = false
		let newMostRecent = mostRecentPosition
		if totalPositionCount > 1 {
			position = .automatic

		} else if let mrCoord = newMostRecent?.nodeCoordinate {
			let cameraDistance = cameraDistanceForPrecision(newMostRecent)
			position = .camera(MapCamera(centerCoordinate: mrCoord, distance: cameraDistance, heading: 0, pitch: 0))
		}
		if let newMostRecent, let coord = newMostRecent.nodeCoordinate {
			Task {
				scene = try? await fetchScene(for: coord)
			}
		}
	}

	private func handleAppear() {
		UIApplication.shared.isIdleTimerDisabled = true
		updateMapStyle(for: selectedMapLayer)
		refreshPositions()
		let mostRecent = mostRecentPosition
		if totalPositionCount > 1 {
			position = .automatic

		} else if let mrCoord = mostRecent?.nodeCoordinate {
			let cameraDistance = cameraDistanceForPrecision(mostRecent)
			position = .camera(MapCamera(centerCoordinate: mrCoord, distance: cameraDistance, heading: 0, pitch: 0))
		}
		if scene == nil, let mrCoord = mostRecent?.nodeCoordinate {
			Task {
				scene = try? await fetchScene(for: mrCoord)
			}
		}
	}

	private func refreshPositions() {
		totalPositionCount = node.positionCount(context: context)
		let limit = (showNodeHistory || showRouteLines || showConvexHull) ? visiblePositionLimit : 1
		let latestPositions = node.positionsSortedByTime(context: context, ascending: false, limit: limit)
		mostRecentPosition = latestPositions.first
		positions = limit == 1 ? latestPositions : Array(latestPositions.reversed())
	}

	/// Get the look around scene
	private func fetchScene(for coordinate: CLLocationCoordinate2D) async throws -> MKLookAroundScene? {
		let lookAroundScene = MKLookAroundSceneRequest(coordinate: coordinate)
		return try await lookAroundScene.scene
	}
}
