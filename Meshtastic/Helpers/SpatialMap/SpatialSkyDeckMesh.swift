//
//  SpatialSkyDeckMesh.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/11/26.
//
import Foundation
import simd

/// What the cinema's sky deck puts on the spatial map: a glass box hung off the face of its tower
/// just under the roof, on a steel frame with two braces back into the wall, its ceiling lit.
/// Small, like a marker, scaled up as the rooftop's water tower is. Its back is at z = 0, against
/// the tower's face, and it opens out along +z, turned to the cinema's heading; it stands from its
/// floor at y = 0 up to `height`, where the roof is.
enum SpatialSkyDeck {
	/// The parts drawn in their own material.
	enum Part: CaseIterable {
		/// The front and side panes and the glass floor.
		case glass
		/// The edges, mullions and braces.
		case frame
		/// The lit ceiling.
		case ceiling
	}

	static let halfWidth: Float = 0.0050
	static let depth: Float = 0.0070
	static let boxHeight: Float = 0.0050
	private static let pane: Float = 0.00015
	private static let edge: Float = 0.0004
	/// Drawn at the same scale as the rooftop's water tower, so the two read alike among towers.
	static let scale: Float = SpatialRooftop.scale
	/// From the floor to the top of the box.
	static var height: Float { boxHeight * scale }
	static let triangleBudget = 600

	/// Where the cinema keeps the sky deck's chosen site, as the rooftop's is kept under
	/// "cinemaRooftopSite".
	static let siteKey = "cinemaSkyDeckSite"

	/// Where the cinema keeps the chosen deck's tower height in meters and the bearing it hangs out
	/// along, "height,facing", for the map to hang its box at the roof and against the face.
	static let towerKey = "cinemaSkyDeckTower"

	static func tower(_ value: String) -> (height: Double, facing: Double)? {
		let parts = value.split(separator: ",")
		guard parts.count == 2, let height = Double(parts[0]), let facing = Double(parts[1]) else { return nil }
		return (height, facing)
	}

	static func tower(height: Double, facing: Double) -> String {
		"\(height),\(facing)"
	}

	static func geometry() -> [Part: SpatialMeshData] {
		var parts: [Part: SpatialMeshData] = [:]
		for part in Part.allCases { parts[part] = SpatialMeshData() }
		let w = halfWidth, d = depth, h = boxHeight

		// The floor, the front pane and the two side panes. The back is the tower's wall.
		parts[.glass]?.addPrism(outline: [[-w, 0], [w, 0], [w, d], [-w, d]], bottom: 0, top: pane)
		parts[.glass]?.addPrism(outline: [[-w, d - pane], [w, d - pane], [w, d], [-w, d]], bottom: 0, top: h)
		for side: Float in [-1, 1] {
			let x = side * w
			parts[.glass]?.addPrism(outline: [[min(x, x - side * pane), 0], [max(x, x - side * pane), 0], [max(x, x - side * pane), d], [min(x, x - side * pane), d]], bottom: 0, top: h)
		}
		parts[.ceiling]?.addPrism(outline: [[-w, 0], [w, 0], [w, d], [-w, d]], bottom: h - edge, top: h)

		var frame = SpatialMeshData()
		let corners: [SIMD3<Float>] = [[-w, 0, 0], [w, 0, 0], [w, 0, d], [-w, 0, d]]
		for i in 0..<4 {
			let a = corners[i], b = corners[(i + 1) % 4]
			frame.addStrut(from: a, to: b, width: edge)
			frame.addStrut(from: a + [0, h, 0], to: b + [0, h, 0], width: edge)
		}
		for corner in corners.suffix(2) {
			frame.addStrut(from: corner, to: corner + [0, h, 0], width: edge)
		}
		// Mullions in the front and side panes.
		for x: Float in [-w / 3, w / 3] {
			frame.addStrut(from: [x, 0, d], to: [x, h, d], width: edge * 0.6)
		}
		for side: Float in [-1, 1] {
			frame.addStrut(from: [side * w, 0, d / 2], to: [side * w, h, d / 2], width: edge * 0.6)
		}
		// Braces from under the floor's front corners back up into the wall.
		for side: Float in [-1, 1] {
			frame.addStrut(from: [side * w * 0.8, 0, d * 0.9], to: [side * w * 0.8, -h * 0.9, 0], width: edge)
		}
		parts[.frame] = frame
		for part in Part.allCases {
			if let scaled = parts[part]?.positions.map({ $0 * scale }) { parts[part]?.positions = scaled }
		}
		return parts
	}
}
