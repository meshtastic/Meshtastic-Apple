import Foundation
import SwiftUI
import CoreBluetooth

struct Channels: View {
	@State private var isShowingDetailView = true
	    
    var body: some View {
        NavigationView {
            
            GeometryReader { bounds in
                
                NavigationLink(destination: Messages(), isActive: $isShowingDetailView) {
                    
                    List{
                        
                        HStack {
                            
                            Image(systemName: "dial.max.fill")
                                .font(.system(size: 62))
                                .symbolRenderingMode(.hierarchical)
                                .padding(.trailing)
								.foregroundColor(.accentColor)
                            
                            Text("Primary")
                                .font(.largeTitle)
                            
                        }.padding()
                    }
                }
            }
            .navigationTitle("Channels")
        }
		.navigationViewStyle(DoubleColumnNavigationViewStyle())
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
