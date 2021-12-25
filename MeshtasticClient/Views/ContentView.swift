/*
Abstract: Default App View
*/

import SwiftUI

struct ContentView: View {
    @State private var selection: Tab = .ble

    enum Tab {
		case contacts
        case messages
        case map
        case ble
        case nodes
        case settings
    }

    var body: some View {

        TabView(selection: $selection) {
//			Contacts()
//				.tabItem {
//					Label("Contacts", systemImage: "person.crop.circle")
//						.symbolRenderingMode(.hierarchical)
//						.symbolVariant(.none)
//					
//				}
//				.tag(Tab.contacts)
            Channels()
                .tabItem {
                    Label("Messages", systemImage: "text.bubble")
						.symbolRenderingMode(.hierarchical)
                        .symbolVariant(.none)
                }
                .tag(Tab.messages)
			Connect()
				.tabItem {
					Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
						.symbolRenderingMode(.hierarchical)
						.symbolVariant(.none)
				}
				.tag(Tab.ble)
            NodeList()
                .tabItem {
                    Label("Nodes", systemImage: "flipphone")
						.symbolRenderingMode(.hierarchical)
                        .symbolVariant(.none)
                }
                .tag(Tab.nodes)
            NodeMap()
                .tabItem {
                    Label("Mesh Map", systemImage: "map")
						.symbolRenderingMode(.hierarchical)
                        .symbolVariant(.none)
                }
                .tag(Tab.map)
            AppSettings()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                        .symbolRenderingMode(.hierarchical)
						.symbolVariant(.none)
                }
                .tag(Tab.settings)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
