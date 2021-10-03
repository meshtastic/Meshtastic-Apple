import Foundation
import SwiftUI

struct AppSettings: View {
    
    var body: some View {
        NavigationView {
            
            GeometryReader { bounds in
                
                NavigationLink(destination: Messages()) {
                    
                    List{

                    }
                }
            }
            .navigationTitle("App Settings")
        }
    }
}

struct AppSettings_Previews: PreviewProvider {
    static let meshData = MeshData()

    static var previews: some View {
        Group {
            AppSettings()
        }
    }
}
