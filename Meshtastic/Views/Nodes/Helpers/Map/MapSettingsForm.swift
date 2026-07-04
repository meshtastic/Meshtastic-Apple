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
	@AppStorage("mapOverlaysEnabled") private var mapOverlaysEnabled = false
	@AppStorage("enableOfflineTiles") private var enableOfflineTiles = false
	@AppStorage("enableMapClustering") private var enableMapClustering = true
	@AppStorage("enableMapPreciseLocationsOnly") private var preciseLocationsOnly = false
	@ObservedObject private var mapDataManager = MapDataManager.shared
	@ObservedObject private var offlineMapManager = OfflineMapManager.shared
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
							// `.offline` is an overlay toggle now, not a base layer — keep it out of the base picker.
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
					if LocationsHandler.currentPreciseLocation != nil {
							HStack {
								Label("Distance", systemImage: "lines.measurement.horizontal")
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
						}
						Toggle(isOn: $enableMapWaypoints) {
							Label {
								Text("Waypoints")
							} icon: {
								Image(systemName: "signpost.right.and.left")
									.symbolRenderingMode(.multicolor)
							}
						}
						.tint(.accentColor)
						Toggle(isOn: $preciseLocationsOnly) {
							Label {
								VStack(alignment: .leading) {
									Text("Precise Locations Only")
									Text("Hides nodes that broadcast an approximate location (the ones drawn with a translucent precision circle).")
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} icon: {
								Image(systemName: "scope")
							}
						}
						.tint(.accentColor)
					}
					if !meshMap {
						Toggle(isOn: $nodeHistory) {
							Label("Node History", systemImage: "building.columns.fill")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						Toggle(isOn: $enableMapRouteLines) {
							Label("Route Lines", systemImage: "road.lanes")
						}
						.tint(.accentColor)

					}
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

				if meshMap {
					Section(header: Text("Offline Maps")) {
						NavigationLink {
							OfflineMapsList()
						} label: {
							Label {
								VStack(alignment: .leading) {
									Text("Offline Maps")
									if offlineMapManager.regions.isEmpty {
										Text("Download map areas to use without a connection.")
											.font(.caption)
											.foregroundColor(.secondary)
									} else {
										Text("\(offlineMapManager.regions.count) downloaded · \(offlineMapManager.formattedTotalSize)")
											.font(.caption)
											.foregroundColor(.secondary)
									}
								}
							} icon: {
								Image(systemName: "arrow.down.circle")
							}
						}
					}
				}

				Section(header: Text("Map Overlays")) {
					if meshMap {
						Toggle(isOn: $enableOfflineTiles) {
							Label {
								VStack(alignment: .leading) {
									Text("Offline Tiles")
									Text("Shows a saved offline map over the covered area, so it still works without an internet connection.")
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} icon: {
								Image(systemName: "square.dashed")
							}
						}
						.tint(.accentColor)
						Toggle(isOn: $enableMapClustering) {
							Label {
								VStack(alignment: .leading) {
									Text("Cluster Nodes")
									Text("Groups nearby nodes into one numbered pin; tap it to zoom in. Turn off to always show every node.")
										.font(.caption)
										.foregroundColor(.secondary)
								}
							} icon: {
								Image(systemName: "circle.grid.3x3.fill")
							}
						}
						.tint(.accentColor)
					}
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
			.navigationTitle("Map Options")
			.navigationBarTitleDisplayMode(.inline)
		}
		#if targetEnvironment(macCatalyst)
		.overlay(alignment: .topLeading) {
			Button {
				dismiss()
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
		.presentationDetents([.large], selection: $currentDetent)
		.presentationContentInteraction(.scrolls)
		#if !targetEnvironment(macCatalyst)
		.presentationDragIndicator(.visible)
		#endif
		.presentationBackgroundInteraction(.enabled(upThrough: .medium))
		.onAppear {
			// Initialize map data manager
			mapDataManager.initialize()
			offlineMapManager.loadIfNeeded()
			// Migrate the legacy `.offline` base layer to the new independent offline-tiles overlay here
			// (a shared entry point), so any presenter — incl. the per-node map — never shows the base
			// picker with an unselectable `.offline` value when its segment is hidden on the new map.
			if mapLayer == .offline {
				mapLayer = .standard
				enableOfflineTiles = true
			}
		}

	}
}

#Preview {
	MapSettingsForm(
		traffic: .constant(false),
		pointsOfInterest: .constant(true),
		mapLayer: .constant(.standard),
		meshMap: .constant(true),
		enabledOverlayConfigs: .constant(Set<UUID>())
	)
}
