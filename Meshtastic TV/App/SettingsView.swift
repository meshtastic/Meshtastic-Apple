//
//  SettingsView.swift
//  Meshtastic TV
//
//  Copyright(c) Garth Vander Houwen 7/26/26.
//
//  Apple TV settings. Currently just data management — clearing the persisted node
//  store (see MeshNode). Designed to grow as more tvOS options are added. Pushed as a
//  detail from the connect screen and the map's side list, so it does not wrap its own
//  NavigationStack.
//

import MapKit
import OSLog
import SwiftData
import SwiftUI

struct SettingsView: View {
	@Environment(\.modelContext) private var context
	@Query private var nodes: [MeshNode]
	@State private var confirmClear = false
	@FocusState private var clearFocused: Bool
	/// MKMapType raw value, shared with MeshTVMapView via the same key.
	@AppStorage("tv.mapType") private var mapTypeRaw: Int = Int(MKMapType.standard.rawValue)

	var body: some View {
		List {
			Section {
				Picker("Map Type", selection: $mapTypeRaw) {
					Text("Standard").tag(Int(MKMapType.standard.rawValue))
					Text("Hybrid").tag(Int(MKMapType.hybrid.rawValue))
					Text("Satellite").tag(Int(MKMapType.satellite.rawValue))
				}
				.pickerStyle(.segmented)
			} header: {
				Text("Map")
			}

			Section {
				Button(role: .destructive) {
					confirmClear = true
				} label: {
					Label("Clear Node Database", systemImage: "trash")
				}
				.focused($clearFocused)
			} header: {
				Text("Data")
			} footer: {
				Text("Removes all \(nodes.count) saved nodes from this Apple TV. They repopulate from the radio's database on the next connection.")
			}
		}
		.defaultFocus($clearFocused, true)
		.navigationTitle("Settings")
		.alert("Clear Node Database?", isPresented: $confirmClear) {
			Button("Clear", role: .destructive, action: clearDatabase)
			Button("Cancel", role: .cancel) { }
		} message: {
			Text("This permanently removes all \(nodes.count) saved nodes from this device.")
		}
	}

	private func clearDatabase() {
		do {
			try context.delete(model: MeshNode.self)
			try context.save()
		} catch {
			Logger.transport.error("📺 [Settings] Failed to clear node database: \(error.localizedDescription, privacy: .public)")
		}
	}
}
