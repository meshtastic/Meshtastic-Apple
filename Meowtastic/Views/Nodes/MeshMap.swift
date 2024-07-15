import SwiftUI
import CoreData
import CoreLocation
import Foundation
import OSLog
import MapKit

struct MeshMap: View {
	@Environment(\.managedObjectContext)
	var context
	@StateObject
	var appState = AppState.shared
	@State
	var showUserLocation: Bool = true

	@Namespace var mapScope
	@State
	var mapStyle = MapStyle.standard(
		elevation: .flat,
		emphasis: MapStyle.StandardEmphasis.muted
	)
	@State
	var position = MapCameraPosition.automatic
	@State
	var isEditingSettings = false
	@State
	var selectedPosition: PositionEntity?
	@State
	var isMeshMap = true

	@EnvironmentObject
	private var bleManager: BLEManager
	@AppStorage("mapLayer")
	private var selectedMapLayer: MapLayer = .standard

	var body: some View {
		NavigationStack {
			ZStack {
				MapReader { reader in
					Map(
						position: $position,
						bounds: MapCameraBounds(
							minimumDistance: 1,
							maximumDistance: .infinity
						),
						scope: mapScope
					) {
						MeshMapContent(
							showUserLocation: $showUserLocation,
							selectedMapLayer: $selectedMapLayer,
							selectedPosition: $selectedPosition
						)
					}
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
				}
			}
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
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
				}
				.controlSize(.regular)
				.padding(5)
			}
			.onChange(of: selectedMapLayer, initial: true) {
				UserDefaults.mapLayer = selectedMapLayer

				switch selectedMapLayer {
				case .standard:
					mapStyle = MapStyle.standard(elevation: .realistic)
				case .hybrid:
					mapStyle = MapStyle.hybrid(elevation: .realistic)
				case .satellite:
					mapStyle = MapStyle.imagery(elevation: .realistic)
				case .offline:
					return
				}
			}
			.sheet(item: $selectedPosition) { position in
				if let node = selectedPosition?.nodePosition {
					NodeDetail(isInSheet: true, node: node)
						.presentationDetents([.medium])
				}
			}
			.sheet(isPresented: $isEditingSettings) {
				MapSettingsForm(mapLayer: $selectedMapLayer, meshMap: $isMeshMap)
			}
			.navigationTitle("Mesh")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(
				leading: MeshtasticLogo(),
				trailing: ConnectedDevice(ble: bleManager)
			)
		}
		.onAppear {
			UIApplication.shared.isIdleTimerDisabled = true
		}
		.onDisappear {
			UIApplication.shared.isIdleTimerDisabled = false
		}
	}
}
