import SwiftUI
import CoreLocation
import MapKit

struct NodeMap: View {
	@Environment(\.managedObjectContext)
	var context
	@EnvironmentObject
	var bleManager: BLEManager

	@ObservedObject
	private var node: NodeInfoEntity
	@AppStorage("mapLayer")
	private var selectedMapLayer: MapLayer = .standard
	@Namespace
	private var mapScope
	@State
	private var positions: [PositionEntity] = []
	@State
	private var position = MapCameraPosition.automatic
	@State
	private var isEditingSettings = false
	@State
	private var isMeshMap = false
	@State
	private var mapRegion = MKCoordinateRegion.init()

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

	private var screenTitle: String {
		if let name = node.user?.shortName {
			return name
		}
		else {
			return "Node Map"
		}
	}
	private var mapStyle: MapStyle {
		getMapStyle(for: selectedMapLayer)
	}
	private var hasPositions: Bool {
		if let positions = node.positions, positions.count > 1 {
			return true
		}
		else {
			return false
		}
	}

	var body: some View {
		if node.hasPositions {
			VStack(spacing: 0) {
				map

				if hasPositions {
					AltitudeHistoryView(node: node)
						.frame(height: 200)
				}
			}
			.navigationBarTitle(
				screenTitle,
				displayMode: .inline
			)
			.navigationBarItems(
				trailing: ConnectedDevice()
			)
		}
		else {
			ContentUnavailableView("No Positions", systemImage: "mappin.slash")
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
			.mapControls {
				MapScaleView(scope: mapScope)
					.mapControlVisibility(.visible)

				MapUserLocationButton(scope: mapScope)
					.mapControlVisibility(.visible)

				MapPitchToggle(scope: mapScope)
					.mapControlVisibility(.visible)

				MapCompass(scope: mapScope)
					.mapControlVisibility(.visible)
			}
			.controlSize(.regular)
			.onDisappear {
				UIApplication.shared.isIdleTimerDisabled = false
			}
			.onChange(of: node, initial: true) {
				UIApplication.shared.isIdleTimerDisabled = true

				mostRecent = node.positions?.lastObject as? PositionEntity

				if hasPositions {
					position = .automatic
				} else {
					position = .camera(
						MapCamera(
							centerCoordinate: mostRecent!.coordinate,
							distance: 8000,
							heading: 0,
							pitch: 40
						)
					)
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
			.sheet(isPresented: $isEditingSettings) {
				MapSettingsForm(
					mapLayer: $selectedMapLayer,
					meshMap: $isMeshMap
				)
			}
		}
	}

	init(node: NodeInfoEntity) {
		self.node = node
	}

	private func getMapStyle(for layer: MapLayer) -> MapStyle {
		switch layer {
		case .standard:
			return MapStyle.standard(
				elevation: .flat
			)
		case .hybrid, .offline:
			return MapStyle.hybrid(
				elevation: .flat
			)
		case .satellite:
			return MapStyle.imagery(
				elevation: .flat
			)
		}
	}
}
