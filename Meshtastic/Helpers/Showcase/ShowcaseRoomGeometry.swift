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
	/// The display tables, numbered from the viewer: table1 is nearest, table5 is against the back wall.
	case table1 = "Anchor_Table1"
	case table2 = "Anchor_Table2"
	case table3 = "Anchor_Table3"
	case table4 = "Anchor_Table4"
	case table5 = "Anchor_Table5"
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
	/// Every display table, front to back. Each is the same depth, and each top is one slab
	/// thickness plus a gap of four thirds of one above the table in front, up to 1.42 m at the
	/// back wall.
	static let tables: [ShowcaseAnchor] = [.table1, .table2, .table3, .table4, .table5]
	static let tableDepth: Float = 0.35
	/// A table top's thickness (Showcase.usda's TableN_Top).
	static let tableThickness: Float = 0.05
	static let tableStep: Float = tableThickness * 7 / 3
	static let backTableTop: Float = 1.42
	static var frontTableTop: Float { backTableTop - tableStep * Float(tables.count - 1) }
	/// The back table's back edge, just in front of the rack frame.
	static let tablesBackEdgeZ: Float = -2.56
	/// The tables sit left of the room's middle, leaving the right side clear for Chirpy.
	static let tablesCenterX: Float = -0.25
	/// The wall rack, hung above the back table: wide and short, so it clears the devices below.
	static let rackSize = SIMD2<Float>(2.8, 0.9)
	/// Eye height for someone sitting in the chair at the origin.
	static let seatedEye = SIMD3<Float>(0, 1.2, 0)

	static func defaultPose(_ anchor: ShowcaseAnchor) -> ShowcaseAnchorPose {
		switch anchor {
		case .table1, .table2, .table3, .table4, .table5:
			let index = tables.firstIndex(of: anchor) ?? 0
			let fromBack = Float(tables.count - 1 - index)
			return ShowcaseAnchorPose(SIMD3(tablesCenterX, frontTableTop + tableStep * Float(index), tablesBackEdgeZ + tableDepth / 2 + tableDepth * fromBack))
		case .wallRack:
			return ShowcaseAnchorPose(SIMD3(0, 2.2, -2.555))
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
