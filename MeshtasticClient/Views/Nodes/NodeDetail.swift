
/*
See LICENSE folder for this sample’s licensing information.

Abstract:
A view showing the details for a device.
*/

import SwiftUI
import MapKit
import CoreLocation
import CoreBluetooth

struct NodeDetail: View {
    
    @EnvironmentObject var modelData: ModelData
    var node: NodeInfoModel
    
    var nodeIndex: Int {
        modelData.nodes.firstIndex(where: { $0.id == node.id })!
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
        
        GeometryReader { bounds in
            
            VStack {
                
                // Map or Device Image
                if(node.position.latitudeI != nil && node.position.latitudeI! > 0) {
                    Map(coordinateRegion: regionBinding, showsUserLocation: true, userTrackingMode: .constant(.follow))
                        
                        .frame(idealWidth: bounds.size.width, minHeight: bounds.size.height / 2)
                }
                else
                {
                    Image(node.user.hwModel.lowercased())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: bounds.size.width, height: bounds.size.height / 2)
                }
                ScrollView {
                    HStack {
                        Spacer()
                        Image(systemName: "flipphone").font(.largeTitle).foregroundColor(.blue)
                        Text("Model: " + String(node.user.hwModel)).font(.title)
                        Spacer()
                    }.padding()
                    Divider()
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right").font(.title2).foregroundColor(.blue)
                        VStack(alignment: .center) {
                            
                            Text("SNR").font(.title3)
                            Text(String(node.snr!)).font(.title3).foregroundColor(.gray)
                        }
                        Divider()
                        VStack(alignment: .center) {
                            
                            Text("AKA").font(.title3)
                            Text(node.user.shortName).font(.title3).foregroundColor(.gray)
                        }
                        Divider()
                        VStack(alignment: .leading) {
                            Text("Battery").font(.title3)
                            Text(String(node.position.batteryLevel!) + "%").font(.title3).foregroundColor(.gray)
                       }
                    }.padding(4)
                    Divider()
                    HStack{
                        Image(systemName: "clock").font(.title2).foregroundColor(.blue)
                        let lastHeard = Date(timeIntervalSince1970: node.lastHeard)
                        Text("Last Heard:").font(.title3)
                        Text(lastHeard, style: .relative).font(.title3)
                        Text("ago").font(.title3)
                    }.padding()
                    Divider()
                    HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 14) {
                        Image(systemName: "mappin").font(.title).foregroundColor(.blue)
                        VStack(alignment: .leading) {
                            Text("Latitude").font(.headline)
                            Text(String(node.position.latitudeI!)).font(.caption).foregroundColor(.gray)
                        }
                        VStack(alignment: .leading) {
                            Text("Longitude").font(.headline)
                            Text(String(node.position.longitudeI!)).font(.caption).foregroundColor(.gray)
                        }
                        VStack(alignment: .leading) {
                            Text("Altitude").font(.headline)
                            Text(String(node.position.altitude!) + " m").font(.caption).foregroundColor(.gray)
                        }
                    }.padding()
                    Divider()
                    HStack {
                        Spacer()
                        Image(systemName: "person").font(.title3).foregroundColor(.blue)
                        Text("Unique Id: " + String(node.user.id)).font(.headline)
                        Divider()
                        Image(systemName: "number").font(.title3).foregroundColor(.blue)
                        Text("Node Num: " + String(node.num)).font(.headline)
                        Spacer()
                    }.padding()
                }
            }.navigationTitle(node.user.longName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                HStack {
                    
                    CircleText(text: node.user.shortName).offset(y: -2)
                    
                }
            )
        }.ignoresSafeArea(.all, edges: [.leading, .trailing])
        
    }
}
