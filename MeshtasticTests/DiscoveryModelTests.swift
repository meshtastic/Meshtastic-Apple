// MARK: DiscoveryModelTests

import Foundation
import SwiftData
import Testing

@testable import Meshtastic

@Suite("Discovery Models")
struct DiscoveryModelTests {

	// MARK: - DiscoverySessionEntity

	@Test func sessionEntityDefaultValues() {
		let session = DiscoverySessionEntity()
		#expect(session.presetsScanned == "")
		#expect(session.totalUniqueNodes == 0)
		#expect(session.averageChannelUtilization == 0.0)
		#expect(session.totalTextMessages == 0)
		#expect(session.totalSensorPackets == 0)
		#expect(session.furthestNodeDistance == 0.0)
		#expect(session.completionStatus == "inProgress")
		#expect(session.aiSummaryText == "")
		#expect(session.presetResults.isEmpty)
		#expect(session.discoveredNodes.isEmpty)
	}

	// MARK: - DiscoveryPresetResultEntity

	@Test func presetResultDefaultValues() {
		let result = DiscoveryPresetResultEntity()
		#expect(result.presetName == "")
		#expect(result.dwellDurationSeconds == 0)
		#expect(result.uniqueNodesFound == 0)
		#expect(result.directNeighborCount == 0)
		#expect(result.meshNeighborCount == 0)
		#expect(result.messageCount == 0)
		#expect(result.sensorPacketCount == 0)
		#expect(result.averageChannelUtilization == 0.0)
		#expect(result.averageAirtimeRate == 0.0)
		#expect(result.packetSuccessRate == 0.0)
		#expect(result.packetFailureRate == 0.0)
	}

	// MARK: - DiscoveredNodeEntity

	@Test func discoveredNodeDefaultValues() {
		let node = DiscoveredNodeEntity()
		#expect(node.nodeNum == 0)
		#expect(node.shortName == "")
		#expect(node.longName == "")
		#expect(node.neighborType == "mesh")
		#expect(node.latitude == 0.0)
		#expect(node.longitude == 0.0)
		#expect(node.distanceFromUser == 0.0)
		#expect(node.hopCount == 0)
		#expect(node.snr == 0.0)
		#expect(node.rssi == 0)
		#expect(node.messageCount == 0)
		#expect(node.sensorPacketCount == 0)
		#expect(node.presetName == "")
	}

	@Test func discoveredNodeIconNameChat() {
		let node = DiscoveredNodeEntity()
		node.messageCount = 5
		node.sensorPacketCount = 2
		#expect(node.iconName == "person.2.fill")
	}

	@Test func discoveredNodeIconNameSensor() {
		let node = DiscoveredNodeEntity()
		node.messageCount = 1
		node.sensorPacketCount = 5
		#expect(node.iconName == "thermometer.medium")
	}

	@Test func discoveredNodeIconNameEqual() {
		let node = DiscoveredNodeEntity()
		node.messageCount = 3
		node.sensorPacketCount = 3
		// When equal, messageCount >= sensorPacketCount, so chat icon
		#expect(node.iconName == "person.2.fill")
	}

	// MARK: - Completion Status Values

	@Test func validCompletionStatuses() {
		let session = DiscoverySessionEntity()
		let validStatuses = ["inProgress", "complete", "stopped", "interrupted"]
		for status in validStatuses {
			session.completionStatus = status
			#expect(session.completionStatus == status)
		}
	}

	// MARK: - Neighbor Types

	@Test func validNeighborTypes() {
		let node = DiscoveredNodeEntity()
		node.neighborType = "direct"
		#expect(node.neighborType == "direct")
		node.neighborType = "mesh"
		#expect(node.neighborType == "mesh")
	}
}
