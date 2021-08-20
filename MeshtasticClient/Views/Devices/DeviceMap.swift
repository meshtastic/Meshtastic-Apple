//
//  DeviceMap.swift
//  Landmarks
//
//  Created by Garth Vander Houwen on 8/7/21.
//  Copyright © 2021 Apple. All rights reserved.
//

import SwiftUI
import MapKit
import CoreLocation

struct DeviceMap: View {
    
    @EnvironmentObject var modelData: ModelData

    var devices: [Device] {
        modelData.devices
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
        let annotations = [
            MapLocation(name: devices[0].shortName, coordinate: CLLocationCoordinate2D(latitude: devices[0].position.latitude, longitude: devices[0].position.longitude)),
            MapLocation(name: devices[1].shortName, coordinate: CLLocationCoordinate2D(latitude: devices[1].position.latitude, longitude: devices[1].position.longitude)),
            MapLocation(name: devices[2].shortName, coordinate: CLLocationCoordinate2D(latitude: devices[2].position.latitude, longitude: devices[2].position.longitude)),
            MapLocation(name: devices[3].shortName, coordinate: CLLocationCoordinate2D(latitude: devices[3].position.latitude, longitude: devices[3].position.longitude))
        ]
        
        ZStack {
            Map(coordinateRegion: regionBinding,
                interactionModes: [.all],
                showsUserLocation: true,
                userTrackingMode: .constant(.follow), annotationItems: annotations) { location in
                
                MapAnnotation(
                   coordinate: location.coordinate,
                   content: {
                    Text(location.name).font(.caption2).foregroundColor(.white)
                        .background(Circle()
                            .fill(Color.blue)
                            .frame(width: 40, height: 40))                       }
                )
            }.frame(maxHeight:.infinity)
        }
    }
}
