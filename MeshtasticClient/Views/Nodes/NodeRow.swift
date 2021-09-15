//
//  DeviceMap.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/7/21.
//
//  Abstract:
//  A single row to be displayed in a list of landmarks.

import SwiftUI

struct NodeRow: View {
    var node: NodeInfoModel

    var body: some View {
        HStack {
            Image(node.user.hwModel.lowercased()).resizable().frame(width: 150, height: 150)
            
            VStack(alignment: .leading) {
                
                Text(node.user.longName).font(.title2)
                HStack {
                    if node.user.hwModel == "TBEAM" || node.user.hwModel == "TLORA" {
                        Image(systemName: "wifi")
                            .foregroundColor(.blue).font(.title3)
                    }
                    if false {
                        Image(systemName: "rectangle.connected.to.line.below")
                            .foregroundColor(.green).font(.title2)
                    }
                }
            }
            Spacer()
        }
    }
}

struct NodeRow_Previews: PreviewProvider {
    static var nodes = ModelData().nodes

    static var previews: some View {
        Group {
            NodeRow(node: nodes[0])
            NodeRow(node: nodes[1])
            NodeRow(node: nodes[2])
        }
        .previewLayout(.fixed(width: 300, height: 70))
    }
}
