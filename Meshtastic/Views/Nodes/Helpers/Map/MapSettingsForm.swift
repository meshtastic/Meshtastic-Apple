//
//  MapSettingsForm.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 10/3/23.
//

import SwiftUI
import MapKit

struct MapSettingsForm: View {
	@Environment(\.dismiss) private var dismiss
	@State private var currentDetent = PresentationDetent.medium
	@AppStorage("meshMapShowNodeHistory") private var nodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var enableMapRouteLines = false
	@AppStorage("enableMapConvexHull") private var convexHull = false
	@AppStorage("enableMapWaypoints") private var enableMapWaypoints = true
	@AppStorage("enableMapShowFavorites") private var enableMapShowFavorites = false
	@Binding var traffic: Bool
	@Binding var pointsOfInterest: Bool
	@Binding var mapLayer: MapLayer
	@AppStorage("meshMapDistance") private var meshMapDistance: Double = 800000
	@Binding var meshMap: Bool

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

				Section(header: Text("Burning Man Overlays")) {
					Toggle(isOn: Binding(
						get: { UserDefaults.standard.bool(forKey: "burningManShowStreets") },
						set: { UserDefaults.standard.set($0, forKey: "burningManShowStreets") }
					)) {
						Label {
							Text("Street Outlines")
						} icon: {
							Image(systemName: "road.lanes")
								.foregroundColor(.yellow)
						}
					}
					.tint(.accentColor)

					Toggle(isOn: Binding(
						get: { UserDefaults.standard.bool(forKey: "burningManShowToilets") },
						set: { UserDefaults.standard.set($0, forKey: "burningManShowToilets") }
					)) {
						Label {
							Text("Toilets")
						} icon: {
							Image(systemName: "toilet")
								.foregroundColor(.brown)
						}
					}
					.tint(.accentColor)

					Toggle(isOn: Binding(
						get: { UserDefaults.standard.bool(forKey: "burningManShowTrashFence") },
						set: { UserDefaults.standard.set($0, forKey: "burningManShowTrashFence") }
					)) {
						Label {
							Text("Trash Fence")
						} icon: {
							Image(systemName: "fence")
								.foregroundColor(.red)
						}
					}
					.tint(.accentColor)
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

	}
}
