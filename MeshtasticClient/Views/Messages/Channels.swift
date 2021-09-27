import Foundation
import SwiftUI
import CoreBluetooth

struct Channels: View {
    
    var body: some View {
        NavigationView {
            
            GeometryReader { bounds in
                
                NavigationLink(destination: Messages()) {
                    
                    List{
                        
                        HStack {
                            
                            Image(systemName: "dial.max.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 70, height: 70)
                                .foregroundColor(Color.blue)
                                .symbolRenderingMode(.hierarchical)
                                .padding(.trailing)
                            
                            Text("Primary")
                                .font(.largeTitle)
                        }.padding()
                    }
                }
            }
            .navigationTitle("Channels")
        }
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
