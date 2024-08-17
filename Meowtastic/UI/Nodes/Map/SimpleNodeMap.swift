import CoreLocation
import MapKit
import SwiftUI

struct SimpleNodeMap: View {
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager

	private let mapStyle = MapStyle.standard(elevation: .flat)

	@ObservedObject
	private var node: NodeInfoEntity
	@Namespace
	private var mapScope
	@State
	private var positions: [PositionEntity] = []
	@State
	private var position = MapCameraPosition.automatic

	@FetchRequest(
		sortDescriptors: [
			NSSortDescriptor(key: "name", ascending: false)
		],
		predicate: NSPredicate(
			format: "expire == nil || expire >= %@", Date() as NSDate
		),
		animation: .none
	)
	private var waypoints: FetchedResults<WaypointEntity>

	var body: some View {
		if node.hasPositions {
			map
		}
		else {
			EmptyView()
		}
	}

	@ViewBuilder
	private var map: some View {
		MapReader { _ in
			Map(
				position: $position,
				bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: .infinity),
				scope: mapScope
			) {
				UserAnnotation()
				NodeMapContent(node: node)
			}
			.mapScope(mapScope)
			.mapStyle(mapStyle)
			.mapControls {
				MapScaleView(scope: mapScope)
					.mapControlVisibility(.visible)

				MapUserLocationButton(scope: mapScope)
					.mapControlVisibility(.hidden)

				MapPitchToggle(scope: mapScope)
					.mapControlVisibility(.hidden)

				MapCompass(scope: mapScope)
					.mapControlVisibility(.hidden)
			}
			.onAppear {
				if
					let lastCoordinate = (node.positions?.lastObject as? PositionEntity)?.coordinate,
					lastCoordinate.isValid
				{
					position = .camera(
						MapCamera(
							centerCoordinate: lastCoordinate,
							distance: 500,
							heading: 0,
							pitch: 80
						)
					)
				}
			}
		}
	}

	init(node: NodeInfoEntity) {
		self.node = node
	}
}
