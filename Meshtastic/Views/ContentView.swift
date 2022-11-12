/*
Copyright (c) Garth Vander Houwen 2021
*/

import SwiftUI

struct ContentView: View {
   
	@EnvironmentObject var userSettings: UserSettings
	
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
			
			if userSettings.preferredNodeNum > 0 {
				
				Contacts()
				.tabItem {
					Label("Messages", systemImage: "message")
				}
				.tag(Tab.contacts)
			}
			Connect()
				.tabItem {
					Label("Bluetooth", systemImage: "antenna.radiowaves.left.and.right")
				}
				.tag(Tab.ble)
			NodeList()
				.tabItem {
					Label("Nodes", systemImage: "flipphone")
				}
				.tag(Tab.nodes)
			NodeMap()
				.tabItem {
					Label("Mesh Map", systemImage: "map")
				}
				.tag(Tab.map)
			Settings()
				.tabItem {
					Label("Settings", systemImage: "gear")
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
