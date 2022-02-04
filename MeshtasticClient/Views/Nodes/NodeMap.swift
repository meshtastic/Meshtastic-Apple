//
//  NodeMap.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//  Copyright © 2021 Apple. All rights reserved.
//

import SwiftUI
import MapKit
import CoreLocation
import CoreData

struct NodeMap: View {

	@Environment(\.managedObjectContext) var context
	@EnvironmentObject var bleManager: BLEManager

	@AppStorage("meshMapType") var type: String = "hybrid"
	@AppStorage("meshMapCustomTileServer") var customTileServer: String = "" {
		didSet {
			if customTileServer == "" {
				self.customMapOverlay = nil
			} else {
				self.customMapOverlay = MapView.CustomMapOverlay(
					mapName: customTileServer,
					tileType: "png",
					canReplaceMapContent: true
				)
			}
		}
	}
	
	@State private var showLabels: Bool = false

	//@State private var annotationItems: [MapLocation] = []
	//@FetchRequest( sortDescriptors: [NSSortDescriptor(keyPath: \NodeInfoEntity.lastHeard, ascending: false)], animation: .default)
	//private var locationNodes: FetchedResults<NodeInfoEntity>

	/*@State private var mapRegion: MKCoordinateRegion = MKCoordinateRegion(
		center: CLLocationCoordinate2D(
			latitude: -38.758247,
			longitude: 175.360208
		),
		span: MKCoordinateSpan(
			latitudeDelta: 0.01,
			longitudeDelta: 0.01
		)
	)*/
	
	@State private var customMapOverlay: MapView.CustomMapOverlay? = MapView.CustomMapOverlay(
			mapName: "offlinemap",
			tileType: "png",
			canReplaceMapContent: true
		)

	//@State private var mapType: MKMapType = MKMapType.standard

	@State private var zoomEnabled: Bool = true
	@State private var showZoomScale: Bool = true
	@State private var useMinZoomBoundary: Bool = false
	@State private var minZoom: Double = 0
	@State private var useMaxZoomBoundary: Bool = false
	@State private var maxZoom: Double = 3000000

	@State private var scrollEnabled: Bool = true
	@State private var useScrollBoundaries: Bool = false
	@State private var scrollBoundaries: MKCoordinateRegion = MKCoordinateRegion()

	@State private var rotationEnabled: Bool = true
	@State private var showCompassWhenRotated: Bool = true

	@State private var showUserLocation: Bool = true
	@State private var userTrackingMode: MKUserTrackingMode = MKUserTrackingMode.none
	@State private var userLocation: CLLocationCoordinate2D? = LocationHelper.currentLocation

	@State private var showAnnotations: Bool = true
	@State private var annotations: [MKPointAnnotation] = []

	@State private var showOverlays: Bool = true
	@State private var overlays: [MapView.Overlay] = []

	@State private var showMapCenter: Bool = false
	
    var body: some View {

		//self.$userLocation = LocationHelper.currentLocation

        NavigationView {

            ZStack {

				//MapView(nodes: self.locationNodes)//.environmentObject(bleManager)
                // }
				MapView(
					//region: self.$mapRegion,
					customMapOverlay: self.customMapOverlay,
					mapType: self.type,
					zoomEnabled: self.zoomEnabled,
					showZoomScale: self.showZoomScale,
					zoomRange: (minHeight: self.useMinZoomBoundary ? self.minZoom : 0, maxHeight: self.useMaxZoomBoundary ? self.maxZoom : .infinity),
					scrollEnabled: self.scrollEnabled,
					scrollBoundaries: self.useScrollBoundaries ? self.scrollBoundaries : nil,
					rotationEnabled: self.rotationEnabled,
					showCompassWhenRotated: self.showCompassWhenRotated,
					showUserLocation: self.showUserLocation,
					userTrackingMode: self.userTrackingMode,
					userLocation: self.$userLocation,
					//annotations: self.annotations,
					//locationNodes: self.locationNodes.map({ nodeinfo in return nodeinfo }),
					overlays: self.overlays
					//context: self.context
				)

               .frame(maxHeight: .infinity)
               .ignoresSafeArea(.all, edges: [.leading, .trailing])
            }
            .navigationTitle("Mesh Map")
            .navigationBarTitleDisplayMode(.inline)
			
			.navigationBarItems(trailing:

			ZStack {

				ConnectedDevice(
					bluetoothOn: bleManager.isSwitchedOn,
					deviceConnected: bleManager.connectedPeripheral != nil,
					name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.shortName :
						"???")
			})
			.onAppear(perform: {

				self.bleManager.context = context

			})
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct NodeMap_Previews: PreviewProvider {
    static let bleManager = BLEManager()

    static var previews: some View {
        NodeMap()
    }
}
