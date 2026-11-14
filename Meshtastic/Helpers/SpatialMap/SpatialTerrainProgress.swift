//
//  SpatialTerrainProgress.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/13/26.
//
import Foundation

/// How far a terrain build for the 3D map has got, for the card shown over the map while it builds.
struct SpatialTerrainProgress: Equatable, Sendable {
	enum Phase: Equatable, Sendable {
		/// Reading heights from the downloaded terrain: `done` of `total` tiles.
		case elevation(done: Int, total: Int)
		/// Drawing the map image, its shading and contours.
		case drawing
		/// Making the surface that is drawn.
		case surface
	}

	var phase: Phase

	/// The whole build, 0...1. Reading the heights is most of it; the rest is a step each.
	var fraction: Double {
		switch phase {
		case .elevation(let done, let total):
			total > 0 ? Self.elevationShare * Double(min(done, total)) / Double(total) : 0
		case .drawing:
			Self.elevationShare + 0.1
		case .surface:
			Self.elevationShare + 0.2
		}
	}

	/// Whether `next` is worth showing over this one: a later phase, or at least two percent further
	/// through the heights, so the card isn't redrawn for every tile.
	func isWorthShowing(_ next: SpatialTerrainProgress) -> Bool {
		next.fraction >= fraction + 0.02 || (next.fraction > fraction && !next.isElevation)
	}

	private var isElevation: Bool {
		if case .elevation = phase { return true }
		return false
	}

	private static let elevationShare = 0.7
}
