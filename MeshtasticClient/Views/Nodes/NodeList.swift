//
//  DeviceHome.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//

// Abstract:
//  A view showing a list of devices that have been seen on the mesh network

import SwiftUI

struct NodeList: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var meshData: MeshData
    
    @State private var showLocationOnly = false
    
    var filteredDevices: [NodeInfoModel] {
        meshData.nodes.filter { node in
            (!showLocationOnly || node.position.coordinate != nil)
        }
    }

    var body: some View {
        NavigationView {
           
            List {
                Toggle(isOn: $showLocationOnly) {
                    Text("Nodes with location only")
                }
                ForEach(filteredDevices.sorted(by: { $0.lastHeard > $1.lastHeard })) { node in
                    NavigationLink(destination: NodeDetail(node: node)) {
                        NodeRow(node: node, index : 0)
    
                    }
                }
            }
            .navigationTitle("All Nodes")
        }
    }
}

struct NodeList_Previews: PreviewProvider {
    static var previews: some View {
        NodeList()
            .environmentObject(MeshData())
    }
}
