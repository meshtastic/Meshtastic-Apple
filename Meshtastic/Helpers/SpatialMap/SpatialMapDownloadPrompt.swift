//
//  SpatialMapDownloadPrompt.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 10/23/26.
//
import Foundation

/// When the spatial map volume offers to download an offline map by hand. The automatic download
/// covers the area around the mesh, so with no node positions there is nothing for it to download.
/// If the user has downloaded a map the volume shows that; otherwise it opens the map search, once
/// each time it opens.
struct SpatialMapDownloadPrompt: Equatable {
	/// Refreshes to wait before deciding, so nodes still loading from the store or the radio
	/// have a moment to arrive. The volume refreshes every couple of seconds.
	static let settleRefreshes = 4

	private(set) var refreshes = 0
	private(set) var offered = false

	/// Called after each refresh. True when the search should open now.
	mutating func shouldOffer(positionedNodes: Int, hasDownloadedMap: Bool, autoDownload: Bool, isBusy: Bool) -> Bool {
		guard !offered else { return false }
		refreshes += 1
		// Positions arrived, so the automatic download takes it from here. Or there's a map to show.
		if positionedNodes > 0 || hasDownloadedMap {
			offered = true
			return false
		}
		guard autoDownload, !isBusy, refreshes >= Self.settleRefreshes else { return false }
		offered = true
		return true
	}
}
