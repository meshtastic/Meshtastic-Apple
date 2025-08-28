//
//  NodeMapSwiftUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/11/23.
//

import SwiftUI
import CoreLocation
import MapKit

struct NodeMapSwiftUI: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var accessoryManager: AccessoryManager
	/// Parameters
	@ObservedObject var node: NodeInfoEntity
	@State var showUserLocation: Bool = false
	@State var positions: [PositionEntity] = []
	/// Map State User Defaults
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
	@State var isMeshMap = false
	@State var enabledOverlayConfigs: Set<UUID> = Set()

	@State private var mapRegion = MKCoordinateRegion.init()

	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
				  predicate: NSPredicate(
					format: "expire == nil || expire >= %@", Date() as NSDate
				  ), animation: .none)
	private var waypoints: FetchedResults<WaypointEntity>

	var body: some View {
		if node.hasPositions {
			mapWithNavigation
		} else {
			ContentUnavailableView("No Positions", systemImage: "mappin.slash")
		}
	}

	private var mapWithNavigation: some View {
		ZStack {
			MapReader { _ in
				configuredMap
			}
		}
		.navigationBarTitle(String((node.user?.shortName ?? "Unknown".localized) + (" \(node.positions?.count ?? 0) points")), displayMode: .inline)
		.navigationBarItems(trailing:
			ZStack {
				ConnectedDevice(
					deviceConnected: accessoryManager.isConnected,
					name: accessoryManager.activeConnection?.device.shortName ?? "?")
			})
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
			.onChange(of: selectedMapLayer) { _, newMapLayer in
				updateMapStyle(for: newMapLayer)
			}
			.onChange(of: node) {
				handleNodeChange()
			}
			.onAppear {
				handleAppear()
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				controlButtons
			}
			.onDisappear {
				UIApplication.shared.isIdleTimerDisabled = false
			}
	}

	private var baseMap: some View {
		Map(position: $position, bounds: MapCameraBounds(minimumDistance: 0, maximumDistance: .infinity), scope: mapScope) {
			NodeMapContent(node: node)
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
					isEditingSettings = !isEditingSettings
				}
			}) {
				Image(systemName: isEditingSettings ? "info.circle.fill" : "info.circle")
					.padding(.vertical, 5)
			}
			.tint(Color(UIColor.secondarySystemBackground))
			.foregroundColor(.accentColor)
			.buttonStyle(.borderedProminent)

			if scene != nil {
				Button(action: {
					if isShowingAltitude {
						isShowingAltitude = false
					}
					isLookingAround = !isLookingAround
				}) {
					Image(systemName: isLookingAround ? "binoculars.fill" : "binoculars")
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
			}

			if node.positions?.count ?? 0 > 1 {
				Button(action: {
					if isLookingAround {
						isLookingAround = false
					}
					isShowingAltitude = !isShowingAltitude
				}) {
					Image(systemName: isShowingAltitude ? "mountain.2.fill" : "mountain.2")
						.padding(.vertical, 5)
				}
				.tint(Color(UIColor.secondarySystemBackground))
				.foregroundColor(.accentColor)
				.buttonStyle(.borderedProminent)
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

	private func handleNodeChange() {
		isLookingAround = false
		isShowingAltitude = false
		let newMostRecent = node.positions?.lastObject as? PositionEntity
		if node.positions?.count ?? 0 > 1 {
			position = .automatic
		} else if let mrCoord = newMostRecent?.coordinate {
			position = .camera(MapCamera(centerCoordinate: mrCoord, distance: distance, heading: 0, pitch: 0))
		}
		if let newMostRecent {
			Task {
				scene = try? await fetchScene(for: newMostRecent.coordinate)
			}
		}
	}

	private func handleAppear() {
		UIApplication.shared.isIdleTimerDisabled = true
		updateMapStyle(for: selectedMapLayer)
		let mostRecent = node.positions?.lastObject as? PositionEntity
		if node.positions?.count ?? 0 > 1 {
			position = .automatic
		} else if let mrCoord = mostRecent?.coordinate {
			position = .camera(MapCamera(centerCoordinate: mrCoord, distance: distance, heading: 0, pitch: 0))
		}
		if scene == nil, let mrCoord = mostRecent?.coordinate {
			Task {
				scene = try? await fetchScene(for: mrCoord)
			}
		}
	}
	/// Get the look around scene
	private func fetchScene(for coordinate: CLLocationCoordinate2D) async throws -> MKLookAroundScene? {
		let lookAroundScene = MKLookAroundSceneRequest(coordinate: coordinate)
		return try await lookAroundScene.scene
	}
}
