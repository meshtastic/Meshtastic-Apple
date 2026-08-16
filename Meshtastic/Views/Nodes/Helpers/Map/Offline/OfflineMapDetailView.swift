//
//  OfflineMapDetailView.swift
//  Meshtastic
//
//  Manage a single downloaded region: preview, rename, resize, or remove.
//

import SwiftUI
import MapKit

struct OfflineMapDetailView: View {
	let region: OfflineMapRegion

	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var manager = OfflineMapManager.shared
	@State private var renaming = false
	@State private var draftName = ""
	@State private var confirmingDelete = false

	/// The live copy from the store, so edits (rename) reflect immediately.
	private var current: OfflineMapRegion {
		manager.regions.first { $0.id == region.id } ?? region
	}

	/// Preview sized to the region's real on-screen aspect (longitude span shrinks
	/// by cos(latitude) on a Mercator map), clamped so extremes stay usable.
	private var previewSize: CGSize {
		let width: CGFloat = 340
		let mkRegion = current.region
		let aspect = (mkRegion.span.longitudeDelta * cos(mkRegion.center.latitude * .pi / 180)) / max(mkRegion.span.latitudeDelta, 0.0001)
		return CGSize(width: width, height: (width / min(max(aspect, 0.8), 2.2)).rounded())
	}

	var body: some View {
		List {
			Section {
				OfflineMapThumbnail(region: current, size: previewSize, cornerRadius: 12)
					.frame(maxWidth: .infinity)
					.listRowInsets(EdgeInsets())
					.listRowBackground(Color.clear)

				NavigationLink {
					RegionSelectorView(target: OfflineRegionTarget(name: current.name, region: current.region), replacing: current)
				} label: {
					Label("Resize Area", systemImage: "arrow.up.left.and.arrow.down.right")
				}
			}

			Section {
				LabeledContent("Name", value: current.name)
				Button {
					draftName = current.name
					renaming = true
				} label: {
					Label("Rename", systemImage: "pencil")
				}
				LabeledContent("Size", value: current.formattedSize)
				LabeledContent("Detail", value: "Zoom \(current.minZoom)–\(current.maxZoom)")
				if let warning = current.zoomCoverage.warningLabel {
					Label(warning, systemImage: "exclamationmark.triangle")
						.font(.callout)
						.foregroundStyle(.orange)
				}
				LabeledContent("Map updated", value: current.updatedDate.formatted(.relative(presentation: .named)))
				LabeledContent("Source", value: current.sourceBuild == "Imported" ? "Imported PMTiles" : "Protomaps \(current.sourceBuild)")
			}

			Section("Terrain") {
				if let terrain = current.terrain {
					LabeledContent("Size", value: current.formattedTerrainSize ?? "")
					LabeledContent("Detail", value: "Zoom 0–\(terrain.maxZoom)")
					LabeledContent("Source", value: "Mapterhorn")
				} else {
					Button {
						manager.downloadTerrain(for: current)
					} label: {
						Label("Add Terrain", systemImage: "mountain.2")
					}
					.disabled(manager.isBusy)
					Text("Elevation data for hillshade and contour lines, downloaded for this area.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			if let fileURL = manager.fileURL(for: current), FileManager.default.fileExists(atPath: fileURL.path) {
				Section {
					ShareLink(item: fileURL) {
						Label("Share Offline Map", systemImage: "square.and.arrow.up")
					}
				}
			}

			Section {
				Button(role: .destructive) {
					confirmingDelete = true
				} label: {
					Label("Remove Download", systemImage: "trash")
				}
			}
		}
		.navigationTitle(current.name)
		.navigationBarTitleDisplayMode(.inline)
		.alert("Rename Map", isPresented: $renaming) {
			TextField("Name", text: $draftName)
			Button("Save") { manager.rename(current, to: draftName) }
			Button("Cancel", role: .cancel) { }
		}
		.confirmationDialog("Remove this offline map?", isPresented: $confirmingDelete, titleVisibility: .visible) {
			Button("Remove Download", role: .destructive) {
				manager.remove(current)
				dismiss()
			}
			Button("Cancel", role: .cancel) { }
		} message: {
			Text("\(current.formattedSize) will be freed on this device.")
		}
	}
}
