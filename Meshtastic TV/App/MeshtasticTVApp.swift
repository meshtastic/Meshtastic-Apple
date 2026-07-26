//
//  MeshtasticTVApp.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/24/26.
//
//  Apple TV client: connect to a Meshtastic node over TCP and show a live mesh map
//  operable with the Siri Remote.
//

import OSLog
import SwiftUI
import SwiftData

@main
struct MeshtasticTVApp: App {
	private let container: ModelContainer
	@State private var client: MeshClient

	init() {
		// Slim tvOS-local store — just `MeshNode` (see MeshNode.swift). Persists the
		// node database so the map is populated on relaunch before the radio re-dumps.
		let container = Self.makeContainer()
		self.container = container
		_client = State(initialValue: MeshClient(context: container.mainContext))
	}

	/// Open the node store, wiping and recreating it if migration fails. The store is
	/// disposable — it fully repopulates from the radio on the next connect — so a
	/// schema change must never brick launch.
	private static func makeContainer() -> ModelContainer {
		do {
			return try ModelContainer(for: MeshNode.self)
		} catch {
			Logger.transport.error("📺 [App] Node store open failed, recreating: \(error.localizedDescription, privacy: .public)")
			let support = URL.applicationSupportDirectory
			for name in ["default.store", "default.store-wal", "default.store-shm"] {
				try? FileManager.default.removeItem(at: support.appending(path: name))
			}
			// swiftlint:disable:next force_try
			return try! ModelContainer(for: MeshNode.self)
		}
	}

	var body: some Scene {
		WindowGroup {
			RootView(client: client)
		}
		.modelContainer(container)
	}
}
