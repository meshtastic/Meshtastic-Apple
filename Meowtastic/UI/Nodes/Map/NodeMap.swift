import CoreLocation
import FirebaseAnalytics
import MapKit
import SwiftUI

struct NodeMap: View {
	@Environment(\.managedObjectContext)
	var context

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
	private var mapRegion = MKCoordinateRegion()

	private let node: NodeInfoEntity
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
	private var positionCount: Int {
		node.positions?.count ?? 0
	}

	var body: some View {
		if node.hasPositions {
			map
				.navigationBarTitle(
					screenTitle,
					displayMode: .inline
				)
				.navigationBarItems(
					trailing: ConnectionInfo()
				)
				.onAppear {
					Analytics.logEvent(
						AnalyticEvents.nodeMap.id,
						parameters: AnalyticEvents.getParams(for: node)
					)
				}
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
				UserAnnotation()
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
			.safeAreaInset(edge: .bottom, alignment: .trailing) {
				VStack(alignment: .trailing, spacing: 4) {
					Button(action: {
						withAnimation {
							isEditingSettings.toggle()
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
				.padding(8)
			}
			.sheet(isPresented: $isEditingSettings) {
				MapSettingsForm(
					mapLayer: $selectedMapLayer,
					meshMap: $isMeshMap
				)
			}
			.onChange(of: node, initial: true) {
				mostRecent = node.positions?.lastObject as? PositionEntity

				if let mostRecent, mostRecent.coordinate.isValid {
					position = .camera(
						MapCamera(
							centerCoordinate: mostRecent.coordinate,
							distance: 8000,
							heading: 0,
							pitch: 40
						)
					)
				}
				else {
					position = .automatic
				}
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
