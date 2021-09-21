//
//  DeviceMap.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//  Copyright © 2021 Apple. All rights reserved.
//

import SwiftUI
import MapKit
import CoreLocation

struct NodeMap: View {
    
    @EnvironmentObject var meshData: MeshData

    var locationNodes: [NodeInfoModel] {
        meshData.nodes.filter { node in
            (node.position.coordinate != nil)
        }
    }
    struct MapLocation: Identifiable {
        let id = UUID()
        let name: String
        let coordinate: CLLocationCoordinate2D
    }
    
    var body: some View {
        let location = LocationHelper.currentLocation
        let currentCoordinatePosition = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let regionBinding = Binding<MKCoordinateRegion>(
            get: {
                MKCoordinateRegion(center: currentCoordinatePosition, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
            },
            set: { _ in }
        )
                
        NavigationView {
            
            ZStack {
                Map(coordinateRegion: regionBinding,
                    interactionModes: [.all],
                    showsUserLocation: true,
                    userTrackingMode: .constant(.follow), annotationItems: locationNodes) { location in
                    
                    MapAnnotation(
                        coordinate: location.position.coordinate!,
                       content: {
                        CircleText(text: location.user.shortName, color: Color.blue)
                       }
                    )
                }.frame(maxHeight:.infinity)
            }
            .navigationTitle("Mesh Map")
            .navigationBarTitleDisplayMode(.inline)
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct NodeMap_Previews: PreviewProvider {
    static let modelData = ModelData()

    static var previews: some View {
        NodeMap()
            .environmentObject(modelData)
    }
}
