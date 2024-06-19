//
//  NodeMapSwiftUI.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/11/23.
//

import SwiftUI
import CoreLocation
#if canImport(MapKit)
import MapKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct NodeMapSwiftUI: View {
	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
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
	@State var scene: MKLookAroundScene?
	@State var isLookingAround = false
	@State var isShowingAltitude = false
	@State var isEditingSettings = false
	@State var isMeshMap = false

	@State private var mapRegion = MKCoordinateRegion.init()

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(key: "name", ascending: false)],
		predicate: NSPredicate(
			format: "expire == nil || expire >= %@", Date() as NSDate
		),
		animation: .none
	)
	private var waypoints: FetchedResults<WaypointEntity>

	private var title: String {
		String((node.user?.shortName ?? "unknown".localized) + (" \(node.positions?.count ?? 0) points"))
	}
	
	private var mostRecent: PositionEntity? {
		node.positions?.lastObject as? PositionEntity
		
	}

	
	
	private var mapControls: some View {
		HStack {
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
	}

	private var mapAccessoryControls: some View {
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
			/// Look Around Button
			if self.scene != nil {
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
			/// Altitude Button
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

	private var connectedDeviceIndicator: some View {
		ConnectedDevice(
			bluetoothOn: bleManager.isSwitchedOn,
			deviceConnected: bleManager.connectedPeripheral != nil,
			name: bleManager.connectedPeripheral?.shortName ?? "?"
		)
	}

	var body: some View {
		if node.hasPositions {
			Map(
				position: $position,
				bounds: MapCameraBounds(
					minimumDistance: 1,
					maximumDistance: .infinity
				),
				scope: mapScope
			) {
				NodeMapContent(node: node)
			}
			.mapScope(mapScope)
			.mapStyle(mapStyle)
			.mapControls {
				mapControls
			}
			.controlSize(.regular)
			.overlay(alignment: .bottom) {
				if scene != nil, isLookingAround {
					LookAroundPreview(initialScene: scene)
						.frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 250 : 400)
						.clipShape(RoundedRectangle(cornerRadius: 12))
						.padding(.horizontal, 20)
				} else if isShowingAltitude {
					PositionAltitudeChart(node: node)
						.frame(height: UIDevice.current.userInterfaceIdiom == .phone ? 250 : 400)
						.clipShape(RoundedRectangle(cornerRadius: 12))
						.padding(.horizontal, 20)
				}
			}
			.sheet(isPresented: $isEditingSettings) {
				MapSettingsForm(
					traffic: $showTraffic,
					pointsOfInterest: $showPointsOfInterest,
					mapLayer: $selectedMapLayer,
					meshMap: $isMeshMap
				).onChange(of: (selectedMapLayer)) { newMapLayer in
					switch selectedMapLayer {
					case .standard:
						UserDefaults.mapLayer = newMapLayer
						mapStyle = MapStyle.standard(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
					case .hybrid:
						UserDefaults.mapLayer = newMapLayer
						mapStyle = MapStyle.hybrid(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
					case .satellite:
						UserDefaults.mapLayer = newMapLayer
						mapStyle = MapStyle.imagery(elevation: .flat)
					case .offline:
						return
					}
				}
			}
			.onChange(of: node) {
				isLookingAround = false
				isShowingAltitude = false
				if node.positions?.count ?? 0 > 1 {
					position = .automatic
				} else if let coordinate = mostRecent?.coordinate {
					position = .camera(MapCamera(centerCoordinate: coordinate, distance: 8000, heading: 0, pitch: 60))
				}
				if let coordinate = mostRecent?.coordinate {
					Task {
						scene = try await fetchScene(for: coordinate)
					}
				}
			}
			.onAppear {
				setupMapView()
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				mapAccessoryControls
			}
			.onDisappear {
				UIApplication.shared.isIdleTimerDisabled = false
			}
			.navigationBarTitle(title, displayMode: .inline)
			.navigationBarItems(trailing: connectedDeviceIndicator)
		} else {
			ContentUnavailableView("No Positions", systemImage: "mappin.slash")
		}
	}

	private func setupMapView() {
		UIApplication.shared.isIdleTimerDisabled = true
		if let coordinate = mostRecent?.coordinate {
			position = .camera(MapCamera(centerCoordinate: coordinate, distance: 12000, heading: 0, pitch: 60))
		} else {
			position = .automatic
		}
		switch selectedMapLayer {
		case .standard:
			mapStyle = MapStyle.standard(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
		case .hybrid:
			mapStyle = MapStyle.hybrid(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
		case .satellite:
			mapStyle = MapStyle.imagery(elevation: .flat)
		case .offline:
			mapStyle = MapStyle.hybrid(elevation: .flat, pointsOfInterest: showPointsOfInterest ? .all : .excludingAll, showsTraffic: showTraffic)
		}
	
		if scene == nil, let coordinate = mostRecent?.coordinate {
			Task {
				scene = try await fetchScene(for: coordinate)
			}
		}
	}

	/// Get the look around scene
	private func fetchScene(for coordinate: CLLocationCoordinate2D) async throws -> MKLookAroundScene? {
		let lookAroundScene = MKLookAroundSceneRequest(coordinate: coordinate)
		return try await lookAroundScene.scene
	}
}
