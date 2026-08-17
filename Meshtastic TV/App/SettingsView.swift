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
	@FocusState private var mapTypeFocused: Bool
	/// MKMapType raw value, shared with MeshTVMapView via the same key.
	@AppStorage("tv.mapType") private var mapTypeRaw: Int = Int(MKMapType.standard.rawValue)
	@StateObject private var offlineBasemap = TVOfflineBasemap()
	@State private var estimate: (tiles: Int, bytes: Int64)?
	/// Mesh stats strip, shared with MapScreen via the same keys.
	@AppStorage("tv.statsBar.enabled") private var statsBarEnabled = true
	@AppStorage("tv.statsBar.edge") private var statsBarEdge: StatsStripEdge = .top

	var body: some View {
		List {
			Section {
				Picker("Map Type", selection: $mapTypeRaw) {
					Text("Standard").tag(Int(MKMapType.standard.rawValue))
					Text("Hybrid").tag(Int(MKMapType.hybrid.rawValue))
					Text("Satellite").tag(Int(MKMapType.satellite.rawValue))
				}
				.pickerStyle(.segmented)
				.focused($mapTypeFocused)
				.accessibilityIdentifier("settings.mapType")

				Toggle("Mesh Stats", isOn: $statsBarEnabled)
				Picker("Stats Position", selection: $statsBarEdge) {
					Text("Top").tag(StatsStripEdge.top)
					Text("Bottom").tag(StatsStripEdge.bottom)
				}
				.pickerStyle(.segmented)
				.disabled(!statsBarEnabled)
			} header: {
				Text("Map")
			} footer: {
				Text("Mesh Stats shows the connected node's mesh totals, radio load and packet counters over the map.")
			}

			offlineMapSection

			Section {
				Button(role: .destructive) {
					confirmClear = true
				} label: {
					Label("Clear Node Database", systemImage: "trash")
				}
				.accessibilityIdentifier("settings.clearNodeDatabase")
			} header: {
				Text("Data")
			} footer: {
				Text("Removes all \(nodes.count) saved nodes from this Apple TV. They repopulate from the radio's database on the next connection.")
			}
		}
		.defaultFocus($mapTypeFocused, true)
		.navigationTitle("Settings")
		.alert("Clear Node Database?", isPresented: $confirmClear) {
			Button("Clear", role: .destructive, action: clearDatabase)
			Button("Cancel", role: .cancel) { }
		} message: {
			Text("This permanently removes all \(nodes.count) saved nodes from this device.")
		}
	}

	/// Offline basemap for use without internet. The region is derived from the mesh's own
	/// node positions rather than a map selector — there is no sane way to drag a bounding
	/// box with a Siri Remote. See TVOfflineBasemap.
	@ViewBuilder
	private var offlineMapSection: some View {
		Section {
			switch offlineBasemap.state {
			case .preparing:
				Label("Preparing…", systemImage: "clock")
			case .downloading(let fraction):
				VStack(alignment: .leading, spacing: 8) {
					Label("Downloading map…", systemImage: "arrow.down.circle")
					ProgressView(value: fraction)
				}
			default:
				Button {
					Task { await offlineBasemap.download(for: nodes) }
				} label: {
					Label(
						offlineBasemap.needsDownload ? "Download Map for This Mesh" : "Update Downloaded Map",
						systemImage: "map"
					)
				}
				.disabled(locatedNodeCount == 0)

				if !offlineBasemap.needsDownload {
					Button(role: .destructive) {
						offlineBasemap.removeDownloadedRegion()
					} label: {
						Label("Remove Downloaded Map", systemImage: "trash")
					}
				}
			}
		} header: {
			Text("Offline Map")
		} footer: {
			offlineMapFooter
		}
		.task {
			estimate = await offlineBasemap.estimate(for: nodes)
		}
	}

	@ViewBuilder
	private var offlineMapFooter: some View {
		if case .failed(let message) = offlineBasemap.state {
			Text(message)
		} else if locatedNodeCount == 0 {
			Text("No node has reported a position yet. Once one does, the map covering your mesh can be downloaded.")
		} else if let region = offlineBasemap.region {
			Text("Covering \(locatedNodeCount) located nodes, \(byteText(region.fileSize)) from the \(region.sourceBuild) map build. Drawn instead of Apple's map when the Map Type is Standard.")
		} else if let estimate {
			Text("Downloads roughly \(byteText(estimate.bytes)) covering the area around your \(locatedNodeCount) located nodes, so the map still draws without internet.")
		} else {
			Text("Downloads the map around your mesh so it still draws without internet.")
		}
	}

	private var locatedNodeCount: Int { nodes.filter(\.hasLocation).count }

	private func byteText(_ bytes: Int64) -> String {
		ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
