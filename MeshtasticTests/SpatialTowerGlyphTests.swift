//
//  SpatialTowerGlyphTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/13/26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Meshtastic

/// Covers `SVGPath`, which reads an SVG path's `d` attribute, and the tower outline the spatial map
/// extrudes from the custom.radio.tower symbol.
@Suite("SVGPath")
struct SVGPathTests {

	private func bounds(_ d: String) throws -> CGRect {
		try SVGPath.cgPath(d).boundingBoxOfPath
	}

	private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool {
		abs(a - b) <= tolerance
	}

	@Test("absolute move, lines and close")
	func absoluteLines() throws {
		#expect(try bounds("M0 0L10 0L10 5L0 5Z") == CGRect(x: 0, y: 0, width: 10, height: 5))
	}

	@Test("relative commands follow the current point")
	func relativeLines() throws {
		#expect(try bounds("m2 3l4 0v2h-4z") == CGRect(x: 2, y: 3, width: 4, height: 2))
	}

	@Test("pairs after a move are line-tos")
	func implicitLineTo() throws {
		#expect(try bounds("M0 0 10 0 10 10") == CGRect(x: 0, y: 0, width: 10, height: 10))
	}

	@Test("numbers run together on signs and second decimal points")
	func compactNumbers() throws {
		#expect(try bounds("M0-1L.5.5L-2,3e0") == CGRect(x: -2, y: -1, width: 2.5, height: 4))
	}

	@Test("horizontal and vertical lines, absolute and relative")
	func horizontalVertical() throws {
		#expect(try bounds("M1 1H5V4h-2v-6") == CGRect(x: 1, y: -2, width: 4, height: 6))
	}

	@Test("cubic and smooth cubic curves")
	func cubics() throws {
		let box = try bounds("M0 0C0 10 10 10 10 0S20 -10 20 0")
		#expect(close(box.minX, 0) && close(box.maxX, 20))
		// Each half bulges 7.5 out from the baseline, the second one mirrored by S.
		#expect(close(box.maxY, 7.5) && close(box.minY, -7.5))
	}

	@Test("quadratic and smooth quadratic curves")
	func quadratics() throws {
		let box = try bounds("M0 0Q5 10 10 0T20 0")
		#expect(close(box.maxY, 5) && close(box.minY, -5))
		#expect(close(box.maxX, 20))
	}

	@Test("two half arcs make a full circle")
	func fullCircleArcs() throws {
		let box = try bounds("M0 0A5 5 0 1 0 10 0A5 5 0 1 0 0 0Z")
		#expect(close(box.minX, 0, 0.01) && close(box.maxX, 10, 0.01))
		#expect(close(box.minY, -5, 0.01) && close(box.maxY, 5, 0.01))
	}

	@Test("the sweep flag picks the side of the arc")
	func arcSweep() throws {
		let positive = try bounds("M0 0A5 5 0 0 1 10 0")
		let negative = try bounds("M0 0A5 5 0 0 0 10 0")
		#expect(close(positive.minY, -5, 0.01) && close(positive.maxY, 0, 0.01))
		#expect(close(negative.maxY, 5, 0.01) && close(negative.minY, 0, 0.01))
	}

	@Test("arc flags may be written without separators")
	func packedArcFlags() throws {
		#expect(try bounds("M0 0A5 5 0 1010 0") == bounds("M0 0A5 5 0 1 0 10 0"))
	}

	@Test("radii too small to reach are scaled up")
	func arcRadiiScaled() throws {
		let box = try bounds("M0 0A1 1 0 0 1 10 0")
		#expect(close(box.minY, -5, 0.01))
	}

	@Test("rejects a path that does not start with a move")
	func missingMove() {
		#expect(throws: SVGPath.ParseError.missingMoveTo) { try SVGPath.cgPath("L1 1") }
	}

	@Test("rejects a command missing its numbers")
	func missingNumber() {
		#expect(throws: SVGPath.ParseError.missingNumber(command: "L")) { try SVGPath.cgPath("M0 0L1") }
	}

	@Test("rejects numbers after close")
	func numbersAfterClose() {
		#expect(throws: SVGPath.ParseError.unexpectedCharacter("1")) { try SVGPath.cgPath("M0 0L1 1Z1 1") }
	}
}

@Suite("SpatialTowerGlyph")
struct SpatialTowerGlyphTests {

	@Test("parses the glyph")
	func parses() throws {
		let box = try SVGPath.cgPath(SpatialTowerGlyph.pathData).boundingBoxOfPath
		// The outer arcs reach out to 17.1 and 70.9 around the mast at x = 44; the legs end at y = 1.04.
		#expect(abs(box.midX - 44) < 0.1)
		#expect(abs(box.maxY - 1.04) < 0.01)
		#expect(box.height > 70 && box.height < 75)
	}

	@Test("the outline stands on the origin, centered and the height asked for")
	func outlinePlacement() throws {
		let outline = try #require(SpatialTowerGlyph.outline(height: 0.04))
		let box = outline.boundingBoxOfPath
		#expect(abs(box.minY) < 1e-6)
		#expect(abs(box.height - 0.04) < 1e-6)
		#expect(abs(box.midX) < 1e-6)
		// Wider at the waves than the legs, and narrower than it is tall.
		#expect(box.width > 0.02 && box.width < 0.04)
	}

	@Test("the mast top is above the legs, not flipped")
	func outlineUpright() throws {
		let outline = try #require(SpatialTowerGlyph.outline(height: 0.04))
		// The ball at the top of the mast is centered 52.04 of the glyph's 73.24 units above the legs'
		// ends; the legs straddle the center line below.
		#expect(outline.contains(CGPoint(x: 0, y: 0.04 * 52.04 / 73.24)))
		#expect(!outline.contains(CGPoint(x: 0, y: 0.04 * (1 - 52.04 / 73.24))))
		#expect(!outline.contains(CGPoint(x: 0, y: 0.001)))
	}

	@Test("no outline for a zero height")
	func zeroHeight() {
		#expect(SpatialTowerGlyph.outline(height: 0) == nil)
	}

	@Test("matches the Regular glyph in the symbol's SVG")
	func matchesSymbol() throws {
		let svg = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Meshtastic/Assets.xcassets/custom.radio.tower.symbolset/custom.radio.tower.svg")
		let text = try String(contentsOf: svg, encoding: .utf8)
		let group = try #require(text.range(of: "id=\"\(SpatialTowerGlyph.symbolID)\""))
		let rest = text[group.upperBound...]
		let start = try #require(rest.range(of: " d=\""))
		let end = try #require(rest[start.upperBound...].firstIndex(of: "\""))
		#expect(String(rest[start.upperBound..<end]) == SpatialTowerGlyph.pathData)
	}
}

@Suite("DeviceRoles infrastructure")
struct DeviceRolesInfrastructureTests {

	@Test("routers, repeaters and client bases are infrastructure")
	func infrastructureRoles() {
		for role in [DeviceRoles.router, .routerLate, .clientBase, .repeater] {
			#expect(role.isInfrastructure, "\(role)")
		}
	}

	@Test("every other role is not")
	func otherRoles() {
		let infrastructure: Set<DeviceRoles> = [.router, .routerLate, .clientBase, .repeater]
		for role in DeviceRoles.allCases where !infrastructure.contains(role) {
			#expect(!role.isInfrastructure, "\(role)")
		}
	}

	@Test("reads a stored role number, unknown and missing are not infrastructure")
	func storedRole() {
		#expect(DeviceRoles.isInfrastructure(role: 2))
		#expect(DeviceRoles.isInfrastructure(role: 11))
		#expect(DeviceRoles.isInfrastructure(role: 12))
		#expect(DeviceRoles.isInfrastructure(role: 4))
		#expect(!DeviceRoles.isInfrastructure(role: 0))
		#expect(!DeviceRoles.isInfrastructure(role: 99))
		#expect(!DeviceRoles.isInfrastructure(role: nil))
	}
}
