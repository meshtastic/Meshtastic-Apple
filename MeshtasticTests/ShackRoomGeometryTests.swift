//
//  ShackRoomGeometryTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Ham shack room anchors")
struct ShackRoomGeometryTests {

	@Test("With nothing found, every anchor falls back to its default")
	func allDefaults() {
		let resolved = ShackRoomGeometry.resolve(found: [:])
		#expect(resolved.missing == ShackAnchor.allCases)
		for anchor in ShackAnchor.allCases {
			#expect(resolved.poses[anchor] == ShackRoomGeometry.defaultPose(anchor))
		}
	}

	@Test("A found anchor wins over the default; others still fall back; unknown names are ignored")
	func partial() {
		let moved = ShackAnchorPose(SIMD3<Float>(1, 2, 3))
		let resolved = ShackRoomGeometry.resolve(found: [ShackAnchor.lamp.rawValue: moved, "Anchor_Nope": moved])
		#expect(resolved.poses[.lamp] == moved)
		#expect(resolved.poses[.deskRadio] == ShackRoomGeometry.defaultPose(.deskRadio))
		#expect(!resolved.missing.contains(.lamp))
		#expect(resolved.missing.count == ShackAnchor.allCases.count - 1)
		#expect(resolved.poses.count == ShackAnchor.allCases.count)
	}

	@Test("Side wall anchors face into the room")
	func facing() {
		let rack = ShackRoomGeometry.defaultPose(.wallRack).forward
		let window = ShackRoomGeometry.defaultPose(.window).forward
		#expect(abs(rack.x + 1) < 1e-4)
		#expect(abs(window.x - 1) < 1e-4)
		#expect(abs(ShackRoomGeometry.defaultPose(.deskRadio).forward.z - 1) < 1e-4)
	}

	/// Shack.usda is the source of truth; the defaults must match it so a missing anchor lands
	/// where the room has the matching furniture.
	@Test("Shack.usda has every anchor, at its default position and facing")
	func assetMatchesDefaults() throws {
		let url = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Packages/ShackContent/Sources/ShackContent/ShackContent.rkassets/Shack.usda")
		let text = try String(contentsOf: url, encoding: .utf8)
		let parsed = Self.anchorPoses(in: text)
		for anchor in ShackAnchor.allCases {
			let pose = try #require(parsed[anchor.rawValue], "\(anchor.rawValue) missing from Shack.usda")
			let expected = ShackRoomGeometry.defaultPose(anchor)
			#expect(simd_distance(pose.position, expected.position) < 1e-4, "\(anchor.rawValue) position")
			#expect(simd_distance(pose.forward, expected.forward) < 1e-4, "\(anchor.rawValue) facing")
		}
	}

	/// Reads `def Xform "Anchor_*"` blocks: their translate, and orient (w, x, y, z) if present.
	private static func anchorPoses(in text: String) -> [String: ShackAnchorPose] {
		var poses: [String: ShackAnchorPose] = [:]
		var current: String?
		var pose = ShackAnchorPose(.zero)
		func numbers(_ line: Substring) -> [Float] {
			guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") else { return [] }
			return line[line.index(after: open)..<close].split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
		}
		for line in text.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("def Xform \"Anchor_") {
				if let current { poses[current] = pose }
				current = trimmed.split(separator: "\"")[1].description
				pose = ShackAnchorPose(.zero)
			} else if current != nil, trimmed.hasPrefix("def ") {
				poses[current!] = pose
				current = nil
			} else if current != nil, trimmed.hasPrefix("float3 xformOp:translate") {
				let v = numbers(line)
				if v.count == 3 { pose.position = SIMD3(v[0], v[1], v[2]) }
			} else if current != nil, trimmed.hasPrefix("quatf xformOp:orient") {
				let v = numbers(line)
				if v.count == 4 { pose.orientation = simd_quatf(ix: v[1], iy: v[2], iz: v[3], r: v[0]) }
			}
		}
		if let current { poses[current] = pose }
		return poses
	}
}
