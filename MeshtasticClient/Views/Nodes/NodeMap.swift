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

	// @AppStorage("meshMapType") var meshMapType: String = "hybrid"

	@State private var showLabels: Bool = false

	@State private var annotationItems: [MapLocation] = []
	@FetchRequest( sortDescriptors: [NSSortDescriptor(keyPath: \NodeInfoEntity.lastHeard, ascending: false)], animation: .default)

	private var locationNodes: FetchedResults<NodeInfoEntity>

	var annotations: [MapLocation] = [MapLocation]()

    var body: some View {

		let location = LocationHelper.currentLocation
        let currentCoordinatePosition = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let regionBinding = Binding<MKCoordinateRegion>(
            get: {
                MKCoordinateRegion(center: currentCoordinatePosition, span: MKCoordinateSpan(latitudeDelta: 0.0359, longitudeDelta: 0.0359))
            },
            set: { _ in }
        )

        NavigationView {

            ZStack {

				MapView(nodes: self.locationNodes)// .environmentObject(userSettings)
                // }
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
