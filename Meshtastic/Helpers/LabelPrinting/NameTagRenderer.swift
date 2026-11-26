//
//  NameTagRenderer.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/25/26.
//

import CoreGraphics
import CoreImage.CIFilterBuiltins
import CoreText
import Foundation
import MeshtasticProtobufs
#if canImport(UIKit)
import UIKit
#endif

/// What a name tag shows for a node.
struct NameTagContent {
	var shortName: String
	var longName: String
	var nodeID: String
	/// The shared-contact link for the QR, with the long name cut to at most this many bytes
	/// (nil for the whole name), or nil when the node can't be shared.
	var contactURL: (_ longNameBytes: Int?) -> String?

	init(node: NodeInfo) {
		shortName = node.user.shortName
		longName = node.user.longName
		nodeID = node.user.id.isEmpty ? String(format: "!%08x", node.num) : node.user.id
		contactURL = { cut in
			var trimmed = node
			if let cut {
				// Whole characters that fit in `cut` bytes, so an emoji is never split.
				var kept = ""
				for character in node.user.longName {
					if kept.utf8.count + character.utf8.count > cut { break }
					kept.append(character)
				}
				trimmed.user.longName = kept
			}
			return ShareContactQR.urlString(for: trimmed, manuallyVerified: false)
		}
	}

	init(shortName: String, longName: String, nodeID: String, contactURL: @escaping (Int?) -> String?) {
		self.shortName = shortName
		self.longName = longName
		self.nodeID = nodeID
		self.contactURL = contactURL
	}
}

/// The name tag from meshtastic/labeltastic's D110 die-cut layout, drawn natively at one
/// pixel per printer dot in reading orientation (along the feed): `lengthDots` x 96. The
/// rules match labeltastic's render_compact; the text font is the system's rather than
/// DejaVu, so lines can break in slightly different places.
enum NameTagRenderer {
	static let headDots = 96
	/// Labeltastic's die-cut length: 8 dots per mm, less 4 rows of slack for the gap.
	static func lengthDots(millimeters: Int) -> Int { millimeters * 8 - 4 }

	private static let endPx = 3
	private static let edgePx = 2
	private static let narrowPx = 180
	private static let bandPx = 22
	private static let markPx = 18

	static func image(for content: NameTagContent, lengthDots length: Int) -> CGImage? {
		let across = headDots
		guard let canvas = NameTagCanvas(width: length, height: across) else { return nil }
		let e = edgePx

		// The QR keeps all 96 dots at 2 per module, so long names are trimmed in its payload
		// only, as labeltastic does. Its width is just the code plus a one-module quiet zone.
		var qrWidth = 0
		if let modules = qrModules(for: content, maxSide: across) {
			// The largest whole number of dots per module that fits, as labeltastic picks it.
			let module = max(1, across / (modules.count + 2))
			let side = modules.count * module
			let top = (across - side) / 2
			canvas.fill(x: endPx, y: 0, width: side + 2 * module, height: across, gray: 1)
			for (row, line) in modules.enumerated() {
				for (column, ink) in line.enumerated() where ink {
					canvas.fill(x: endPx + module + column * module, y: top + row * module, width: module, height: module, gray: 0)
				}
			}
			qrWidth = side + 2 * module
		}
		let x = endPx + qrWidth + 6
		let width = length - x - endPx
		let narrow = width < narrowPx

		let top: Int
		if narrow {
			top = e
		} else {
			canvas.band(in: CGRect(x: x, y: e, width: width, height: bandPx), text: String(localized: "HELLO MY NODE IS", comment: "Printed name tag header"), size: 21)
			top = e + bandPx
		}

		let markWidth = canvas.drawMark(height: markPx, right: length - endPx, bottom: across - e)

		let short = NameTagCanvas.clean(content.shortName)
		let long = NameTagCanvas.clean(content.longName).isEmpty ? "?" : NameTagCanvas.clean(content.longName)
		let nid = content.nodeID
		// The short name is shown once, as typed. An emoji-only one (one emoji fills the 4
		// bytes a short name allows) becomes the flair and the long name the big line.
		let emojiOnly = !short.isEmpty && short.unicodeScalars.allSatisfy { NameTagCanvas.isEmoji($0) || $0.properties.isWhitespace }
		let flair = emojiOnly ? short.trimmingCharacters(in: .whitespaces) : ""
		let letters = emojiOnly ? "" : (short.isEmpty ? String(nid.suffix(4)) : short)
		var textWidth = width

		if !flair.isEmpty && narrow {
			// 30 mm is too narrow to share: the long name takes the full width and all the
			// height above the bottom row, where the emoji sits between the ID and the mark.
			let row = 22
			let rowY = across - e - row / 2
			let flairSize = row - 2
			let flairWidth = Int(canvas.width(of: flair, size: flairSize))
			let flairX = length - endPx - markWidth - 4 - flairWidth
			canvas.draw(flair, x: x, yCenter: rowY - 1, size: flairSize, startingAt: flairX)
			let (idText, idSize) = canvas.fit(nid, maxWidth: flairX - x - 4, size: 16)
			canvas.draw(idText, x: x, yCenter: rowY, size: idSize)
			let available = across - e - row - 2 - top
			var lines: [String] = []
			var nameSize = 0
			for size in stride(from: 34, through: 12, by: -1) {
				if let wrapped = canvas.wrapLines(long, width: width, size: size, maxLines: 3),
				   wrapped.count * (size + 2) <= available {
					lines = wrapped
					nameSize = size
					break
				}
			}
			if lines.isEmpty {
				let (text, size) = canvas.fit(long, maxWidth: width, size: 18)
				lines = [text]
				nameSize = size
			}
			var y = top + (available - lines.count * (nameSize + 2)) / 2
			for line in lines {
				canvas.draw(line, x: x, yCenter: y + nameSize / 2 + 1, size: nameSize)
				y += nameSize + 2
			}
			return canvas.image()
		}

		if !flair.isEmpty {
			// Fill the space above the mark, but stop at a quarter of the column so the
			// names keep their room (never under 26: still a picture).
			var size = across - e - markPx - 4 - top - 2
			while size > 26 && canvas.width(of: flair, size: size) > CGFloat(max(26, width / 4)) {
				size -= 1
			}
			let flairWidth = Int(canvas.width(of: flair, size: size))
			let flairY = (top + across - e - markPx - 4) / 2
			canvas.draw(flair, x: length - endPx - flairWidth, yCenter: flairY, size: size)
			textWidth = width - flairWidth - 6
		}

		let big: Int, longMax: Int, wrappedBig: Int, wrappedLine: Int
		let bigY: Int, longY: Int, wrappedBigY: Int, wrappedY: Int
		let aloneMax: Int, aloneWrap: Int
		if narrow {
			(big, longMax, wrappedBig, wrappedLine) = (38, 20, 32, 16)
			(bigY, longY, wrappedBigY, wrappedY) = (19, 50, 16, 40)
			(aloneMax, aloneWrap) = (30, 24)
		} else {
			(big, longMax, wrappedBig, wrappedLine) = (32, 18, 24, 13)
			(bigY, longY, wrappedBigY, wrappedY) = (15, 40, 11, 27)
			(aloneMax, aloneWrap) = (26, 18)
		}
		let idY = across - e - 9

		if !letters.isEmpty {
			let (text, size) = canvas.fit(long, maxWidth: textWidth, size: longMax)
			if size < 12, let (pair, line) = canvas.wrapTwo(long, width: textWidth, start: wrappedLine, minSize: 11) {
				// The short name gives up a little height for the long name's second line.
				let (shortText, shortSize) = canvas.fit(letters, maxWidth: textWidth, size: wrappedBig)
				canvas.draw(shortText, x: x, yCenter: top + wrappedBigY, size: shortSize)
				canvas.draw(pair.0, x: x, yCenter: top + wrappedY, size: line)
				canvas.draw(pair.1, x: x, yCenter: top + wrappedY + line, size: line)
			} else {
				let (shortText, shortSize) = canvas.fit(letters, maxWidth: textWidth, size: big)
				canvas.draw(shortText, x: x, yCenter: top + bigY, size: shortSize)
				canvas.draw(text, x: x, yCenter: top + longY, size: size)
			}
		} else {
			// Nothing but emoji in the short name: the long name is the name people read,
			// centred in the space above the ID row.
			let (text, size) = canvas.fit(long, maxWidth: textWidth, size: aloneMax)
			let mid = (top + idY - 9) / 2
			if size < 15, let (pair, line) = canvas.wrapTwo(long, width: textWidth, start: aloneWrap, minSize: 13) {
				let first = mid - (line + 2) / 2
				canvas.draw(pair.0, x: x, yCenter: first, size: line)
				canvas.draw(pair.1, x: x, yCenter: first + line + 2, size: line)
			} else {
				canvas.draw(text, x: x, yCenter: mid, size: size)
			}
		}

		// The node ID is what people copy down, so it stays readable.
		let (idText, idSize) = canvas.fit(nid, maxWidth: width - markWidth - 6, size: 16)
		canvas.draw(idText, x: x, yCenter: idY, size: idSize)
		return canvas.image()
	}

	/// The contact QR's modules, trimming the long name in the payload until the code fits
	/// at 2 dots per module with a one-module quiet zone. Nil when the node can't be shared.
	static func qrModules(for content: NameTagContent, maxSide: Int) -> [[Bool]]? {
		var modules: [[Bool]]?
		for cut in [nil, 32, 24, 16] as [Int?] {
			guard let url = content.contactURL(cut), let code = qrMatrix(url) else { return modules }
			modules = code
			if (code.count + 2) * 2 <= maxSide { break }
		}
		return modules
	}

	/// The QR's modules at error correction L, without Core Image's quiet zone.
	static func qrMatrix(_ text: String) -> [[Bool]]? {
		let filter = CIFilter.qrCodeGenerator()
		filter.message = Data(text.utf8)
		filter.correctionLevel = "L"
		guard let output = filter.outputImage,
			  let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
		let width = image.width, height = image.height
		var gray = [UInt8](repeating: 255, count: width * height)
		guard let context = CGContext(
			data: &gray, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
			space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
		) else { return nil }
		context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
		var minX = width, minY = height, maxX = -1, maxY = -1
		for y in 0..<height {
			for x in 0..<width where gray[y * width + x] < 128 {
				minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
			}
		}
		guard maxX >= minX, maxY >= minY else { return nil }
		return (minY...maxY).map { y in (minX...maxX).map { x in gray[y * width + x] < 128 } }
	}
}

/// A grayscale drawing surface, top-left origin, one pixel per printer dot, with the
/// text helpers labeltastic's layouts are written against.
final class NameTagCanvas {
	let context: CGContext
	let width: Int
	let height: Int

	init?(width: Int, height: Int) {
		guard let context = CGContext(
			data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
			space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
		) else { return nil }
		self.context = context
		self.width = width
		self.height = height
		context.setFillColor(gray: 1, alpha: 1)
		context.fill(CGRect(x: 0, y: 0, width: width, height: height))
		context.translateBy(x: 0, y: CGFloat(height))
		context.scaleBy(x: 1, y: -1)
		context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
	}

	func image() -> CGImage? { context.makeImage() }

	func fill(x: Int, y: Int, width: Int, height: Int, gray: CGFloat) {
		context.setFillColor(gray: gray, alpha: 1)
		context.fill(CGRect(x: x, y: y, width: width, height: height))
	}

	// MARK: Fonts

	private static let emojiFont: CGFont? = {
		guard let url = Bundle.main.url(forResource: "NotoEmoji-Regular", withExtension: "ttf"),
			  let provider = CGDataProvider(url: url as CFURL) else { return nil }
		return CGFont(provider)
	}()

	private func font(emoji: Bool, size: Int, condensed: Bool = false) -> CTFont {
		if emoji, let emojiFont = Self.emojiFont {
			return CTFontCreateWithGraphicsFont(emojiFont, CGFloat(size), nil, nil)
		}
		#if canImport(UIKit)
		let font = condensed
			? UIFont.systemFont(ofSize: CGFloat(size), weight: .bold, width: .condensed)
			: UIFont.systemFont(ofSize: CGFloat(size), weight: .bold)
		return font as CTFont
		#else
		return CTFontCreateUIFontForLanguage(.emphasizedSystem, CGFloat(size), nil)!
		#endif
	}

	/// Labeltastic's test for which characters draw from the emoji font.
	static func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
		let value = scalar.value
		return value >= 0x1F000 || (0x2600...0x27BF).contains(value) || (0x2B00...0x2BFF).contains(value)
	}

	/// Joiners, variation selectors and skin tones draw as stray boxes in black and white.
	static func clean(_ text: String) -> String {
		let kept = text.unicodeScalars.filter { scalar in
			let value = scalar.value
			if value == 0x200D || value == 0xFE0E || value == 0xFE0F || (0x1F3FB...0x1F3FF).contains(value) { return false }
			return scalar.properties.generalCategory != .control
		}
		return String(String.UnicodeScalarView(kept)).split(whereSeparator: \.isWhitespace).joined(separator: " ")
	}

	private func runs(_ text: String) -> [(emoji: Bool, text: String)] {
		var result: [(emoji: Bool, text: String)] = []
		for scalar in text.unicodeScalars {
			let emoji = Self.isEmoji(scalar)
			if let last = result.last, last.emoji == emoji {
				result[result.count - 1].text.unicodeScalars.append(scalar)
			} else {
				result.append((emoji, String(scalar)))
			}
		}
		return result
	}

	private func line(_ text: String, font: CTFont, gray: CGFloat = 0) -> CTLine {
		let color = CGColor(gray: gray, alpha: 1)
		let attributes: [NSAttributedString.Key: Any] = [
			NSAttributedString.Key(kCTFontAttributeName as String): font,
			NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
		]
		return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
	}

	// MARK: Text

	func width(of text: String, size: Int) -> CGFloat {
		runs(text).reduce(0) { total, run in
			total + CGFloat(CTLineGetTypographicBounds(line(run.text, font: font(emoji: run.emoji, size: size)), nil, nil, nil))
		}
	}

	/// Draws text with its vertical middle at yCenter, as PIL's "lm" anchor does: halfway
	/// between each font's ascender and descender.
	func draw(_ text: String, x: Int, yCenter: Int, size: Int, startingAt startX: Int? = nil) {
		var cursor = CGFloat(startX ?? x)
		for run in runs(text) {
			let runFont = font(emoji: run.emoji, size: size)
			let baseline = CGFloat(yCenter) + (CTFontGetAscent(runFont) - CTFontGetDescent(runFont)) / 2
			let runLine = line(run.text, font: runFont)
			context.textPosition = CGPoint(x: cursor, y: baseline)
			CTLineDraw(runLine, context)
			cursor += CGFloat(CTLineGetTypographicBounds(runLine, nil, nil, nil))
		}
	}

	/// Shrinks the size until the text fits; at the minimum size, ellipsizes it.
	func fit(_ text: String, maxWidth: Int, size: Int, minSize: Int = 9) -> (String, Int) {
		for candidate in stride(from: size, through: minSize, by: -1) where width(of: text, size: candidate) <= CGFloat(maxWidth) {
			return (text, candidate)
		}
		var trimmed = text
		while trimmed.count > 1 && width(of: trimmed + "…", size: minSize) > CGFloat(maxWidth) {
			trimmed.removeLast()
		}
		return (trimmed + "…", minSize)
	}

	/// Two lines split at a space that each fit, largest size first.
	func wrapTwo(_ text: String, width maxWidth: Int, start: Int, minSize: Int) -> ((String, String), Int)? {
		let words = text.split(separator: " ").map(String.init)
		guard words.count > 1 else { return nil }
		for size in stride(from: start, through: minSize, by: -1) {
			for split in stride(from: words.count - 1, through: 1, by: -1) {
				let first = words[..<split].joined(separator: " "), second = words[split...].joined(separator: " ")
				if width(of: first, size: size) <= CGFloat(maxWidth) && width(of: second, size: size) <= CGFloat(maxWidth) {
					return ((first, second), size)
				}
			}
		}
		return nil
	}

	/// Greedy word wrap; nil when it needs more than maxLines or a word is too wide.
	func wrapLines(_ text: String, width maxWidth: Int, size: Int, maxLines: Int) -> [String]? {
		var lines: [String] = []
		var current = ""
		for word in text.split(separator: " ").map(String.init) {
			let trial = current.isEmpty ? word : current + " " + word
			if width(of: trial, size: size) <= CGFloat(maxWidth) {
				current = trial
				continue
			}
			if current.isEmpty || width(of: word, size: size) > CGFloat(maxWidth) { return nil }
			lines.append(current)
			current = word
		}
		if !current.isEmpty { lines.append(current) }
		return (1...maxLines).contains(lines.count) ? lines : nil
	}

	/// The black HELLO MY NODE IS band: white condensed text as tall as the band allows,
	/// 4 dots of black each side, squeezed sideways rather than shrunk when it's too wide.
	func band(in rect: CGRect, text: String, size: Int) {
		let x = Int(rect.minX), y = Int(rect.minY), bandWidth = Int(rect.width), bandHeight = Int(rect.height)
		fill(x: x, y: y, width: bandWidth, height: bandHeight, gray: 0)
		let bandFont = font(emoji: false, size: size, condensed: true)
		let bandLine = line(text, font: bandFont, gray: 1)
		let bounds = CTLineGetImageBounds(bandLine, context)
		let room = CGFloat(bandWidth - 8)
		let squeeze = min(1, room / max(1, bounds.width))
		let drawnWidth = bounds.width * squeeze
		context.saveGState()
		// Centre the ink, not the advance, and the cap height in the band.
		let left = CGFloat(x) + (CGFloat(bandWidth) - drawnWidth) / 2 - bounds.minX * squeeze
		let baseline = CGFloat(y) + (CGFloat(bandHeight) + CTFontGetCapHeight(bandFont)) / 2
		context.translateBy(x: left, y: baseline)
		context.scaleBy(x: squeeze, y: 1)
		context.textPosition = .zero
		CTLineDraw(bandLine, context)
		context.restoreGState()
	}

	// MARK: Mark

	/// The bare Ms of the Meshtastic M-PWRD mark, `height` dots tall, its right and bottom
	/// edges at the given points. Coordinates from meshtastic/design's M-PWRD_BW_Border.svg,
	/// as labeltastic traces them. Returns its width.
	@discardableResult
	func drawMark(height markHeight: Int, right: Int, bottom: Int) -> Int {
		let (mx, my, mw, mh) = (0.27480, 0.20476, 1.76724, 0.91943)
		let slash = [(0.38985, 1.11826), (0.27480, 1.03796), (0.85635, 0.20476), (0.97139, 0.28505)]
		let chevron = [(1.49623, 0.25395), (2.04204, 1.03727), (1.91897, 1.12302), (1.42250, 0.41052),
					   (0.92756, 1.12419), (0.80430, 1.03871), (1.34843, 0.25412)]
		let scale = Double(markHeight) / mh
		let markWidth = Int((mw / mh * Double(markHeight)).rounded())
		let originX = Double(right - markWidth), originY = Double(bottom - markHeight)
		context.setFillColor(gray: 0, alpha: 1)
		for polygon in [slash, chevron] {
			let path = CGMutablePath()
			for (index, point) in polygon.enumerated() {
				let p = CGPoint(x: originX + (point.0 - mx) * scale, y: originY + (point.1 - my) * scale)
				if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
			}
			path.closeSubpath()
			context.addPath(path)
			context.fillPath()
		}
		return markWidth
	}
}
