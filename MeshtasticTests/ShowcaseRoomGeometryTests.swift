//
//  ShowcaseRoomGeometryTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd
import Testing
@testable import Meshtastic

@Suite("Showcase room anchors")
struct ShowcaseRoomGeometryTests {

	@Test("With nothing found, every anchor falls back to its default")
	func allDefaults() {
		let resolved = ShowcaseRoomGeometry.resolve(found: [:])
		#expect(resolved.missing == ShowcaseAnchor.allCases)
		for anchor in ShowcaseAnchor.allCases {
			#expect(resolved.poses[anchor] == ShowcaseRoomGeometry.defaultPose(anchor))
		}
	}

	@Test("A found anchor wins over the default; others still fall back; unknown names are ignored")
	func partial() {
		let moved = ShowcaseAnchorPose(SIMD3<Float>(1, 2, 3))
		let resolved = ShowcaseRoomGeometry.resolve(found: [ShowcaseAnchor.tableBack.rawValue: moved, "Anchor_Nope": moved])
		#expect(resolved.poses[.tableBack] == moved)
		#expect(resolved.poses[.tableFront] == ShowcaseRoomGeometry.defaultPose(.tableFront))
		#expect(!resolved.missing.contains(.tableBack))
		#expect(resolved.missing.count == ShowcaseAnchor.allCases.count - 1)
		#expect(resolved.poses.count == ShowcaseAnchor.allCases.count)
	}

	@Test("The rack and the tables face the viewer")
	func facing() {
		let rack = ShowcaseRoomGeometry.defaultPose(.wallRack).forward
		#expect(abs(rack.z - 1) < 1e-4)
		#expect(abs(ShowcaseRoomGeometry.defaultPose(.tableFront).forward.z - 1) < 1e-4)
	}

	/// Showcase.usda is the source of truth; the defaults must match it so a missing anchor lands
	/// where the room has the matching furniture.
	@Test("Showcase.usda has every anchor, at its default position and facing")
	func assetMatchesDefaults() throws {
		let url = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appendingPathComponent("Packages/ShowcaseContent/Sources/ShowcaseContent/ShowcaseContent.rkassets/Showcase.usda")
		let text = try String(contentsOf: url, encoding: .utf8)
		let parsed = Self.anchorPoses(in: text)
		for anchor in ShowcaseAnchor.allCases {
			let pose = try #require(parsed[anchor.rawValue], "\(anchor.rawValue) missing from Showcase.usda")
			let expected = ShowcaseRoomGeometry.defaultPose(anchor)
			#expect(simd_distance(pose.position, expected.position) < 1e-4, "\(anchor.rawValue) position")
			#expect(simd_distance(pose.forward, expected.forward) < 1e-4, "\(anchor.rawValue) facing")
		}
	}

	/// Reads `def Xform "Anchor_*"` blocks: their translate, and orient (w, x, y, z) if present.
	private static func anchorPoses(in text: String) -> [String: ShowcaseAnchorPose] {
		var poses: [String: ShowcaseAnchorPose] = [:]
		var current: String?
		var pose = ShowcaseAnchorPose(.zero)
		func numbers(_ line: Substring) -> [Float] {
			guard let open = line.firstIndex(of: "("), let close = line.lastIndex(of: ")") else { return [] }
			return line[line.index(after: open)..<close].split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
		}
		for line in text.split(separator: "\n") {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("def Xform \"Anchor_") {
				if let current { poses[current] = pose }
				current = trimmed.split(separator: "\"")[1].description
				pose = ShowcaseAnchorPose(.zero)
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
