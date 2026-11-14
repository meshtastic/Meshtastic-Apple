//
//  SpatialTerrainCache.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
#if os(visionOS)
import RealityKit

/// The last terrains the 3D map built, kept for the whole app: zooming back out to where it just
/// was, and the map's window reopening (as the cinema does when it opens), put one up again
/// without building it. Two, since each holds a large mesh and image.
@MainActor
final class SpatialTerrainCache {
	static let shared = SpatialTerrainCache()

	private struct Entry {
		let key: String
		let model: SpatialTerrainModel
		let entity: ModelEntity
	}

	private var entries: [Entry] = []
	private let limit = 2

	/// The terrain built for `key`, as a copy of its entity: a copy shares the mesh, image and hit
	/// shape, and is never the entity another window, or a fade still running, holds.
	func terrain(for key: String) -> (model: SpatialTerrainModel, entity: ModelEntity)? {
		guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
		let entry = entries.remove(at: index)
		entries.append(entry)
		return (entry.model, entry.entity.clone(recursive: true))
	}

	/// Keeps a terrain just built, or just drawn again, for `key`. A copy is kept, so changes made
	/// to the one put up don't reach it.
	func keep(_ model: SpatialTerrainModel, entity: ModelEntity, for key: String) {
		entries.removeAll { $0.key == key }
		entries.append(Entry(key: key, model: model, entity: entity.clone(recursive: true)))
		if entries.count > limit { entries.removeFirst() }
	}
}
#endif
