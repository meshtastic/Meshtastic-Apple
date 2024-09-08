//
//  MapSettingsForm.swift
//  Meshtastic
//
//  Created by Garth Vander Houwen on 10/3/23.
//

import SwiftUI
#if canImport(MapKit)
import MapKit
#endif

@available(iOS 17.0, macOS 14.0, *)
struct MapSettingsForm: View {
	@Environment(\.dismiss) private var dismiss
	@State private var currentDetent = PresentationDetent.medium
	@AppStorage("meshMapShowNodeHistory") private var nodeHistory = false
	@AppStorage("meshMapShowRouteLines") private var routeLines = false
	@AppStorage("enableMapConvexHull") private var convexHull = false
	@AppStorage("enableMapWaypoints") private var waypoints = true
	@AppStorage("meshMapShowLocationPrecision") private var showLocationPrecision = true
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
								Text(layer.localized)
							}
						}
					}
					.pickerStyle(SegmentedPickerStyle())
					.padding(.top, 5)
					.padding(.bottom, 5)
					.onChange(of: mapLayer) { newMapLayer in
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
						.onChange(of: meshMapDistance) { newMeshMapDistance in
							UserDefaults.meshMapDistance = newMeshMapDistance
						}
						Toggle(isOn: $showLocationPrecision) {
							Label("Show Location Precision", systemImage: "circle.dotted.and.circle")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.onTapGesture {
							UserDefaults.meshMapShowLocationPrecision = !showLocationPrecision
						}
						Toggle(isOn: $waypoints) {
							Label("Show Waypoints ", systemImage: "signpost.right.and.left")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.onTapGesture {
							UserDefaults.enableMapWaypoints = !waypoints
						}
					}

					Toggle(isOn: $nodeHistory) {
						Label("Node History", systemImage: "building.columns.fill")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.nodeHistory.toggle()
						UserDefaults.enableMapNodeHistoryPins = self.nodeHistory
					}
					Toggle(isOn: $routeLines) {
						Label("Route Lines", systemImage: "road.lanes")
					}

					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.routeLines.toggle()
						UserDefaults.enableMapRouteLines = self.routeLines
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
						Label("Points of Interest", systemImage: "mappin.and.ellipse")
					}
					.toggleStyle(SwitchToggleStyle(tint: .accentColor))
					.onTapGesture {
						self.pointsOfInterest.toggle()
						UserDefaults.enableMapPointsOfInterest = self.pointsOfInterest
					}
				}
			}

#if targetEnvironment(macCatalyst)
Spacer()
				Button {
					dismiss()
				} label: {
					Label("close", systemImage: "xmark")
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
