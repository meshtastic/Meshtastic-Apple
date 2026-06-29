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

	var body: some View {
		List {
			Section {
				OfflineMapThumbnail(region: current, size: CGSize(width: 320, height: 170), cornerRadius: 12)
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
				LabeledContent("Map updated", value: current.updatedDate.formatted(.relative(presentation: .named)))
				LabeledContent("Source", value: "Protomaps \(current.sourceBuild)")
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
