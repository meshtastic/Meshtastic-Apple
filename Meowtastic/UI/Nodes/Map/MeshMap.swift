import CoreData
import CoreLocation
import FirebaseAnalytics
import MapKit
import OSLog
import SwiftUI

struct MeshMap: View {
	@Environment(\.managedObjectContext)
	var context
	@StateObject
	var appState = AppState.shared
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

	@FetchRequest(
		fetchRequest: PositionEntity.allPositionsFetchRequest()
	)
	private var positions: FetchedResults<PositionEntity>

	@EnvironmentObject
	private var bleManager: BLEManager

	var body: some View {
		NavigationStack {
			ZStack {
				MapReader { _ in
					Map(
						position: $position,
						bounds: MapCameraBounds(
							minimumDistance: 250,
							maximumDistance: .infinity
						),
						scope: mapScope
					) {
						UserAnnotation()
						MeshMapContent(
							selectedPosition: $selectedPosition
						)
					}
					.mapScope(mapScope)
					.mapStyle(mapStyle)
					.mapControls {
						MapScaleView(scope: mapScope)
							.mapControlVisibility(.visible)

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
		.onAppear {
			Analytics.logEvent(
				AnalyticEvents.meshMap.id,
				parameters: [
					"nodes_count": positions
				]
			)
		}
	}
}
