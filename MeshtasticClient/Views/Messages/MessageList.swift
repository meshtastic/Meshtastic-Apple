import Foundation
import SwiftUI
import CoreBluetooth

struct MessageList: View {
    
    @State var typingMessage: String = ""
    
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var meshData: MeshData
    
    
    var body: some View {
        NavigationView {
          
            GeometryReader { bounds in
                
                ScrollView {
                    Text(String(bleManager.isSwitchedOn))
                    Text(String(bleManager.connectedPeripheral != nil))
                }.padding(.all)
                
            }
            .navigationTitle("Channels")
            .navigationBarItems(trailing:
                                  
                ZStack {

                    ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown")
                }
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MessageList_Previews: PreviewProvider {
    static let meshData = MeshData()

    static var previews: some View {
        Group {
            //NodeDetail(node: modelData.nodes[0]).environmentObject(modelData)
           // NodeDetail(node: modelData.nodes[1]).environmentObject(modelData)
        }
    }
}

func sendMessage() {
        //chatHelper.sendMessage(Message(content: typingMessage, user: DataSource.secondUser))
       // typingMessage = ""
    }
