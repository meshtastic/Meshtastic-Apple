//
//  OfflineMapThumbnail.swift
//  Meshtastic
//
//  A snapshot preview of an offline region's coverage, used in the list and detail.
//

import SwiftUI
import MapKit
import OSLog

struct OfflineMapThumbnail: View {
	let region: OfflineMapRegion
	var size = CGSize(width: 64, height: 64)
	var cornerRadius: CGFloat = 8

	@State private var image: UIImage?
	@Environment(\.colorScheme) private var colorScheme

	var body: some View {
		ZStack {
			if let image {
				Image(uiImage: image)
					.resizable()
					.scaledToFill()
			} else {
				Rectangle()
					.fill(Color(.secondarySystemBackground))
					.overlay {
						Image(systemName: "map")
							.foregroundStyle(.secondary)
					}
			}
			RoundedRectangle(cornerRadius: max(cornerRadius - 3, 0))
				.inset(by: 4)
				.stroke(.white.opacity(0.7), lineWidth: 1.5)
		}
		.frame(width: size.width, height: size.height)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
		.task(id: region.id) {
			image = await Self.snapshot(of: region, size: size, dark: colorScheme == .dark)
		}
	}

	/// Renders a static MapKit snapshot framing the region.
	static func snapshot(of region: OfflineMapRegion, size: CGSize, dark: Bool) async -> UIImage? {
		let options = MKMapSnapshotter.Options()
		var mkRegion = region.region
		// Pad so the coverage sits comfortably inside the frame.
		mkRegion.span.latitudeDelta *= 1.4
		mkRegion.span.longitudeDelta *= 1.4
		options.region = mkRegion
		options.size = size
		options.mapType = .standard
		options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)

		return await withCheckedContinuation { continuation in
			MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, error in
				if let error {
					Logger.services.debug("🗺️ [Offline] Thumbnail snapshot failed: \(error.localizedDescription, privacy: .public)")
				}
				continuation.resume(returning: snapshot?.image)
			}
		}
	}
}
