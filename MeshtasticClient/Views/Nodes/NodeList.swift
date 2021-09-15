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
    @EnvironmentObject var modelData: ModelData
    

    var body: some View {
        NavigationView {
           
            List {


                ForEach(modelData.nodes) { node in
                    NavigationLink(destination: NodeDetail(node: node)) {
                        NodeRow(node: node)
                    }
                }
            }
            .navigationTitle("All Nodes")

            
        }.navigationViewStyle(StackNavigationViewStyle()) // Force Full screen master details
    }
}

struct NodeList_Previews: PreviewProvider {
    static var previews: some View {
        NodeList()
            .environmentObject(ModelData())
    }
}
