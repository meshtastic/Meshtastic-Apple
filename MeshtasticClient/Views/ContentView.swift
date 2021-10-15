/*
Abstract: Default App View
*/

import SwiftUI

struct ContentView: View {
    @State private var selection: Tab = .ble

    enum Tab {
        case messages
        case map
        case ble
        case nodes
        case settings
    }

    var body: some View {
        
        TabView(selection: $selection) {
            Channels()
                .tabItem {
                    Label("Messages", systemImage: "text.bubble")
                        .symbolVariant(.none)
                }
                .tag(Tab.messages)
            NodeList()
                .tabItem {
                    Label("Nodes", systemImage: "flipphone")
                        .symbolVariant(.none)
                }
                .tag(Tab.nodes)
            NodeMap()
                .tabItem {
                    Label("Mesh Map", systemImage: "map")
                        .symbolVariant(.none)
                }
                .tag(Tab.map)
            Connect()
                .tabItem {
                    Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                        .symbolVariant(.none)
                }
                .tag(Tab.ble)
            //AppSettings()
            //    .tabItem {
            //        Label("Settings", systemImage: "gear")
            //            .symbolRenderingMode(.hierarchical)
            //    }
            //    .tag(Tab.settings)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MeshData())
    }
}
