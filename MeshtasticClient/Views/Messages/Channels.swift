import Foundation
import SwiftUI
import CoreBluetooth

struct Channels: View {
    // Message Data and Bluetooth
    @EnvironmentObject var messageData: MessageData
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        NavigationView {
            
            GeometryReader { bounds in
                
                NavigationLink(destination: Messages()) {
                    
                    List{
                        
                        HStack {
                            
                            Image(systemName: "dial.max.fill")
                                .font(.system(size: 62))
                                .symbolRenderingMode(.hierarchical)
                                .padding(.trailing)
                                .foregroundColor(Color.blue)
                            
                            Text("Primary")
                                .font(.largeTitle)
                            
                        }.padding()
                    }
                }
            }
            .navigationTitle("Channels")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct MessageList_Previews: PreviewProvider {
    static let meshData = MeshData()

    static var previews: some View {
        Group {
            Channels()
        }
    }
}
