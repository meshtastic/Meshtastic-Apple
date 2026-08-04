//
//  OfflineMapsList.swift
//  Meshtastic
//
//  Lists downloaded offline map regions and the entry point to download a new one.
//

import SwiftUI
import UniformTypeIdentifiers

struct OfflineMapsList: View {
	@ObservedObject private var manager = OfflineMapManager.shared
	@State private var showingImporter = false
	@State private var importError: String?

	var body: some View {
		List {
			if let download = manager.activeDownload {
				Section {
					OfflineMapDownloadRow(download: download)
				}
			}

			Section("Download") {
				NavigationLink {
					DownloadNewMapView()
				} label: {
					Label("Download New Map", systemImage: "plus.circle")
				}
				.disabled(manager.isBusy)
			}

			if manager.regions.isEmpty {
				Section("Downloaded Maps") {
					Text("No offline maps yet. Download an area to use the map without a connection.")
						.font(.callout)
						.foregroundStyle(.secondary)
				}
			} else {
				Section {
					ForEach(manager.regions) { region in
						NavigationLink {
							OfflineMapDetailView(region: region)
						} label: {
							OfflineMapRow(region: region)
						}
					}
				} footer: {
					VStack(alignment: .leading, spacing: 2) {
						Text("\(manager.formattedTotalSize) used on this device")
						Text("Map data © OpenStreetMap, Protomaps")
					}
					.font(.caption)
				}
			}
		}
		.navigationTitle("Offline Maps")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					showingImporter = true
				} label: {
					Label("Import offline map", systemImage: "square.and.arrow.down")
				}
			}
		}
		.onAppear {
			manager.loadIfNeeded()
		}
		.fileImporter(isPresented: $showingImporter, allowedContentTypes: [.meshtasticPMTiles, .meshtasticMBTiles]) { result in
			switch result {
			case .success(let url):
				Task {
					let hasAccess = url.startAccessingSecurityScopedResource()
					defer {
						if hasAccess { url.stopAccessingSecurityScopedResource() }
					}
					do {
						_ = try await manager.importOfflineMap(from: url)
					} catch {
						importError = error.localizedDescription
					}
				}
			case .failure(let error):
				importError = error.localizedDescription
			}
		}
		.alert("Couldn’t Import Offline Map", isPresented: Binding(
			get: { importError != nil },
			set: { if !$0 { importError = nil } }
		)) {
			Button("OK", role: .cancel) { importError = nil }
		} message: {
			Text(importError ?? "")
		}
	}

}

/// One downloaded region in the list.
struct OfflineMapRow: View {
	let region: OfflineMapRegion

	var body: some View {
		HStack(spacing: 12) {
			OfflineMapThumbnail(region: region)
			VStack(alignment: .leading, spacing: 2) {
				Text(region.name)
					.font(.headline)
				Text("\(region.formattedSize) · Updated \(region.updatedDate.formatted(.relative(presentation: .named)))")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
}

/// In-progress (or failed) download banner.
struct OfflineMapDownloadRow: View {
	let download: OfflineMapDownloadProgress
	@ObservedObject private var manager = OfflineMapManager.shared

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Label(download.name, systemImage: "arrow.down.circle")
					.font(.headline)
				Spacer()
				if case .failed = download.state {
					Button("Dismiss") { manager.dismissDownload() }
						.font(.caption)
				} else {
					Button("Cancel") { manager.cancelDownload() }
						.font(.caption)
						.foregroundStyle(.red)
				}
			}
			switch download.state {
			case .failed(let message):
				Text(message)
					.font(.caption)
					.foregroundStyle(.red)
			case .preparing:
				ProgressView()
				Text("Preparing…")
					.font(.caption)
					.foregroundStyle(.secondary)
			case .downloading, .writing:
				ProgressView(value: download.fractionCompleted ?? 0)
				Text(progressDetail)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.padding(.vertical, 4)
	}

	private var progressDetail: String {
		let written = ByteCountFormatter.string(fromByteCount: download.bytesWritten, countStyle: .file)
		let total = ByteCountFormatter.string(fromByteCount: download.estimatedBytes, countStyle: .file)
		if let fraction = download.fractionCompleted {
			return "\(Int(fraction * 100))% · \(written) of \(total)"
		}
		return written
	}
}
