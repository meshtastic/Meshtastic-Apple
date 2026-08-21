//
//  NodeTrackTimeRangeTests.swift
//  MeshtasticTests
//

import Foundation
import Testing

@testable import Meshtastic

@Suite("Node track time range")
struct NodeTrackTimeRangeTests {

	@Test("Track segments become more opaque toward the newest location")
	func trackSegmentsFadeFromOldToNew() {
		#expect(NodeTrackAppearance.opacity(forSegmentAt: 0, totalSegments: 4) == 0.25)
		#expect(NodeTrackAppearance.opacity(forSegmentAt: 3, totalSegments: 4) == 1.0)
	}

	@Test("A single track segment is fully visible")
	func singleTrackSegmentIsFullyVisible() {
		#expect(NodeTrackAppearance.opacity(forSegmentAt: 0, totalSegments: 1) == 1.0)
	}

	@Test("Three track coordinates create two chronological segments")
	func trackSegmentIndexesFollowCoordinatePairs() {
		#expect(NodeTrackAppearance.segmentIndexes(forCoordinateCount: 3) == [0, 1])
	}

	@Test("A track requires at least two full-precision coordinates")
	func trackAvailabilityRequiresHistory() {
		#expect(!NodeTrackAppearance.hasTrack(forCoordinateCount: 1))
		#expect(NodeTrackAppearance.hasTrack(forCoordinateCount: 2))
	}

	@Test("Long tracks are sampled to the rendering limit")
	func longTracksAreSampled() {
		let indexes = NodeTrackAppearance.sampledCoordinateIndexes(forCoordinateCount: 1_000)
		#expect(indexes.count == 101)
		#expect(indexes.first == 0)
		#expect(indexes.last == 999)
	}

	@Test("One-hour range excludes a report older than one hour")
	func oneHourExcludesOlderReport() {
		let now = Date(timeIntervalSince1970: 10_000)

		#expect(!NodeTrackTimeRange.oneHour.includes(Date(timeIntervalSince1970: 6_399), relativeTo: now))
	}

	@Test("An out-of-range latest report does not contribute to track geometry")
	func outOfRangeLatestReportIsExcludedFromTrack() {
		struct TrackSample {
			let isLatest: Bool
			let time: Date
		}
		let now = Date(timeIntervalSince1970: 10_000)
		let samples = [
			TrackSample(isLatest: false, time: now.addingTimeInterval(-1_800)),
			TrackSample(isLatest: true, time: now.addingTimeInterval(-3_601))
		]

		let trackSamples = NodeTrackTimeRange.oneHour.filtered(samples, timestamp: \.time, relativeTo: now)

		#expect(trackSamples.count == 1)
		#expect(!trackSamples[0].isLatest)
	}

	@Test("Two-day range includes a report at its boundary")
	func twoDaysIncludesBoundaryReport() {
		let now = Date(timeIntervalSince1970: 200_000)

		#expect(NodeTrackTimeRange.twoDays.includes(Date(timeIntervalSince1970: 27_200), relativeTo: now))
	}

	@Test("All range includes reports of any age")
	func allIncludesAnyDatedReport() {
		#expect(NodeTrackTimeRange.all.includes(Date.distantPast, relativeTo: .now))
	}
}
