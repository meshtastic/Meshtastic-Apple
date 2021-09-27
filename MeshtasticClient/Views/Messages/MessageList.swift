import Foundation
import SwiftUI
import CoreBluetooth

struct MessageList: View {
    
    @State var typingMessage: String = ""
    
    @EnvironmentObject var bleManager: BLEManager
    
    var body: some View {
        NavigationView {
            
            GeometryReader { bounds in
                
                NavigationLink(destination: MessageDetail()) {
                    
                    List{
                        
                        HStack {
                            
                            Image(systemName: "dial.max.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: bounds.size.width / 7, height: bounds.size.height / 7)
                                .foregroundColor(Color.blue)
                                .symbolRenderingMode(.hierarchical)
                                .padding(.trailing)
                            
                            Text("Primary")
                                .font(.largeTitle)
                        }.padding([.leading, .trailing])
                    }
                }
            }
            .navigationTitle("Message Channels")
            .navigationBarItems(trailing:
                                  
                ZStack {

                    ConnectedDevice(bluetoothOn: bleManager.isSwitchedOn, deviceConnected: bleManager.connectedPeripheral != nil, name: (bleManager.connectedNode != nil) ? bleManager.connectedNode.user.longName : ((bleManager.connectedPeripheral != nil) ? bleManager.connectedPeripheral.name : "Unknown") ?? "Unknown")
                
                }
            )
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

struct MessageList_Previews: PreviewProvider {
    static let meshData = MeshData()

    static var previews: some View {
        Group {
            MessageList()
        }
    }
}

func sendMessage() {
        //chatHelper.sendMessage(Message(content: typingMessage, user: DataSource.secondUser))
       // typingMessage = ""
    }
