//
//  NodeMap.swift
//  MeshtasticApple
//
//  Created by Garth Vander Houwen on 8/7/21.
//

import SwiftUI
import MapKit
import CoreLocation
import CoreData

struct NodeMap: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager
	@EnvironmentObject var userSettings: UserSettings
	@AppStorage("meshMapType") var type: String = "hybrid"
	@AppStorage("meshMapCustomTileServer") var customTileServer: String = "" {
		didSet {
			if customTileServer == "" {
				self.customMapOverlay = nil
			} else {
				self.customMapOverlay = MapViewSwiftUI.CustomMapOverlay(
					mapName: customTileServer,
					tileType: "png",
					canReplaceMapContent: true
				)
			}
		}
	}
	@FetchRequest(sortDescriptors: [NSSortDescriptor(key: "time", ascending: false)], animation: .default)
	private var positions: FetchedResults<PositionEntity>
	
	@State private var mapType: MKMapType = .standard
	@State var waypointCoordinate: CLLocationCoordinate2D?
	@State private var presentingWaypointForm = false
	@State private var customMapOverlay: MapViewSwiftUI.CustomMapOverlay? = MapViewSwiftUI.CustomMapOverlay(
			mapName: "offlinemap",
			tileType: "png",
			canReplaceMapContent: true
		)
	@State private var overlays: [MapViewSwiftUI.Overlay] = []
	
	//@State private var showLabels: Bool = false
	//@State private var zoomEnabled: Bool = true
	//@State private var showZoomScale: Bool = true
	//@State private var useMinZoomBoundary: Bool = false
	//@State private var minZoom: Double = 0
	//@State private var useMaxZoomBoundary: Bool = false
	//@State private var maxZoom: Double = 3000000
	//@State private var scrollEnabled: Bool = true
	//@State private var useScrollBoundaries: Bool = false
	//@State private var scrollBoundaries: MKCoordinateRegion = MKCoordinateRegion()
	//@State private var rotationEnabled: Bool = true
	//@State private var showCompassWhenRotated: Bool = true
	//@State private var showUserLocation: Bool = true
	//@State private var userTrackingMode: MKUserTrackingMode = MKUserTrackingMode.none
	//@State private var userLocation: CLLocationCoordinate2D? = LocationHelper.currentLocation
	//@State private var showAnnotations: Bool = true
	//@State private var annotations: [MKPointAnnotation] = []
	//@State private var showOverlays: Bool = true
	//@State private var showMapCenter: Bool = false
	
    var body: some View {

        NavigationStack {
			ZStack {
				MapViewSwiftUI(onMarkerTap: { coord in
					presentingWaypointForm = true
					waypointCoordinate = coord
				}, positions: Array(positions), region: MKCoordinateRegion(center: LocationHelper.currentLocation, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)), mapViewType: mapType,
					customMapOverlay: self.customMapOverlay,
					overlays: self.overlays
				)
				VStack {
					Spacer()
					
					Picker("", selection: $mapType) {
						Text("Standard").tag(MKMapType.standard)
						Text("Muted").tag(MKMapType.mutedStandard)
						Text("Hybrid").tag(MKMapType.hybrid)
						Text("Hybrid Flyover").tag(MKMapType.hybridFlyover)
						Text("Satellite").tag(MKMapType.satellite)
						Text("Sat Flyover").tag(MKMapType.satelliteFlyover)
					}
					.pickerStyle(SegmentedPickerStyle())
					.padding(.bottom, 30)
				}
			}
			.ignoresSafeArea(.all, edges: [.top, .leading, .trailing])
			.frame(maxHeight: .infinity)
			.sheet(isPresented: $presentingWaypointForm ) {//,  onDismiss: didDismissSheet) {
				WaypointFormView(coordinate: waypointCoordinate ?? LocationHelper.DefaultLocation)
					.presentationDetents([.medium, .large])
					.presentationDragIndicator(.automatic)
			}
        }
		.navigationBarItems(leading:
			MeshtasticLogo(), trailing:
		ZStack {
			ConnectedDevice(
				bluetoothOn: bleManager.isSwitchedOn,
				deviceConnected: bleManager.connectedPeripheral != nil,
				name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName :
					"????")
		})
		.onAppear(perform: {
			self.bleManager.context = context
			self.bleManager.userSettings = userSettings
		})
    }
}

struct NodeMap_Previews: PreviewProvider {
    static let bleManager = BLEManager()

    static var previews: some View {
        NodeMap()
    }
}
