//
//  SpatialTerrainLoadingCard.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
#if os(visionOS)
import SwiftUI

/// What the card over the 3D map, or in front of the cinema's seat, says: the map downloading,
/// sites being looked for, the terrain building, or why the terrain couldn't be built.
enum SpatialTerrainLoadingStatus: Equatable {
	case downloading(fraction: Double?, step: OfflineMapDownloadProgress.Step?)
	/// Looking through the downloaded maps for the cinema's sites, with what it's looking for.
	case searching(String)
	case building(SpatialTerrainProgress)
	case failed(String)
}

/// The card floating over the 3D map, or in front of the cinema's seat, while terrain downloads or
/// builds, with how far it has got. A failed build shows its reason with Retry until the next build
/// or Close.
struct SpatialTerrainLoadingCard: View {
	let status: SpatialTerrainLoadingStatus
	let onRetry: () -> Void
	let onClose: () -> Void

	var body: some View {
		// Colors fixed like the node card's: over the bright map the glass alone loses contrast.
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline, spacing: 10) {
				Text(title)
					.font(.headline)
				Spacer(minLength: 8)
				if case .failed = status {
					Button(action: onClose) {
						Image(systemName: "xmark")
							.frame(width: 44, height: 44)
					}
					.buttonStyle(SpatialNodeDetailPanel.CardButtonStyle(shape: .circle))
					.accessibilityLabel(String(localized: "Close", comment: "Spatial map loading card: close the card saying the terrain couldn't be built"))
				}
			}
			Text(detail)
				.font(.subheadline)
				.foregroundStyle(.white.opacity(0.6))
				.fixedSize(horizontal: false, vertical: true)
			switch status {
			case .downloading(let fraction?, _):
				ProgressView(value: fraction)
			case .downloading(nil, _), .searching:
				ProgressView()
					.progressViewStyle(.linear)
			case .building(let progress):
				ProgressView(value: progress.fraction)
			case .failed:
				Button(action: onRetry) {
					Label(String(localized: "Retry", comment: "Spatial map loading card: build the terrain again after it failed"), systemImage: "arrow.clockwise")
				}
				.buttonStyle(SpatialNodeDetailPanel.CardButtonStyle(shape: .rounded))
			}
		}
		.tint(.white)
		.foregroundStyle(.white)
		.padding(16)
		.frame(width: 280, alignment: .leading)
		.background(Color(white: 0.11).opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
		.glassBackgroundEffect(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
	}

	private var title: String {
		switch status {
		case .downloading(_, let step?) where step.number == 1:
			String(localized: "Downloading Map", comment: "Spatial map loading card: title while the street map for the area downloads")
		case .downloading:
			String(localized: "Downloading Terrain", comment: "Spatial map loading card: title while the elevation data for the area downloads")
		case .searching:
			String(localized: "Searching the Maps", comment: "Cinema loading card: title while the downloaded maps are searched for summits, coastline or buildings")
		case .building:
			String(localized: "Building Terrain", comment: "Spatial map loading card: title while the 3D terrain is being built")
		case .failed:
			String(localized: "Couldn't Build Terrain", comment: "Spatial map loading card: title when building the 3D terrain failed")
		}
	}

	private var detail: String {
		switch status {
		case .downloading(_, let step?):
			if step.number == 1 {
				String(localized: "Step \(step.number) of \(step.count): streets", comment: "Spatial map loading card: which part of the download is running, the street map")
			} else {
				String(localized: "Step \(step.number) of \(step.count): elevation", comment: "Spatial map loading card: which part of the download is running, the elevation data")
			}
		case .downloading:
			String(localized: "Elevation for the hills and valleys", comment: "Spatial map loading card: what the terrain download is for")
		case .searching(let message):
			message
		case .building(let progress):
			switch progress.phase {
			// The bar shows how far through; the cinema's view counts rings, not tiles.
			case .elevation:
				String(localized: "Reading elevation", comment: "Spatial map loading card: reading heights from the downloaded terrain")
			case .drawing:
				String(localized: "Drawing the map", comment: "Spatial map loading card: drawing the map image laid over the terrain")
			case .surface:
				String(localized: "Building the surface", comment: "Spatial map loading card: making the 3D surface")
			}
		case .failed(let message):
			message
		}
	}
}

/// The card as the map's attachment: it alone watches the download's progress, so a download
/// redraws the card rather than the whole map.
struct SpatialTerrainLoadingAttachment: View {
	let model: SpatialMapModel
	@ObservedObject private var offline = OfflineMapManager.shared

	var body: some View {
		if let status {
			SpatialTerrainLoadingCard(status: status, onRetry: model.retryTerrain, onClose: model.dismissTerrainMessage)
		}
	}

	private var status: SpatialTerrainLoadingStatus? {
		if model.isDownloadingTerrain {
			return .downloading(fraction: offline.activeDownload?.fractionCompleted, step: offline.activeDownload?.step)
		}
		if let progress = model.terrainProgress {
			return .building(progress)
		}
		return model.terrainMessage.map { .failed($0) }
	}
}
#endif
