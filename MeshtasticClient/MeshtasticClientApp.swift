//
//  MeshtasticClientApp.swift
//  MeshtasticClient
//
//  Created by Garth Vander Houwen on 8/18/21.
//

import SwiftUI

@main
struct MeshtasticClientApp: App {

    @ObservedObject private var bleManager: BLEManager = BLEManager()
	@ObservedObject private var userSettings: UserSettings = UserSettings()
    
    var body: some Scene {
        WindowGroup {
		ContentView()
			.environmentObject(bleManager)
			.environmentObject(userSettings)
		}
    }
}
