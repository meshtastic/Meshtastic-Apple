//
//  TraceRouteShareImage.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreTransferable
import MapKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// A rendered trace route share image, with the route as plain text for apps that only take text.
struct TraceRouteShareImage: Transferable {
	let image: UIImage
	let text: String
	let title: String

	static var transferRepresentation: some TransferRepresentation {
		DataRepresentation(exportedContentType: .png) { item in
			guard let data = item.image.pngData() else { throw CocoaError(.fileWriteUnknown) }
			return data
		}
		.suggestedFileName { _ in "Trace Route.png" }
		ProxyRepresentation(exporting: \.text)
	}
}

enum TraceRouteShareRenderer {

	/// Scale the image renders at: 360 points wide becomes 1080 pixels.
	static let scale: CGFloat = 3

	/// Renders the share image: takes the map snapshot first when the route has positions, then
	/// draws the card. Without a map (no positions, or the snapshot failed) the card leaves it out.
	@MainActor
	static func render(model: TraceRouteShareModel) async -> TraceRouteShareImage? {
		var mapImage: UIImage?
		if let map = model.map {
			mapImage = await snapshot(rect: map.rect, size: map.size)
		}
		return image(model: model, mapImage: mapImage)
	}

	/// Draws the card into an image.
	@MainActor
	static func image(model: TraceRouteShareModel, mapImage: UIImage?) -> TraceRouteShareImage? {
		let card = TraceRouteShareCard(model: model, mapImage: mapImage)
			.environment(\.dynamicTypeSize, .large)
		let proposal = ProposedViewSize(width: TraceRouteShareStyle.width, height: nil)
		// Round the height up to whole points so the image is a whole number of pixels tall.
		let measure = ImageRenderer(content: card)
		measure.proposedSize = proposal
		guard let measured = measure.uiImage?.size.height else { return nil }
		let renderer = ImageRenderer(content: card
			.frame(height: measured.rounded(.up), alignment: .top)
			.background(TraceRouteShareStyle.backgroundBottom))
		renderer.scale = scale
		renderer.isOpaque = true
		renderer.proposedSize = proposal
		guard let image = renderer.uiImage else { return nil }
		let title: String
		if let origin = model.origin, let destination = model.destination {
			title = "\(origin.longName) → \(destination.longName)"
		} else {
			title = String(localized: "Trace Route")
		}
		return TraceRouteShareImage(image: image, text: model.plainText, title: title)
	}

	/// Dark, muted map tiles for an area without points of interest, drawn off the main thread.
	static func snapshot(rect: MKMapRect, size: CGSize) async -> UIImage? {
		let options = MKMapSnapshotter.Options()
		options.mapRect = rect
		options.size = size
		options.scale = scale
		options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
		let configuration = MKStandardMapConfiguration(emphasisStyle: .muted)
		configuration.pointOfInterestFilter = .excludingAll
		configuration.showsTraffic = false
		options.preferredConfiguration = configuration
		return await withCheckedContinuation { continuation in
			MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snapshot, error in
				if let error {
					Logger.services.debug("🪧 [TraceRoute] Share map snapshot failed: \(error.localizedDescription, privacy: .public)")
				}
				continuation.resume(returning: snapshot?.image)
			}
		}
	}
}
