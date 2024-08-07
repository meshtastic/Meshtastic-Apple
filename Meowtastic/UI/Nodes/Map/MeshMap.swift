import CoreData
import CoreLocation
import Foundation
import MapKit
import OSLog
import SwiftUI

struct MeshMap: View {
	@Environment(\.managedObjectContext)
	var context
	@StateObject
	var appState = AppState.shared
	@State
	var showUserLocation: Bool = true
	@Namespace
	var mapScope
	@State
	var mapStyle = MapStyle.standard(
		elevation: .realistic,
		emphasis: MapStyle.StandardEmphasis.muted
	)
	@State
	var position = MapCameraPosition.automatic
	@State
	var selectedPosition: PositionEntity?
	@State
	var isMeshMap = true

	@EnvironmentObject
	private var bleManager: BLEManager

	var body: some View {
		NavigationStack {
			ZStack {
				MapReader { _ in
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
							selectedPosition: $selectedPosition
						)
					}
					.mapScope(mapScope)
					.mapStyle(mapStyle)
					.mapControls {
						MapScaleView(scope: mapScope)
							.mapControlVisibility(.automatic)

						MapUserLocationButton(scope: mapScope)
							.mapControlVisibility(.visible)

						MapPitchToggle(scope: mapScope)
							.mapControlVisibility(.automatic)

						MapCompass(scope: mapScope)
							.mapControlVisibility(.automatic)
					}
					.controlSize(.regular)
				}
			}
			.popover(item: $selectedPosition) { position in
				if let node = position.nodePosition {
					NodeDetail(isInSheet: true, node: node)
						.presentationDetents([.medium])
				}
			}
			.navigationTitle("Mesh")
			.navigationBarTitleDisplayMode(.large)
			.navigationBarItems(
				trailing: ConnectedDevice()
			)
		}
	}
}
