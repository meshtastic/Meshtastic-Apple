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
/// 2. **Phone** – companion phone connectivity status
struct ContentView: View {

	@StateObject private var phoneManager = PhoneConnectivityManager()
	@StateObject private var locationManager = WatchLocationManager()

	var body: some View {
		TabView {
			// Tab 1: Foxhunt
			NearbyNodesListView(phoneManager: phoneManager, locationManager: locationManager)

			// Tab 2: Phone connectivity
			DeviceConnectionView(phoneManager: phoneManager)
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
