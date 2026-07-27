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
	@EnvironmentObject private var accessoryManager: AccessoryManager
	@AppStorage("burning-man-2026-offline-map-prompt-dismissed") private var didDismissBurningManPrompt = false
	@State private var showingBurningManPrompt = false
	@State private var showingImporter = false
	@State private var importError: String?
	@State private var hadBurningManMap = false

	private var burningManRegion: OfflineMapRegion? {
		BurningManOfflinePack.existingRegion(in: manager.regions)
	}

	private var canOfferBurningManMap: Bool {
		BurningManOfflinePack.isEligible(firmwareEdition: accessoryManager.firmwareEdition)
	}

	var body: some View {
		List {
			if canOfferBurningManMap {
				Section {
					if let burningManRegion {
						NavigationLink {
							OfflineMapDetailView(region: burningManRegion)
						} label: {
							Label("Burning Man offline map downloaded", systemImage: "checkmark.circle.fill")
								.foregroundStyle(.green)
						}
					} else {
						Button {
							showingBurningManPrompt = true
						} label: {
							Label("Download Burning Man offline map", systemImage: "map.circle.fill")
						}
						.disabled(manager.isBusy)
					}
				} header: {
					Text("Burning Man")
				} footer: {
					Text("Available because your connected node runs Burning Man firmware.")
				}
			}

			if let download = manager.activeDownload {
				Section {
					OfflineMapDownloadRow(download: download)
				}
			}

			Section {
				NavigationLink {
					DownloadNewMapView()
				} label: {
					Label("Download New Map", systemImage: "plus.circle")
				}
				.disabled(manager.isBusy)
			}

			if manager.regions.isEmpty {
				Section {
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
			hadBurningManMap = burningManRegion != nil
			showBurningManPromptIfNeeded()
		}
		.onChange(of: accessoryManager.firmwareEdition) {
			showBurningManPromptIfNeeded()
		}
		.onChange(of: burningManRegion?.id) {
			if hadBurningManMap, burningManRegion == nil {
				didDismissBurningManPrompt = false
			}
			hadBurningManMap = burningManRegion != nil
			showBurningManPromptIfNeeded()
		}
		.sheet(isPresented: $showingBurningManPrompt, onDismiss: {
			didDismissBurningManPrompt = true
		}) {
			BurningManOfflineMapPrompt {
				manager.startBurningManDownload()
			}
		}
		.fileImporter(isPresented: $showingImporter, allowedContentTypes: [.meshtasticPMTiles]) { result in
			switch result {
			case .success(let url):
				Task {
					let hasAccess = url.startAccessingSecurityScopedResource()
					defer {
						if hasAccess { url.stopAccessingSecurityScopedResource() }
					}
					do {
						_ = try await manager.importPMTiles(from: url)
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

	private func showBurningManPromptIfNeeded() {
		guard canOfferBurningManMap,
			burningManRegion == nil,
			!didDismissBurningManPrompt,
			!manager.isBusy
		else { return }
		showingBurningManPrompt = true
	}
}

private struct BurningManOfflineMapPrompt: View {
	let onDownload: () -> Void
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			VStack(alignment: .leading, spacing: 20) {
				Image(systemName: "map.circle.fill")
					.font(.system(size: 56))
					.foregroundStyle(.orange)
				Text("Download Burning Man offline map")
					.font(.title2.bold())
				Text("Save the Black Rock City basemap before you lose service. It stays on this device until you remove it.")
					.foregroundStyle(.secondary)
				Text("Map data © OpenStreetMap, Protomaps")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Button("Download Offline Map") {
					onDownload()
					dismiss()
				}
					.buttonStyle(.borderedProminent)
					.frame(maxWidth: .infinity)
				Button("Not Now", role: .cancel) { dismiss() }
					.frame(maxWidth: .infinity)
			}
			.padding()
			.navigationTitle("Burning Man")
			.navigationBarTitleDisplayMode(.inline)
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
