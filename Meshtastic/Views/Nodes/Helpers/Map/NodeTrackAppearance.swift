//
//  NodeTrackAppearance.swift
//  Meshtastic
//

import Foundation

/// Shared visual treatment for a node's chronological track. Older reports stay visible
/// without competing with the current position, while the newest segment reads most strongly.
enum NodeTrackAppearance {
	static let maximumRenderedSegments = 100
	static let historyArrowMarkerSize: CGFloat = 16
	static let historyCircleMarkerSize: CGFloat = 12
	static let bannerSpacing: CGFloat = 8
	static let bannerHorizontalPadding: CGFloat = 14
	static let bannerVerticalPadding: CGFloat = 8
	static let minimumTapTarget: CGFloat = 48

	static func sampledCoordinateIndexes(forCoordinateCount coordinateCount: Int) -> [Int] {
		guard coordinateCount > 1 else { return [] }
		guard coordinateCount > maximumRenderedSegments + 1 else { return Array(0..<coordinateCount) }
		let interval = Double(coordinateCount - 1) / Double(maximumRenderedSegments)
		return (0...maximumRenderedSegments).map { index in
			min(Int((Double(index) * interval).rounded()), coordinateCount - 1)
		}
	}

	static func segmentIndexes(forCoordinateCount coordinateCount: Int) -> [Int] {
		guard coordinateCount > 1 else { return [] }
		return Array(0..<(coordinateCount - 1))
	}

	static func hasTrack(forCoordinateCount coordinateCount: Int) -> Bool {
		coordinateCount > 1
	}

	static func opacity(forSegmentAt index: Int, totalSegments: Int) -> Double {
		guard totalSegments > 1 else { return 1.0 }
		let progress = Double(index) / Double(totalSegments - 1)
		return 0.25 + (0.75 * progress)
	}
}
