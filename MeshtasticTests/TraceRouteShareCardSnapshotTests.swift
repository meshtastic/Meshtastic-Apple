//
//  TraceRouteShareCardSnapshotTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import Foundation
import Testing
import UIKit
@testable import Meshtastic

/// Renders the trace route share image through the same pipeline as the Share button, with a
/// drawn placeholder in place of the map tiles so the output doesn't depend on MapKit.
@Suite("Trace route share card snapshots")
@MainActor
struct TraceRouteShareCardSnapshotTests {

	private typealias Fixtures = TraceRouteShareFixtures

	/// A dark grid standing in for the map tiles.
	static func placeholderMap(size: CGSize) -> UIImage {
		let format = UIGraphicsImageRendererFormat()
		format.scale = TraceRouteShareRenderer.scale
		return UIGraphicsImageRenderer(size: size, format: format).image { context in
			UIColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1).setFill()
			context.fill(CGRect(origin: .zero, size: size))
			UIColor(white: 1, alpha: 0.06).setStroke()
			for x in stride(from: 0, through: size.width, by: 24) {
				context.cgContext.move(to: CGPoint(x: x, y: 0))
				context.cgContext.addLine(to: CGPoint(x: x, y: size.height))
			}
			for y in stride(from: 0, through: size.height, by: 24) {
				context.cgContext.move(to: CGPoint(x: 0, y: y))
				context.cgContext.addLine(to: CGPoint(x: size.width, y: y))
			}
			context.cgContext.strokePath()
		}
	}

	private func render(_ model: TraceRouteShareModel) throws -> TraceRouteShareImage {
		let model = TraceRouteShareRenderer.fittingMap(model)
		let mapImage = model.map.map { Self.placeholderMap(size: $0.size) }
		return try #require(TraceRouteShareRenderer.image(model: model, mapImage: mapImage))
	}

	private func assertSnapshot(_ image: UIImage, named name: String, sourceLocation: SourceLocation = #_sourceLocation) {
		guard let data = image.pngData(), let cgImage = image.cgImage else {
			Issue.record("Failed to read the rendered image", sourceLocation: sourceLocation)
			return
		}
		let url = SnapshotReferencePath.referenceURL(
			testFileURL: URL(fileURLWithPath: #filePath),
			snapshotName: name,
			forDocs: false,
			platform: .current
		)
		do {
			try SnapshotReferenceStore().check(
				pngData: data,
				pixelDimensions: SnapshotPixelDimensions(width: cgImage.width, height: cgImage.height),
				referenceURL: url,
				mode: .current()
			)
		} catch {
			Issue.record("\(error)", sourceLocation: sourceLocation)
		}
	}

	@Test("With a map")
	func withMap() throws {
		let image = try render(Fixtures.model())
		#expect(image.image.size.width == TraceRouteShareStyle.width)
		#expect(image.image.scale == TraceRouteShareRenderer.scale)
		// A typical route comes out close to square.
		let aspect = image.image.size.width / image.image.size.height
		#expect(aspect > 0.9 && aspect < 1.3)
		assertSnapshot(image.image, named: "traceRouteShareWithMap")
	}

	@Test("Without positions there is no map and the image keeps its minimum height")
	func withoutMap() throws {
		let image = try render(Fixtures.model(positions: [:]))
		#expect(image.image.size.height >= TraceRouteShareStyle.minimumHeight)
		#expect(image.image.size.height < (try render(Fixtures.model())).image.size.height)
		assertSnapshot(image.image, named: "traceRouteShareWithoutMap")
	}

	@Test("A long route with an unknown repeater grows taller, with the map filling the left column")
	func longRoute() throws {
		let model = TraceRouteShareRenderer.fittingMap(Fixtures.longModel())
		let map = try #require(model.map)
		#expect(map.size.height > map.size.width)
		let image = try render(Fixtures.longModel())
		#expect(image.image.size.width == TraceRouteShareStyle.width)
		assertSnapshot(image.image, named: "traceRouteShareLongRoute")
	}

	@Test("No return route")
	func noReturnRoute() throws {
		let image = try render(Fixtures.model(hasBack: false, roundTrip: nil))
		assertSnapshot(image.image, named: "traceRouteShareNoReturn")
	}

	@Test("A direct observed route")
	func directObserved() throws {
		let image = try render(Fixtures.directObservedModel())
		#expect(image.image.size.height == TraceRouteShareStyle.minimumHeight)
		assertSnapshot(image.image, named: "traceRouteShareDirectObserved")
	}

	@Test("The share item carries the route text and a title")
	func shareItem() throws {
		let image = try render(Fixtures.model())
		#expect(image.title == "Capitol Hill Base → Golden Gardens Summit")
		#expect(image.text == Fixtures.model().plainText)
	}
}
