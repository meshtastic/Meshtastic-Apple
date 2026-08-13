//
//  MeshtasticVisionApp.swift
//  Meshtastic Vision
//
//  Copyright(c) Garth Vander Houwen 8/12/26.
//
//  Apple Vision Pro client: connect to a Meshtastic node over TCP and show a live
//  mesh map in a window. Shares the network client, node store, and map views with
//  the Apple TV app — both are thin, TCP-only clients of the same radio protocol.
//

import OSLog
import SwiftUI
import SwiftData

@main
struct MeshtasticVisionApp: App {
	private let container: ModelContainer
	@State private var client: MeshClient

	init() {
		// Slim visionOS-local store — just `MeshNode` (shared with the TV app). Persists
		// the node database so the map is populated on relaunch before the radio re-dumps.
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
			Logger.transport.error("🥽 [App] Node store open failed, recreating: \(error.localizedDescription, privacy: .public)")
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
