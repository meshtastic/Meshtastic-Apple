//
//  MeshtasticTVApp.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Apple TV client: connect to a Meshtastic node over TCP and show a live mesh map
//  operable with the Siri Remote.
//

import SwiftUI

@main
struct MeshtasticTVApp: App {
	@State private var client = MeshClient()

	var body: some Scene {
		WindowGroup {
			RootView(client: client)
		}
	}
}
