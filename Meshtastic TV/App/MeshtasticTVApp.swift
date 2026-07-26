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
import SwiftData

@main
struct MeshtasticTVApp: App {
	private let container: ModelContainer
	@State private var client: MeshClient

	init() {
		// Slim tvOS-local store — just `MeshNode` (see MeshNode.swift). Persists the
		// node database so the map is populated on relaunch before the radio re-dumps.
		let container = try! ModelContainer(for: MeshNode.self)
		self.container = container
		_client = State(initialValue: MeshClient(context: container.mainContext))
	}

	var body: some Scene {
		WindowGroup {
			RootView(client: client)
		}
		.modelContainer(container)
	}
}
