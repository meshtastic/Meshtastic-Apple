//
//  MeshMap.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/7/23.
//

import SwiftUI
import SwiftData
import CoreLocation
import Foundation
import OSLog
import MapKit

struct MeshMap: View {

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
	@State private var editingSettings = false
	@State private var editingFilters = false
	@State var selectedPosition: PositionEntity?
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

	@AppStorage("enableMapShowFavorites") private var showFavorites = false

	@Query(filter: #Predicate<PositionEntity> { $0.nodePosition != nil && $0.latest == true && $0.nodePosition?.ignored != true },
		   sort: \PositionEntity.time, order: .reverse)
	private var allLatestPositions: [PositionEntity]

	/// Positions filtered once per render, passed to MeshMapContent to avoid repeated relationship faulting.
	private var filteredPositions: [PositionEntity] {
		if showFavorites {
			return allLatestPositions.filter { $0.nodePosition?.favorite == true }
		}
		return allLatestPositions
	}

	/// Keep the detached map window fully populated while still starving the
	/// main tabbed Mesh Map when it is off-screen.
	private var isMapVisible: Bool {
		showOpenWindowButton ? router.selectedTab == .map : true
	}

	/// Positions actually passed to the map — empty when the tab is off-screen
	/// so MapKit drops its annotation view trees and reduces memory.
	private var visiblePositions: [PositionEntity] {
		isMapVisible ? filteredPositions : []
	}

	var body: some View {
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
							selectedPosition: $selectedPosition,
							selectedWaypoint: $selectedWaypoint,
							enabledOverlayConfigs: $enabledOverlayConfigs,
							filteredPositions: visiblePositions
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
				.sheet(item: $selectedPosition) { selection in
					if let nodeNum = selection.nodePosition?.num,
					   let node = getNodeInfo(id: Int64(nodeNum), context: context) {
						NavigationStack {
							NodeDetail(node: node, showMapLink: false)
						}
						#if targetEnvironment(macCatalyst)
						.overlay(alignment: .topTrailing) {
							Button {
								selectedPosition = nil
							} label: {
								ZStack {
									Circle()
										.fill(Color(white: 0.19))
									Image(systemName: "xmark")
										.resizable()
										.scaledToFit()
										.font(.body.weight(.bold))
										.scaleEffect(0.416)
										.foregroundColor(Color(white: 0.62))
								}
								.frame(width: 36, height: 36)
							}
							.buttonStyle(.plain)
							.padding(.top, 14)
							.padding(.trailing, 14)
						}
						#endif
						.presentationDetents([.large])
						.presentationDragIndicator(.visible)
					}
				}
				.sheet(item: $selectedWaypoint) { selection in
					WaypointForm(waypoint: selection)
						.padding()
						.presentationDetents([.large]) // full screen
						.presentationDragIndicator(.visible)
				}
				.sheet(item: $editingWaypoint) { selection in
					WaypointForm(waypoint: selection, editMode: true)
						.padding()
						.presentationDetents([.large])
						.presentationDragIndicator(.visible)
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
						filters: filters
					)
				}
				.sheet(isPresented: $showLegend) {
					MapLegend(isMeshMap: true)
						.presentationDetents([.large])
						.presentationContentInteraction(.scrolls)
						.presentationDragIndicator(.visible)
						.presentationBackgroundInteraction(.enabled(upThrough: .medium))
				}
				.safeAreaInset(edge: .bottom, alignment: .trailing) {
					HStack {
						Spacer()
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
					.padding(5)
				}
			}
			.navigationBarItems(leading: MeshtasticLogo(), trailing: HStack {
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
			})
			.toolbarBackground(.hidden, for: .navigationBar)
		}
		.onAppear {
			UIApplication.shared.isIdleTimerDisabled = true
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
		}
		.onDisappear(perform: {
			UIApplication.shared.isIdleTimerDisabled = false
			GeoJSONOverlayManager.shared.clearCache()
		})
		.onChange(of: router.selectedTab) { _, newTab in
			if newTab == .map {
				refreshMapWindowOpenState()
				UIApplication.shared.isIdleTimerDisabled = true
			} else {
				UIApplication.shared.isIdleTimerDisabled = false
				GeoJSONOverlayManager.shared.clearCache()
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
