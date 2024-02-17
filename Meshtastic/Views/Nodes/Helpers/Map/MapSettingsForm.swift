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
	@Binding var nodeHistory: Bool
	@Binding var routeLines: Bool
	@Binding var convexHull: Bool
	@Binding var traffic: Bool
	@Binding var pointsOfInterest: Bool
	@Binding var mapLayer: MapLayer
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
					if !meshMap {
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
		.presentationDetents([.fraction(0.45), .fraction(0.65)])
		.presentationDragIndicator(.visible)
		
	}
}
