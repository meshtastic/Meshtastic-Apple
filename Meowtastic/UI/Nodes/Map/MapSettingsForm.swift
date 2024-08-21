import MapKit
import SwiftUI

struct MapSettingsForm: View {
	@Binding
	var mapLayer: MapLayer
	@Binding
	var meshMap: Bool

	@AppStorage("meshMapShowNodeHistory")
	private var nodeHistory = false
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
					.onChange(of: mapLayer, initial: false) {
						UserDefaults.mapLayer = mapLayer
					}

					if !meshMap {
						Toggle(isOn: $nodeHistory) {
							Label("Node History", systemImage: "building.columns.fill")
						}
						.toggleStyle(SwitchToggleStyle(tint: .accentColor))
						.onTapGesture {
							nodeHistory.toggle()

							UserDefaults.enableMapNodeHistoryPins = self.nodeHistory
						}
					}
				}
			}
		}
		.presentationDetents([ .medium ])
		.presentationDragIndicator(.visible)
	}
}
