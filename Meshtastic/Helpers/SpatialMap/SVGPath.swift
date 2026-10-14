//
//  SVGPath.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//
import CoreGraphics
import Foundation

/// Reads the `d` attribute of an SVG `<path>` into a CGPath, in the SVG's own coordinates (y down).
/// Covers the full path grammar: M L H V C S Q T A Z, absolute and relative.
enum SVGPath {
	enum ParseError: Error, Equatable {
		case unexpectedCharacter(Character)
		case missingNumber(command: Character)
		case missingMoveTo
	}

	static func cgPath(_ d: String) throws -> CGPath {
		var scanner = Scanner(bytes: Array(d.utf8))
		let path = CGMutablePath()
		var current = CGPoint.zero
		var subpathStart = CGPoint.zero
		/// The second control point of the last C/S or the control point of the last Q/T, for the
		/// smooth forms, which reflect it.
		var lastCubicControl: CGPoint?
		var lastQuadControl: CGPoint?
		var command: UInt8?
		var hasCurrentPoint = false

		while true {
			scanner.skipSeparators()
			guard let byte = scanner.peek() else { break }
			if Scanner.isCommand(byte) {
				command = byte
				scanner.index += 1
			} else if command == nil {
				throw ParseError.unexpectedCharacter(Character(UnicodeScalar(byte)))
			}
			guard let cmd = command else { break }
			let relative = cmd >= 97
			let upper = relative ? cmd - 32 : cmd
			let name = Character(UnicodeScalar(cmd))
			if upper != UInt8(ascii: "M"), !hasCurrentPoint {
				throw ParseError.missingMoveTo
			}
			func number() throws -> CGFloat {
				guard let value = scanner.number() else { throw ParseError.missingNumber(command: name) }
				return value
			}
			func flag() throws -> Bool {
				guard let value = scanner.flag() else { throw ParseError.missingNumber(command: name) }
				return value
			}
			func point() throws -> CGPoint {
				let x = try number(), y = try number()
				return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
			}
			var cubicControl: CGPoint?
			var quadControl: CGPoint?
			switch upper {
			case UInt8(ascii: "M"):
				current = try point()
				subpathStart = current
				path.move(to: current)
				hasCurrentPoint = true
				// Pairs after the first are line-tos.
				command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
			case UInt8(ascii: "L"):
				current = try point()
				path.addLine(to: current)
			case UInt8(ascii: "H"):
				let x = try number()
				current.x = relative ? current.x + x : x
				path.addLine(to: current)
			case UInt8(ascii: "V"):
				let y = try number()
				current.y = relative ? current.y + y : y
				path.addLine(to: current)
			case UInt8(ascii: "C"):
				let c1 = try point(), c2 = try point(), end = try point()
				path.addCurve(to: end, control1: c1, control2: c2)
				cubicControl = c2
				current = end
			case UInt8(ascii: "S"):
				let c1 = reflect(lastCubicControl, about: current)
				let c2 = try point(), end = try point()
				path.addCurve(to: end, control1: c1, control2: c2)
				cubicControl = c2
				current = end
			case UInt8(ascii: "Q"):
				let control = try point(), end = try point()
				path.addQuadCurve(to: end, control: control)
				quadControl = control
				current = end
			case UInt8(ascii: "T"):
				let control = reflect(lastQuadControl, about: current)
				let end = try point()
				path.addQuadCurve(to: end, control: control)
				quadControl = control
				current = end
			case UInt8(ascii: "A"):
				let rx = try number(), ry = try number(), rotation = try number()
				let largeArc = try flag(), sweep = try flag()
				let end = try point()
				addArc(Arc(rx: rx, ry: ry, rotationDegrees: rotation, largeArc: largeArc, sweep: sweep), from: current, to: end, on: path)
				current = end
			case UInt8(ascii: "Z"):
				path.closeSubpath()
				current = subpathStart
				// Z takes no arguments, so another number after it is an error rather than a repeat.
				command = nil
			default:
				throw ParseError.unexpectedCharacter(name)
			}
			lastCubicControl = cubicControl
			lastQuadControl = quadControl
		}
		return path
	}

	private static func reflect(_ control: CGPoint?, about point: CGPoint) -> CGPoint {
		guard let control else { return point }
		return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
	}

	/// An elliptical arc as cubic curves of at most a quarter turn each, using the endpoint to
	/// center conversion in the SVG spec (appendix B.2.4).
	struct Arc {
		var rx: CGFloat
		var ry: CGFloat
		var rotationDegrees: CGFloat
		var largeArc: Bool
		var sweep: Bool
	}

	static func addArc(_ arc: Arc, from start: CGPoint, to end: CGPoint, on path: CGMutablePath) {
		if start == end { return }
		let largeArc = arc.largeArc, sweep = arc.sweep
		var rx = abs(arc.rx), ry = abs(arc.ry)
		guard rx > 0, ry > 0 else {
			path.addLine(to: end)
			return
		}
		let phi = arc.rotationDegrees * .pi / 180
		let cosPhi = cos(phi), sinPhi = sin(phi)
		let dx = (start.x - end.x) / 2, dy = (start.y - end.y) / 2
		let x1 = cosPhi * dx + sinPhi * dy
		let y1 = -sinPhi * dx + cosPhi * dy
		// Radii too small to reach are scaled up until they just do.
		let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
		if lambda > 1 {
			let scale = lambda.squareRoot()
			rx *= scale
			ry *= scale
		}
		let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
		let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
		var coefficient = (max(numerator, 0) / denominator).squareRoot()
		if largeArc == sweep { coefficient = -coefficient }
		let cx1 = coefficient * rx * y1 / ry
		let cy1 = -coefficient * ry * x1 / rx
		let cx = cosPhi * cx1 - sinPhi * cy1 + (start.x + end.x) / 2
		let cy = sinPhi * cx1 + cosPhi * cy1 + (start.y + end.y) / 2

		func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
			atan2(ux * vy - uy * vx, ux * vx + uy * vy)
		}
		let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
		var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
		if !sweep, delta > 0 { delta -= 2 * .pi }
		if sweep, delta < 0 { delta += 2 * .pi }

		let segments = max(Int((abs(delta) / (.pi / 2)).rounded(.up)), 1)
		let step = delta / CGFloat(segments)
		let k = 4 / 3 * tan(step / 4)
		func onEllipse(_ t: CGFloat) -> CGPoint {
			let x = rx * cos(t), y = ry * sin(t)
			return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
		}
		func derivative(_ t: CGFloat) -> CGPoint {
			let x = -rx * sin(t), y = ry * cos(t)
			return CGPoint(x: cosPhi * x - sinPhi * y, y: sinPhi * x + cosPhi * y)
		}
		var t = theta1
		for index in 0..<segments {
			let next = t + step
			let p0 = onEllipse(t)
			let p3 = index == segments - 1 ? end : onEllipse(next)
			let d0 = derivative(t), d3 = derivative(next)
			path.addCurve(
				to: p3,
				control1: CGPoint(x: p0.x + k * d0.x, y: p0.y + k * d0.y),
				control2: CGPoint(x: p3.x - k * d3.x, y: p3.y - k * d3.y)
			)
			t = next
		}
	}

	/// Steps through the attribute's bytes. Numbers may run together where the grammar allows it:
	/// "1-2" is two numbers, ".5.5" is two, and arc flags are single digits.
	private struct Scanner {
		let bytes: [UInt8]
		var index = 0

		func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }

		static func isCommand(_ byte: UInt8) -> Bool {
			switch byte {
			case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"),
				 UInt8(ascii: "H"), UInt8(ascii: "h"), UInt8(ascii: "V"), UInt8(ascii: "v"),
				 UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
				 UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"),
				 UInt8(ascii: "A"), UInt8(ascii: "a"), UInt8(ascii: "Z"), UInt8(ascii: "z"):
				return true
			default:
				return false
			}
		}

		mutating func skipSeparators() {
			while let byte = peek(), byte == UInt8(ascii: " ") || byte == UInt8(ascii: ",") || byte == 9 || byte == 10 || byte == 13 {
				index += 1
			}
		}

		mutating func flag() -> Bool? {
			skipSeparators()
			guard let byte = peek(), byte == UInt8(ascii: "0") || byte == UInt8(ascii: "1") else { return nil }
			index += 1
			return byte == UInt8(ascii: "1")
		}

		mutating func number() -> CGFloat? {
			skipSeparators()
			let start = index
			if let byte = peek(), byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") { index += 1 }
			var digits = 0, sawDot = false
			while let byte = peek() {
				if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
					digits += 1
				} else if byte == UInt8(ascii: "."), !sawDot {
					sawDot = true
				} else {
					break
				}
				index += 1
			}
			guard digits > 0 else {
				index = start
				return nil
			}
			if let byte = peek(), byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") {
				let mark = index
				index += 1
				if let sign = peek(), sign == UInt8(ascii: "-") || sign == UInt8(ascii: "+") { index += 1 }
				var exponentDigits = 0
				while let byte = peek(), byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
					exponentDigits += 1
					index += 1
				}
				if exponentDigits == 0 { index = mark }
			}
			guard let text = String(bytes: bytes[start..<index], encoding: .ascii), let value = Double(text) else {
				index = start
				return nil
			}
			return CGFloat(value)
		}
	}
}
