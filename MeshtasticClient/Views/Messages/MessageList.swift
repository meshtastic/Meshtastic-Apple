import Foundation
import SwiftUI
import CoreBluetooth

struct MessageList: View {
    
    @State var typingMessage: String = ""
    
    @ObservedObject var bleManager = BLEManager()
    
    @State var connectedPeripheral: CBPeripheral!
    
    var body: some View {
        NavigationView {
          
            GeometryReader { bounds in
                
                ScrollView {
                    Text(String(bleManager.isSwitchedOn))
                    Text(String(bleManager.connectedPeripheral != nil))
                }.padding(.all)
                
            }
            .navigationTitle("Channels")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct MessageList_Previews: PreviewProvider {
    static let modelData = ModelData()

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
