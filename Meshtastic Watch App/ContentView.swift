//
//  ContentView.swift
//  Meshtastic Watch App
//
//  Copyright(c) Meshtastic 2025.
//

import SwiftUI

/// Root view of the Meshtastic Watch App.
///
/// Uses a tab-based layout:
/// 1. **Foxhunt** – nearby nodes list → compass
/// 2. **Radio** – BLE device connection
struct ContentView: View {

	@StateObject private var bleManager = WatchBLEManager()
	@StateObject private var locationManager = WatchLocationManager()

	var body: some View {
		TabView {
			// Tab 1: Foxhunt
			NavigationStack {
				NearbyNodesListView(bleManager: bleManager, locationManager: locationManager)
			}

			// Tab 2: Radio connection
			NavigationStack {
				DeviceConnectionView(bleManager: bleManager)
			}
		}
		.tabViewStyle(.verticalPage)
		.onAppear {
			locationManager.requestAuthorization()
		}
	}
}

#Preview {
	ContentView()
}
