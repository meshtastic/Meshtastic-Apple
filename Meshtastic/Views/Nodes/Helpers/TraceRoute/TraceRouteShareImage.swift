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

	/// Scale the image renders at: 720 points wide becomes 1800 pixels.
	static let scale: CGFloat = 2.5

	/// Renders the share image: takes the map snapshot first when the route has positions, then
	/// draws the card. Without a map (no positions, or the snapshot failed) the card leaves it out.
	@MainActor
	static func render(model: TraceRouteShareModel) async -> TraceRouteShareImage? {
		let model = fittingMap(model)
		var mapImage: UIImage?
		if let map = model.map {
			mapImage = await snapshot(rect: map.rect, size: map.size)
		}
		// The screen closed or the route changed while the map was loading.
		guard !Task.isCancelled else { return nil }
		return image(model: model, mapImage: mapImage)
	}

	/// Sizes the map so the map and the stats under it end level with the hop chains beside them:
	/// a long route fills the left column with map rather than leaving empty space.
	@MainActor
	static func fittingMap(_ model: TraceRouteShareModel) -> TraceRouteShareModel {
		guard model.map != nil else { return model }
		let chains = height(of: TraceRouteShareChains(model: model, sideBySide: false), width: TraceRouteShareStyle.chainColumnWidth)
		let stats = height(of: TraceRouteShareStats(model: model, columns: 2), width: TraceRouteShareStyle.mapWidth)
		guard let chains, let stats else { return model }
		return model.fittingMap(height: (chains - stats - TraceRouteShareStyle.columnSpacing).rounded(.down))
	}

	/// Height of a part of the card laid out at `width`, with the card's environment.
	@MainActor
	private static func height(of view: some View, width: CGFloat) -> CGFloat? {
		let renderer = ImageRenderer(content: view
			.frame(width: width)
			.environment(\.dynamicTypeSize, .large)
			.environment(\.colorScheme, .dark))
		renderer.proposedSize = ProposedViewSize(width: width, height: nil)
		return renderer.uiImage?.size.height
	}

	/// Draws the card into an image.
	@MainActor
	static func image(model: TraceRouteShareModel, mapImage: UIImage?) -> TraceRouteShareImage? {
		let card = TraceRouteShareCard(model: model, mapImage: mapImage)
			.environment(\.dynamicTypeSize, .large)
		let proposal = ProposedViewSize(width: TraceRouteShareStyle.width, height: nil)
		// Round the height up to an even number of points so at 2.5x it's a whole number of pixels.
		let measure = ImageRenderer(content: card)
		measure.proposedSize = proposal
		guard let measured = measure.uiImage?.size.height else { return nil }
		let renderer = ImageRenderer(content: card
			.frame(height: (measured / 2).rounded(.up) * 2, alignment: .top)
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
