//
//  SpatialOfflineLabels.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/31/26.
//
import CoreGraphics
import CoreLocation
import CoreText
import UIKit

/// Place and water names printed flat on the spatial map's offline texture, the way the Apple map
/// layers print theirs: the bigger places first, each where it doesn't overlap one already placed.
enum SpatialOfflineLabels {
	/// One label to draw: its text laid out and where it goes on the texture.
	struct Placed {
		let label: OfflineMapLabel
		let halo: CTLine
		let text: CTLine
		/// The text's box on the texture, CoreGraphics coordinates (y up).
		let rect: CGRect
	}

	/// Clear space kept around each label, in points.
	static let padding: CGFloat = 4
	/// Labels stay inside this share of the disk's radius, so none is cut by the bezel.
	static let diskShare: CGFloat = 0.94

	/// How a kind of label is set: size in points, weight, and whether it is spaced capitals.
	struct Style {
		let font: UIFont
		var uppercase = false
		var kern: CGFloat = 0
	}

	static func style(for kind: OfflineMapLabel.Kind) -> Style {
		switch kind {
		case .region: return Style(font: .systemFont(ofSize: 13, weight: .regular), uppercase: true, kern: 2)
		case .city: return Style(font: .systemFont(ofSize: 15, weight: .semibold))
		case .town: return Style(font: .systemFont(ofSize: 13, weight: .medium))
		case .village: return Style(font: .systemFont(ofSize: 11.5, weight: .regular))
		case .suburb: return Style(font: .systemFont(ofSize: 11, weight: .medium), uppercase: true, kern: 1.2)
		case .neighborhood: return Style(font: .systemFont(ofSize: 10, weight: .medium), uppercase: true, kern: 1)
		case .water: return Style(font: .italicSystemFont(ofSize: 12), kern: 0.5)
		}
	}

	static func textColor(for kind: OfflineMapLabel.Kind, dark: Bool) -> UIColor {
		switch kind {
		case .water: return dark ? UIColor(red: 0.55, green: 0.70, blue: 0.90, alpha: 1) : UIColor(red: 0.22, green: 0.42, blue: 0.66, alpha: 1)
		case .suburb, .neighborhood, .region: return UIColor(white: dark ? 0.66 : 0.42, alpha: 1)
		default: return UIColor(white: dark ? 0.90 : 0.18, alpha: 1)
		}
	}

	static func haloColor(dark: Bool) -> UIColor {
		dark ? UIColor(white: 0.08, alpha: 0.85) : UIColor(white: 1, alpha: 0.9)
	}

	/// The labels to print at `zoom` on a texture of `size`, most important first, each clear of
	/// the ones before it and inside the disk. Sizes are in points of `SpatialOfflineMap.strokeScale`
	/// texels.
	static func place(_ labels: [OfflineMapLabel], frame: SpatialFrame, size: CGSize, zoom: Double, dark: Bool) -> [Placed] {
		let scale = SpatialOfflineMap.strokeScale
		let candidates = labels
			.filter { $0.minZoom <= zoom }
			.sorted { ($0.kind, -$0.rank, $0.minZoom, $0.name) < ($1.kind, -$1.rank, $1.minZoom, $1.name) }
		let center = CGPoint(x: size.width / 2, y: size.height / 2)
		let radius = min(size.width, size.height) / 2 * diskShare
		var placed: [Placed] = []
		var taken: [CGRect] = []
		for label in candidates {
			let style = style(for: label.kind)
			let font = style.font.withSize(style.font.pointSize * scale)
			let string = style.uppercase ? label.name.uppercased() : label.name
			let kern = style.kern * scale
			let text = line(string, font: font, kern: kern, attributes: [.foregroundColor: textColor(for: label.kind, dark: dark).cgColor])
			var ascent: CGFloat = 0, descent: CGFloat = 0
			let width = CGFloat(CTLineGetTypographicBounds(text, &ascent, &descent, nil))
			let point = SpatialTextureRenderer.canvasPoint(label.coordinate, frame: frame, size: size)
			let rect = CGRect(x: point.x - width / 2, y: point.y - (ascent + descent) / 2, width: width, height: ascent + descent)
			let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
			guard corners.allSatisfy({ hypot($0.x - center.x, $0.y - center.y) <= radius }) else { continue }
			let padded = rect.insetBy(dx: -padding * scale, dy: -padding * scale)
			guard !taken.contains(where: { $0.intersects(padded) }) else { continue }
			taken.append(padded)
			// An outline about a fifth of the font size wide, drawn under the text.
			let halo = line(string, font: font, kern: kern, attributes: [
				.strokeColor: haloColor(dark: dark).cgColor,
				.strokeWidth: 18 as CGFloat
			])
			placed.append(Placed(label: label, halo: halo, text: text, rect: rect))
		}
		return placed
	}

	private static func line(_ string: String, font: UIFont, kern: CGFloat, attributes: [NSAttributedString.Key: Any]) -> CTLine {
		var all = attributes
		all[.font] = font as CTFont
		if kern > 0 { all[.kern] = kern }
		return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: all))
	}

	/// The texture with the labels printed on it; nil if no label is placed or drawing fails.
	static func draw(_ labels: [OfflineMapLabel], over image: CGImage, frame: SpatialFrame, dark: Bool) -> CGImage? {
		let width = image.width, height = image.height
		let size = CGSize(width: width, height: height)
		let zoom = SpatialOfflineMap.styleZoom(bounds: frame.bounds, width: size.width)
		let placed = place(labels, frame: frame, size: size, zoom: zoom, dark: dark)
		guard !placed.isEmpty,
			  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
									  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
		context.draw(image, in: CGRect(origin: .zero, size: size))
		context.textMatrix = .identity
		context.setLineJoin(.round)
		for label in placed {
			var descent: CGFloat = 0
			CTLineGetTypographicBounds(label.text, nil, &descent, nil)
			context.textPosition = CGPoint(x: label.rect.minX, y: label.rect.minY + descent)
			CTLineDraw(label.halo, context)
			context.textPosition = CGPoint(x: label.rect.minX, y: label.rect.minY + descent)
			CTLineDraw(label.text, context)
		}
		return context.makeImage()
	}
}
