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
		}
		.frame(width: size.width, height: size.height)
		.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
		.task(id: snapshotKey) {
			image = await Self.snapshot(of: region, size: size, dark: colorScheme == .dark)
		}
	}

	/// Re-snapshots when the coverage changes (resize keeps the id) or the theme flips.
	private var snapshotKey: String {
		"\(region.id)|\(region.minLongitude),\(region.minLatitude),\(region.maxLongitude),\(region.maxLatitude)|\(colorScheme == .dark)"
	}

	/// Renders a static MapKit snapshot framing the region, with the actual coverage
	/// boundary drawn on it (dim outside, white outline on the true bounds) so the
	/// preview shows exactly what was downloaded, whatever the container's aspect.
	static func snapshot(of region: OfflineMapRegion, size: CGSize, dark: Bool) async -> UIImage? {
		let options = MKMapSnapshotter.Options()
		var mkRegion = region.region
		// Pad so the coverage sits comfortably inside the frame.
		mkRegion.span.latitudeDelta *= 1.25
		mkRegion.span.longitudeDelta *= 1.25
		options.region = mkRegion
		options.size = size
		options.mapType = .standard
		options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)

		let snapshot: MKMapSnapshotter.Snapshot? = await withCheckedContinuation { continuation in
			MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, error in
				if let error {
					Logger.services.debug("🗺️ [Offline] Thumbnail snapshot failed: \(error.localizedDescription, privacy: .public)")
				}
				continuation.resume(returning: snapshot)
			}
		}
		guard let snapshot else { return nil }

		let northWest = snapshot.point(for: CLLocationCoordinate2D(latitude: region.maxLatitude, longitude: region.minLongitude))
		let southEast = snapshot.point(for: CLLocationCoordinate2D(latitude: region.minLatitude, longitude: region.maxLongitude))
		let bounds = CGRect(
			x: min(northWest.x, southEast.x), y: min(northWest.y, southEast.y),
			width: abs(southEast.x - northWest.x), height: abs(southEast.y - northWest.y)
		)
		guard bounds.width > 4, bounds.height > 4 else { return snapshot.image }

		return UIGraphicsImageRenderer(size: size).image { _ in
			snapshot.image.draw(at: .zero)
			let outline = UIBezierPath(roundedRect: bounds, cornerRadius: 6)
			let outside = UIBezierPath(rect: CGRect(origin: .zero, size: size))
			outside.append(outline)
			outside.usesEvenOddFillRule = true
			UIColor.black.withAlphaComponent(dark ? 0.4 : 0.22).setFill()
			outside.fill()
			UIColor.black.withAlphaComponent(0.3).setStroke()
			outline.lineWidth = 3.5
			outline.stroke()
			UIColor.white.setStroke()
			outline.lineWidth = 1.8
			outline.stroke()
		}
	}
}
