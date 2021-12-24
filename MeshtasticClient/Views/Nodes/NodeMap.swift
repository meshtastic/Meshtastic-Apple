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
		
		/*ForEach ( locationNodes ) { node in
					let mostRecent = node.positions?.lastObject as! PositionEntity
					if mostRecent.coordinate != nil {
		
						annotations.append(MapLocation(name: node.user?.shortName! ?? "???", coordinate: mostRecent.coordinate!))
		
					}
				}*/
		
        NavigationView {


            ZStack {
				
				
				
                /*Map(coordinateRegion: regionBinding,
                    interactionModes: [.all],
                    showsUserLocation: true,
					userTrackingMode: .constant(.follow),
					annotationItems: self.locationNodes.filter({ nodeinfo in
					return nodeinfo.positions != nil && nodeinfo.positions!.count > 0// && (nodeinfo.positions?.lastObject as? AnyObject)?.coordinate != nil

					})
				) { locationNode in
					
						return MapAnnotation(
							coordinate: (locationNode.positions!.lastObject as! PositionEntity).coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
						   content: {
							   CircleText(text: locationNode.user!.shortName ?? "???", color: .accentColor)
						   }
						)


				}*/
				
				MapView(nodes: self.locationNodes)
				
                //}
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
