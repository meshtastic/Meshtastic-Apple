import SwiftUI
import CoreLocation
import MapKit

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
		} else {
			EmptyView()
		}
	}

	@ViewBuilder
	private var map: some View {
		var mostRecent = node.positions?.lastObject as? PositionEntity

		MapReader { _ in
			Map(
				position: $position,
				bounds: MapCameraBounds(minimumDistance: 100, maximumDistance: .infinity),
				scope: mapScope
			) {
				NodeMapContent(node: node)
			}
			.mapScope(mapScope)
			.mapStyle(mapStyle)
			.onAppear {
				UIApplication.shared.isIdleTimerDisabled = true
				mostRecent = node.positions?.lastObject as? PositionEntity

				position = .camera(
					MapCamera(
						centerCoordinate: mostRecent!.coordinate,
						distance: 500,
						heading: 0,
						pitch: 80
					)
				)
			}
			.onDisappear {
				UIApplication.shared.isIdleTimerDisabled = false
			}
		}
	}

	init(node: NodeInfoEntity) {
		self.node = node
	}
}
