//
//  MapSettingsForm.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 10/3/23.
//

import SwiftUI
import MapKit
import OSLog

struct MapSettingsForm: View {
	@Environment(\.dismiss) private var dismiss
	@State private var currentDetent = PresentationDetent.medium
	@AppStorage("meshMapShowNodeHistory") private var nodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var enableMapRouteLines = false
	@AppStorage("enableMapConvexHull") private var convexHull = false
	@AppStorage("enableMapWaypoints") private var enableMapWaypoints = true
	@AppStorage("enableMapShowFavorites") private var enableMapShowFavorites = false
	@AppStorage("mapOverlaysEnabled") private var mapOverlaysEnabled = false
	@ObservedObject private var mapDataManager = MapDataManager.shared
	@Binding var traffic: Bool
	@Binding var pointsOfInterest: Bool
	@Binding var mapLayer: MapLayer
	@AppStorage("meshMapDistance") private var meshMapDistance: Double = 800000
	@Binding var meshMap: Bool
	@Binding var enabledOverlayConfigs: Set<UUID>

	var body: some View {

		NavigationStack {
			Form {
				Section(header: Text("Map Options")) {
					Picker(selection: $mapLayer, label: Text("")) {
						ForEach(MapLayer.allCases, id: \.self) { layer in
							if layer != MapLayer.offline {
								Text(layer.localized.capitalized)
							}
						}
					}
					.pickerStyle(SegmentedPickerStyle())
					.padding(.top, 5)
					.padding(.bottom, 5)
					.onChange(of: mapLayer) { _, newMapLayer in
						UserDefaults.mapLayer = newMapLayer
					}
					if meshMap {
						HStack {
							Label("Show nodes", systemImage: "lines.measurement.horizontal")
							Picker("", selection: $meshMapDistance) {
								ForEach(MeshMapDistances.allCases) { di in
									Text(di.description)
										.tag(di.id)
								}
							}
							.pickerStyle(DefaultPickerStyle())
						}
						.onChange(of: meshMapDistance) { _, newMeshMapDistance in
							UserDefaults.meshMapDistance = newMeshMapDistance
						}
						Toggle(isOn: $enableMapWaypoints) {
							Label {
								Text("Show Waypoints")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.multicolor)
							}
						}
						.tint(.accentColor)
					}
					Toggle(isOn: $enableMapShowFavorites) {
						Label {
							Text("Favorites")
						} icon: {
							Image(systemName: "star.fill")
								.symbolRenderingMode(.multicolor)
						}
					}
					.tint(.accentColor)
					Toggle(isOn: $nodeHistory) {
						Label("Node History", systemImage: "building.columns.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.nodeHistory.toggle()
						UserDefaults.enableMapNodeHistoryPins = self.nodeHistory
					}
					Toggle(isOn: $enableMapRouteLines) {
						Label("Route Lines", systemImage: "road.lanes")
					}
					.tint(.accentColor)
					Toggle(isOn: $convexHull) {
						Label("Convex Hull", systemImage: "button.angledbottom.horizontal.right")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.convexHull.toggle()
						UserDefaults.enableMapConvexHull = self.convexHull
					}
					Toggle(isOn: $traffic) {
						Label("Traffic", systemImage: "car")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.traffic.toggle()
						UserDefaults.enableMapTraffic = self.traffic
					}
					Toggle(isOn: $pointsOfInterest) {
						Label {
							Text("Points of Interest")
						} icon: {
							Image(systemName: "mappin.and.ellipse")
								.symbolRenderingMode(.multicolor)
						}
					}
					.tint(.accentColor)
					.onTapGesture {
						self.pointsOfInterest.toggle()
						UserDefaults.enableMapPointsOfInterest = self.pointsOfInterest
					}
				}

				Section(header: Text("Map Overlays")) {
					let hasUserData = GeoJSONOverlayManager.shared.hasUserData()
					// Master toggle for map overlays
					Toggle(isOn: $mapOverlaysEnabled) {
						Label {
							VStack(alignment: .leading) {
								Text("Map Overlays")
								Text(GeoJSONOverlayManager.shared.getActiveDataSource())
									.font(.caption)
									.foregroundColor(.secondary)
							}
						} icon: {
							Image(systemName: "map")
								.symbolRenderingMode(.multicolor)
						}
					}
					.tint(.accentColor)
					.disabled(!hasUserData && !mapOverlaysEnabled)

					// Show individual file toggles when overlays are enabled
					if mapOverlaysEnabled && hasUserData {
						if !mapDataManager.getUploadedFiles().isEmpty {
							// Individual file toggles
							ForEach(mapDataManager.getUploadedFiles()) { file in
								Toggle(isOn: Binding(
									get: {
										return enabledOverlayConfigs.contains(file.id)
									},
									set: { newValue in
										if newValue {
											enabledOverlayConfigs.insert(file.id)
										} else {
											enabledOverlayConfigs.remove(file.id)
										}
									}
								)) {
									Label {
										VStack(alignment: .leading) {
											Text(file.originalName)
												.font(.subheadline)
											HStack {
												Text("\(file.overlayCount) features")
													.font(.caption2)
													.foregroundColor(.secondary)
												Spacer()
												Text(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))
													.font(.caption2)
													.foregroundColor(.secondary)
											}
										}
									} icon: {
										let isEnabled = enabledOverlayConfigs.contains(file.id)
										Image(systemName: isEnabled ? "doc.fill" : "doc")
											.foregroundColor(isEnabled ? .accentColor : .secondary)
									}
								}
								.tint(.accentColor)
							}
							NavigationLink(destination: MapDataFiles()) {
								Label {
									Text("Manage map data")
								} icon: {
									Image(systemName: "folder")
										.symbolRenderingMode(.multicolor)
								}
							}
						} else {
							ContentUnavailableView("No map data files uploaded", systemImage: "exclamationmark.triangle")
						}
					} else if !hasUserData {
						// Upload prompt when no data available
						NavigationLink(destination: MapDataFiles()) {
							Label {
								Text("Upload map data to enable overlays")
							} icon: {
								Image(systemName: "arrow.up.doc")
									.symbolRenderingMode(.multicolor)
							}
						}
					}
				}
			}

#if targetEnvironment(macCatalyst)
			Spacer()
			Button {
				dismiss()
			} label: {
				Label("Close", systemImage: "xmark")
			}
			.buttonStyle(.bordered)
			.buttonBorderShape(.capsule)
			.controlSize(.large)
			.padding(.bottom)
#endif
		}
		.presentationDetents([.medium, .large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		.presentationDragIndicator(.visible)
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
		.onAppear {
			// Initialize map data manager
			mapDataManager.initialize()
		}

	}
}
