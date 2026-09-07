//
//  TrafficManagementCandidacyTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 9/7/26.
//

import Testing
@testable import Meshtastic

/// Covers the placement tiers on the Traffic Management screen. The thresholds come from the
/// module author: it needs a node reaching 50 or more nodes in a single transmission, ideally
/// around 200 — below that there is no retransmission storm worth policing.
@Suite("Traffic Management candidacy")
struct TrafficManagementCandidacyTests {

	@Test("tiers follow the author's thresholds")
	func tiersFollowTheThresholds() {
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 0) == .limited)
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 37) == .limited)   // c549's real count
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 49) == .limited)
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 50) == .good)
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 199) == .good)
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 200) == .strong)
		#expect(TrafficManagementCandidacy.tier(directNeighborCount: 500) == .strong)
	}

	@Test("every tier's summary names the count")
	func summariesNameTheCount() {
		for count in [3, 75, 240] {
			#expect(TrafficManagementCandidacy.summary(directNeighborCount: count).contains("\(count)"))
		}
	}
}
