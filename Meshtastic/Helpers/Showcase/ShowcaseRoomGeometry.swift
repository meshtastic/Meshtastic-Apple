//
//  ShowcaseRoomGeometry.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/14/26.
//
import Foundation
import simd

/// The named empty prims in Showcase.usda that code places things at. The raw value is the prim name.
enum ShowcaseAnchor: String, CaseIterable, Sendable {
	case tableFront = "Anchor_TableFront"
	case tableBack = "Anchor_TableBack"
	case wallRack = "Anchor_WallRack"
}

/// Where an anchor sits in the room, in meters from the floor under the viewer (Y up, facing -Z).
/// Local +Z points out of the surface toward the viewer.
struct ShowcaseAnchorPose: Equatable, Sendable {
	var position: SIMD3<Float>
	var orientation: simd_quatf

	init(_ position: SIMD3<Float>, orientation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) {
		self.position = position
		self.orientation = orientation
	}

	/// The direction the anchor faces, into the room.
	var forward: SIMD3<Float> { orientation.act(SIMD3<Float>(0, 0, 1)) }
}

/// The room's measurements, kept in step with Showcase.usda. Used when the asset is missing an anchor
/// (or fails to load), so the rest of the showcase can still lay itself out.
enum ShowcaseRoomGeometry {
	/// The scene in ShowcaseContent.rkassets.
	static let assetName = "Showcase"

	static let width: Float = 3.4
	static let height: Float = 2.8
	/// Inner face of the back wall, in front of the viewer.
	static let backWallZ: Float = -2.6
	/// The display tables' usable length, inside their legs.
	static let tableLength: Float = 1.8
	/// The front table's riser: its height and how far back of the table's middle it runs.
	static let riserHeight: Float = 0.05
	static let riserOffset: Float = -0.2
	static let rackSize = SIMD2<Float>(1.75, 1.65)
	/// Eye height for someone sitting in the chair at the origin.
	static let seatedEye = SIMD3<Float>(0, 1.2, 0)

	/// A quarter turn about Y: faces +X when positive, -X when negative.
	private static func yaw(_ degrees: Float) -> simd_quatf {
		simd_quatf(angle: degrees * .pi / 180, axis: SIMD3<Float>(0, 1, 0))
	}

	static func defaultPose(_ anchor: ShowcaseAnchor) -> ShowcaseAnchorPose {
		switch anchor {
		case .tableFront: ShowcaseAnchorPose(SIMD3(0, 0.82, -0.95))
		case .tableBack: ShowcaseAnchorPose(SIMD3(0, 0.95, -2.0))
		case .wallRack: ShowcaseAnchorPose(SIMD3(1.655, 1.3, -0.2), orientation: yaw(-90))
		}
	}

	/// Every anchor, taking the asset's pose where it has one and the default otherwise.
	/// `found` is keyed by prim name; names that are not anchors are ignored.
	static func resolve(found: [String: ShowcaseAnchorPose]) -> (poses: [ShowcaseAnchor: ShowcaseAnchorPose], missing: [ShowcaseAnchor]) {
		var poses: [ShowcaseAnchor: ShowcaseAnchorPose] = [:]
		var missing: [ShowcaseAnchor] = []
		for anchor in ShowcaseAnchor.allCases {
			if let pose = found[anchor.rawValue] {
				poses[anchor] = pose
			} else {
				poses[anchor] = defaultPose(anchor)
				missing.append(anchor)
			}
		}
		return (poses, missing)
	}
}
