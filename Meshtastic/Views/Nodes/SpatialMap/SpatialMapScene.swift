//
//  SpatialMapScene.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/10/26.
//
import Foundation

/// The visionOS volume that shows the mesh on a terrain model. Opened with one constant key so
/// every entry point brings the same volume forward instead of opening another.
enum SpatialMapScene {
	static let id = "spatialmap-volume"
}

struct SpatialMapSceneKey: Codable, Hashable {
	static let shared = SpatialMapSceneKey()
}

/// A one-shot ask for the volume to select a node; claimed by the volume once it is showing.
struct SpatialMapFocusRequest: Equatable {
	let id = UUID()
	let nodeNum: Int64
}
