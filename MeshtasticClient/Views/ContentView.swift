/*
Abstract: Default App View
*/

import SwiftUI

struct ContentView: View {
    @State private var selection: Tab = .nodes

    enum Tab {
        case messages
        case map
        case ble
        case nodes
    }

    var body: some View {
        TabView(selection: $selection) {
            Messages()
                .tabItem {
                    Label("Messages", systemImage: "message")
                }
                .tag(Tab.messages)
            NodeMap()
                .tabItem {
                    Label("Mesh Map", systemImage: "map")
                }
                .tag(Tab.map)
            NodeList()
                .tabItem {
                    Label("Nodes", systemImage: "flipphone")
                }
                .tag(Tab.nodes)
            DeviceBLE()
                .tabItem {
                    Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                }
                .tag(Tab.ble)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(ModelData())
    }
}
