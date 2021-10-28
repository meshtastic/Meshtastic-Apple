/*
Abstract:
A view showing the details for a node.
*/

import SwiftUI
import MapKit
import CoreLocation

struct NodeDetail: View {
    
    var node: NodeInfoModel
    
    struct MapLocation: Identifiable {
          let id = UUID()
          let name: String
          let coordinate: CLLocationCoordinate2D
    }
    
    var body: some View {

        GeometryReader { bounds in
            
            VStack {
                
                if(node.position.coordinate != nil) {
                    
                    let nodeCoordinatePosition = CLLocationCoordinate2D(latitude: node.position.latitude!, longitude: node.position.longitude!)
                    
                    let regionBinding = Binding<MKCoordinateRegion>(
                        get: {
                            MKCoordinateRegion(center: nodeCoordinatePosition, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
                        },
                        set: { _ in }
                    )
                    let annotations = [MapLocation(name: node.user.shortName, coordinate: node.position.coordinate!)]
                    
                    Map(coordinateRegion: regionBinding, showsUserLocation: true, userTrackingMode: .none, annotationItems: annotations) { location in
                        MapAnnotation(
                           coordinate: location.coordinate,
                           content: {
							   CircleText(text: node.user.shortName, color: .accentColor)
                           }
                        )
                    }.frame(idealWidth: bounds.size.width, minHeight: bounds.size.height / 2)  
                }
                else
                {
                    Image(node.user.hwModel)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: bounds.size.width, height: bounds.size.height / 2)
                }
                ScrollView {
                    
                    HStack {
                        
                        VStack(alignment: .center) {
                            Text("AKA").font(.title2).fixedSize()
							CircleText(text: node.user.shortName, color: .accentColor)
                                .offset(y:10)
                        }
                        .padding([.leading, .trailing, .bottom])
                        Divider()
                        if node.snr != nil && node.snr! > 0 {
                            VStack(alignment: .center) {
                                
                                Image(systemName: "waveform.path")
                                    .font(.title)
									.foregroundColor(.accentColor)
                                    .symbolRenderingMode(.hierarchical)
                                Text("SNR").font(.title2).fixedSize()
                                Text(String(node.snr ?? 0))
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                            Divider()
                        }
                        VStack(alignment: .center) {
							BatteryIcon(batteryLevel: node.position.batteryLevel, font: .title, color: .accentColor)
                            if node.position.batteryLevel != nil && node.position.batteryLevel! > 0 {
                                Text("Battery").font(.title2).fixedSize()
                                Text(String(node.position.batteryLevel!) + "%")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            else {
                                Text("Powered").font(.title2)
                            }
                        }
                        
                    }.padding(4)
                    Divider()
                    HStack {
                        
                        Image(node.user.hwModel)
                            .resizable()
                            .frame(width:60, height: 60)
                            .cornerRadius(5)
                            
                        Text("Model: " + String(node.user.hwModel))
                            .font(.title3)
                    }
                    .padding()
                    Divider()
                    
                    if node.lastHeard > 0 {
                        
                        HStack{
                            
							Image(systemName: "clock").font(.title2).foregroundColor(.accentColor)
                                let lastHeard = Date(timeIntervalSince1970: TimeInterval(node.lastHeard))
                                Text("Last Heard: \(lastHeard, style: .relative) ago").font(.title3)
                        }.padding()
                        Divider()
                    }
                    
                    if node.position.coordinate != nil {
                        HStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/, spacing: 14) {
							Image(systemName: "mappin").font(.title).foregroundColor(.accentColor)
                            VStack(alignment: .leading) {
                                Text("Latitude").font(.headline)
                                Text(String(node.position.latitude ?? 0)).font(.caption).foregroundColor(.gray)
                            }
                            Divider()
                            VStack(alignment: .leading) {
                                Text("Longitude").font(.headline)
                                Text(String(node.position.longitude ?? 0)).font(.caption).foregroundColor(.gray)
                            }
                            Divider()
                            VStack(alignment: .leading) {
                                Text("Altitude").font(.headline)
                                Text(String(node.position.altitude ?? 0) + " m").font(.caption).foregroundColor(.gray)
                            }
                        }.padding()
                        Divider()
                    }
                    HStack (alignment: .center) {
                        VStack {
                            HStack{
                                Image(systemName: "person").font(.title3).foregroundColor(.accentColor)
                                Text("Unique Id:").font(.title3)
                            }
                            Text(node.user.id).font(.headline).foregroundColor(.gray)
                        }
                        Divider()
                        VStack {
                            HStack {
								Image(systemName: "number").font(.title3).foregroundColor(.accentColor)
                                Text("Node Number:").font(.title3)
                            }
                            Text(String(node.num)).font(.headline).foregroundColor(.gray)
                        }
                    }.padding()
                }
            }.navigationTitle(node.user.longName)
            .navigationBarTitleDisplayMode(.inline)
        }.ignoresSafeArea(.all, edges: [.leading, .trailing])
    }
}


struct NodeDetail_Previews: PreviewProvider {
	static let bleManager = BLEManager()

    static var previews: some View {
        Group {
			NodeDetail(node: bleManager.meshData.nodes[0])
			NodeDetail(node: bleManager.meshData.nodes[1])
        }
    }
}
