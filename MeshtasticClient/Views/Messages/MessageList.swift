import Foundation
import SwiftUI

struct MessageList: View {
    
    @State var typingMessage: String = ""
    
    @ObservedObject var bleManager = BLEManager()
    
    @EnvironmentObject var modelData: ModelData
    
    var body: some View {
        NavigationView {
          
            GeometryReader { bounds in
                
                ScrollView {
                    
                }.padding(.all)
                
            }
            .navigationTitle("Channels")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                HStack {
                    VStack {
                        if bleManager.isSwitchedOn {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .imageScale(.large)
                                .foregroundColor(.green)
                            Text("CONNECTED").font(.caption2).foregroundColor(.gray)
                        }
                        else {
                    
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .imageScale(.large)
                                .foregroundColor(.red)
                            Text("DISCONNECTED").font(.caption).foregroundColor(.gray)
                            
                        }
                    }
                }.offset(x: 10, y: -10)
            )
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
