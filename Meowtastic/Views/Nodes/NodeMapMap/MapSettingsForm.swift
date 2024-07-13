import SwiftUI
import MapKit

struct MapSettingsForm: View {
	@Binding
	var mapLayer: MapLayer
	@Binding
	var meshMap: Bool

	@AppStorage("meshMapShowNodeHistory")
	private var nodeHistory = false
	@AppStorage("meshMapShowRouteLines")
	private var routeLines = false
	@AppStorage("enableMapConvexHull")
	private var convexHull = false
	@AppStorage("meshMapDistance")
	private var meshMapDistance: Double = 800000
	@Environment(\.dismiss)
	private var dismiss

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
					.onChange(of: mapLayer, initial: false) {
						UserDefaults.mapLayer = mapLayer
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
						.onChange(of: meshMapDistance, initial: false) {
							UserDefaults.meshMapDistance = meshMapDistance
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
				}
			}
		}
		.presentationDetents([.fraction(meshMap ? 0.55 : 0.45), .fraction(0.65)])
		.presentationDragIndicator(.visible)
	}
}
