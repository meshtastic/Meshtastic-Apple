//
//  SpatialTowerGlyph.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//
import CoreGraphics
import Foundation

/// The outline the spatial map extrudes into a tower for infrastructure nodes: the Regular glyph
/// of the custom.radio.tower symbol. Asset catalog symbols can't be read back as paths at run
/// time, so its path is copied here; a test checks it still matches the symbol's SVG.
enum SpatialTowerGlyph {
	/// The template only draws the small size; the others are interpolated from it.
	static let symbolID = "Regular-S"

	static let pathData = [
		"M30.39 0.40L43.39 -44.60L40.61 -45.40L27.61 -0.40Z",
		"M60.39 -0.40L47.39 -45.40L44.61 -44.60L57.61 0.40Z",
		"M33.33 -13.80L54.67 -13.80L54.67 -16.20L33.33 -16.20Z",
		"M37.67 -28.80L50.33 -28.80L50.33 -31.20L37.67 -31.20Z",
		"M40.56 -38.80L47.44 -38.80L47.44 -41.20L40.56 -41.20Z",
		"M29.61 1.04L55.27 -13.96L54.06 -16.04L28.39 -1.04Z",
		"M59.61 -1.04L33.94 -16.04L32.73 -13.96L58.39 1.04Z",
		"M34.13 -14.10L51.13 -29.10L49.54 -30.90L32.54 -15.90Z",
		"M55.46 -15.90L38.46 -30.90L36.87 -29.10L53.87 -14.10Z",
		"M38.52 -29.16L48.30 -39.16L46.59 -40.84L36.81 -30.84Z",
		"M51.19 -30.84L41.41 -40.84L39.70 -39.16L49.48 -29.16Z",
		"M39.10 -51.00A4.90 4.90 0 1 0 48.90 -51.00A4.90 4.90 0 1 0 39.10 -51.00Z",
		"M51.94 -40.83A12.90 12.90 0 0 0 51.94 -61.17L50.22 -58.96A10.10 10.10 0 0 1 50.22 -43.04Z",
		"M36.06 -61.17A12.90 12.90 0 0 0 36.06 -40.83L37.78 -43.04A10.10 10.10 0 0 1 37.78 -58.96Z",
		"M56.25 -35.32A19.90 19.90 0 0 0 56.25 -66.68L54.53 -64.47A17.10 17.10 0 0 1 54.53 -37.53Z",
		"M31.75 -66.68A19.90 19.90 0 0 0 31.75 -35.32L33.47 -37.53A17.10 17.10 0 0 1 33.47 -64.47Z",
		"M60.56 -29.80A26.90 26.90 0 0 0 60.56 -72.20L58.84 -69.99A24.10 24.10 0 0 1 58.84 -32.01Z",
		"M27.44 -72.20A26.90 26.90 0 0 0 27.44 -29.80L29.16 -32.01A24.10 24.10 0 0 1 29.16 -69.99Z"
	].joined()

	/// The glyph standing on the origin, y up, `height` tall and centered left to right, with its
	/// overlapping strokes merged into one outline so an extrusion has no seams or holes where the
	/// legs cross the braces.
	static func outline(height: CGFloat) -> CGPath? {
		guard height > 0, let glyph = try? SVGPath.cgPath(pathData) else { return nil }
		let bounds = glyph.boundingBoxOfPath
		guard bounds.height > 0 else { return nil }
		let scale = height / bounds.height
		// SVG y runs down: flip it, and put the bottom of the legs on y = 0.
		var transform = CGAffineTransform(scaleX: scale, y: -scale)
			.translatedBy(x: -bounds.midX, y: -bounds.maxY)
		guard let placed = glyph.copy(using: &transform) else { return nil }
		return placed.normalized(using: .winding)
	}
}
