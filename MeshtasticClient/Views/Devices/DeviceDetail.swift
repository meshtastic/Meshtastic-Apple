/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view showing the details for a device.
*/

import SwiftUI
import MapKit
import CoreLocation
import CoreBluetooth

struct DeviceDetail: View {
    @EnvironmentObject var modelData: ModelData
    var device: Device

    var deviceIndex: Int {
        modelData.devices.firstIndex(where: { $0.id == device.id })!
    }
    
    struct MapLocation: Identifiable {
        let id = UUID()
        let name: String
        let coordinate: CLLocationCoordinate2D
    }
    var body: some View {
        
        let currentCoordinatePosition = CLLocationCoordinate2D(latitude: device.position.latitude, longitude: device.position.longitude)
        let regionBinding = Binding<MKCoordinateRegion>(
            get: {
                MKCoordinateRegion(center: currentCoordinatePosition, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
            },
            set: { _ in }
        )
        
        VStack{
            // Map or Device Image
            if(device.hasGPS) {
                
                let annotations = [
                    MapLocation(name: device.shortName, coordinate: CLLocationCoordinate2D(latitude:device.position.latitude, longitude: device.position.longitude))
                    ]
                
                Map(coordinateRegion: regionBinding, annotationItems: annotations) { location in
                    MapAnnotation(
                       coordinate: location.coordinate,
                       content: {
                        Text(device.shortName).font(.subheadline).foregroundColor(.white)
                            .background(Circle()
                                .fill(Color.blue)
                                .frame(width: 40, height: 40))
                       }
                    )
                }.frame(minHeight: 150, maxHeight: 1000)
            }
            else
            {
                device.image
                    .resizable()
                    .frame(minHeight: 300, maxHeight: 1000)
            }
        }
        
        ZStack {

            VStack(alignment: .leading) {
                
                HStack {
                    if(device.hasGPS){
                        device.image
                        .resizable()
                        .frame(width: 100, height: 100)
                    }
                    Text(device.longName).font(.largeTitle)
                }
                Divider()
                HStack{
                    Image(systemName: "clock").font(.title3).foregroundColor(.blue)
                    let lastHeard = Date(timeIntervalSince1970: device.lastHeard)
                    Text("Last Heard:").font(.headline)
                    Text(lastHeard, style: .date).font(.subheadline)
                    Text(lastHeard, style: .time).font(.subheadline)
                }
                Divider()
                HStack {
                    Text("Meshtastic Version: " + device.firmwareVersion)
                    Spacer()
                    Text("Id: " + device.id)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                HStack {
                    Text("Hardware Model: " + device.hardwareModel)
                    Spacer()
                    Text("Region: " + device.region)
                    
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                Divider()
                HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 14) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.title).foregroundColor(.blue)
                    VStack(alignment: .leading) {
                        
                        Text("AKA").font(.caption)
                        Text(device.shortName).font(.caption2).foregroundColor(.gray)
                    }
                    VStack(alignment: .leading) {
                        
                        Text("Latitude").font(.caption)
                        Text(String(format: "%.4f", device.position.latitude) + "°").font(.caption2).foregroundColor(.gray)
                    }
                    VStack(alignment: .leading) {
                        
                        Text("Longitude").font(.caption)
                        let fourDecimalPlaces = String(format: "%.4f", device.position.longitude)
                        Text(String(fourDecimalPlaces) + "°").font(.caption2).foregroundColor(.gray)
                    }
                    VStack(alignment: .leading) {
                        
                        Text("Altitude").font(.caption)
                        Text(String(device.position.altitude) + " m").font(.caption2).foregroundColor(.gray)
                    }
                    VStack(alignment: .leading) {
                        Text("Battery").font(.caption)
                        Text(String(device.position.batteryLevel) + "%").font(.caption2).foregroundColor(.gray)
                   }
               }
            }
            .padding()
        }
        .navigationTitle(device.longName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DeviceDetail_Previews: PreviewProvider {
    static let modelData = ModelData()

    static var previews: some View {
        DeviceDetail(device: modelData.devices[0])
            .environmentObject(modelData)
    }
}
