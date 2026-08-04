// MultiRadioStoreIsolationTests.swift
// MeshtasticTests
//
// Production radio-schema persistence spike for one physical store per local radio.

import Foundation
import SwiftData
import Testing
@testable import Meshtastic

@Suite("Multi-radio store isolation", .serialized)
struct MultiRadioStoreIsolationTests {

	private static let collisionNodeNum: Int64 = 0x1234
	private static let collisionMessageId: Int64 = 0x5678

	@Test("radio schema isolates graphs across switch and reopen")
	@MainActor
	func radioSchemaIsolatesGraphsAcrossSwitchAndReopen() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let storeAURL = directory.appendingPathComponent("radio-a.store")
		let storeBURL = directory.appendingPathComponent("radio-b.store")

		do {
			let containerA = try makeContainer(at: storeAURL)
			let containerB = try makeContainer(at: storeBURL)
			try seedRadioStore(containerA, marker: "A", localNodeNum: 1001)
			try seedRadioStore(containerB, marker: "B", localNodeNum: 2002)

			try expectMarker("A", in: containerA)
			try expectMarker("B", in: containerB)

			// Selecting B does not redirect an already-issued A context. This is useful store
			// affinity, but it also demonstrates why production switching needs a generation guard.
			let oldAContext = containerA.mainContext
			let lateMessage = MessageEntity()
			lateMessage.messageId = Self.collisionMessageId + 1
			lateMessage.messagePayload = "late-A"
			oldAContext.insert(lateMessage)
			try oldAContext.save()

			let lateId = Self.collisionMessageId + 1
			let lateInB = try containerB.mainContext.fetch(
				FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == lateId })
			)
			#expect(lateInB.isEmpty)
		}

		do {
			let reopenedA = try makeContainer(at: storeAURL)
			let reopenedB = try makeContainer(at: storeBURL)
			try expectMarker("A", in: reopenedA)
			try expectMarker("B", in: reopenedB)

			let lateId = Self.collisionMessageId + 1
			let lateInA = try reopenedA.mainContext.fetch(
				FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == lateId })
			)
			#expect(lateInA.first?.messagePayload == "late-A")
		}
	}

	@Test("deleting one radio store leaves the other usable")
	@MainActor
	func deletingOneStoreLeavesTheOtherUsable() throws {
		let directory = try makeTemporaryDirectory()
		defer { try? FileManager.default.removeItem(at: directory) }

		let storeAURL = directory.appendingPathComponent("radio-a.store")
		let storeBURL = directory.appendingPathComponent("radio-b.store")

		do {
			let containerA = try makeContainer(at: storeAURL)
			let containerB = try makeContainer(at: storeBURL)
			try seedRadioStore(containerA, marker: "A", localNodeNum: 1001)
			try seedRadioStore(containerB, marker: "B", localNodeNum: 2002)
		}

		removeStoreFiles(at: storeAURL)

		let reopenedB = try makeContainer(at: storeBURL)
		try expectMarker("B", in: reopenedB)

		let additionalNode = NodeInfoEntity()
		additionalNode.num = Self.collisionNodeNum + 1
		reopenedB.mainContext.insert(additionalNode)
		try reopenedB.mainContext.save()

		let additionalNum = Self.collisionNodeNum + 1
		let saved = try reopenedB.mainContext.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == additionalNum })
		)
		#expect(saved.count == 1)
	}

	@MainActor
	private func makeContainer(at url: URL) throws -> ModelContainer {
		let schema = MultiRadioStoreSchema.radioSchema
		let configuration = ModelConfiguration(url: url, allowsSave: true)
		let container = try ModelContainer(
			for: schema,
			configurations: configuration
		)
		container.mainContext.autosaveEnabled = false
		return container
	}

	private func makeTemporaryDirectory() throws -> URL {
		let directory = FileManager.default.temporaryDirectory
			.appendingPathComponent("MultiRadioStoreIsolationTests-\(UUID().uuidString)", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return directory
	}

	private func removeStoreFiles(at storeURL: URL) {
		for suffix in ["", "-shm", "-wal"] {
			try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
		}
	}

	@MainActor
	private func expectMarker(_ marker: String, in container: ModelContainer) throws {
		let context = container.mainContext
		let nodeNum = Self.collisionNodeNum
		let messageId = Self.collisionMessageId

		let nodes = try context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })
		)
		let messages = try context.fetch(
			FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.messageId == messageId })
		)
		let waypoints = try context.fetch(FetchDescriptor<WaypointEntity>())
		let sessions = try context.fetch(FetchDescriptor<DiscoverySessionEntity>())
		let links = try context.fetch(FetchDescriptor<DeviceLinkEntity>())

		#expect(nodes.count == 1)
		#expect(nodes.first?.user?.longName == "User-\(marker)")
		#expect(nodes.first?.myInfo?.channels.first?.name == "Channel-\(marker)")
		#expect(nodes.first?.positions.first?.latitudeI == (marker == "A" ? 1 : 2))
		#expect(nodes.first?.loRaConfig?.modemPreset == (marker == "A" ? 1 : 2))
		#expect(messages.count == 1)
		#expect(messages.first?.messagePayload == "Message-\(marker)")
		#expect(waypoints.first?.name == "Waypoint-\(marker)")
		#expect(sessions.first?.homePreset == "Preset-\(marker)")
		#expect(links.first?.shortCode == "link-\(marker)")
	}

	@MainActor
	private func seedRadioStore(
		_ container: ModelContainer,
		marker: String,
		localNodeNum: Int64
	) throws {
		// Keep this explicit and pinned to the production radio schema. Adding or removing a model
		// must update this seed so schema drift cannot silently weaken the isolation test.
		#expect(MultiRadioStoreSchema.radioModels.count == 49)

		let context = container.mainContext
		let markerValue: Int32 = marker == "A" ? 1 : 2

		let node = NodeInfoEntity()
		node.num = Self.collisionNodeNum
		let user = UserEntity()
		user.num = Self.collisionNodeNum
		user.longName = "User-\(marker)"
		let myInfo = MyInfoEntity()
		myInfo.myNodeNum = localNodeNum
		myInfo.deviceId = Data("Device-\(marker)".utf8)
		let message = MessageEntity()
		message.messageId = Self.collisionMessageId
		message.messagePayload = "Message-\(marker)"
		let channel = ChannelEntity()
		channel.name = "Channel-\(marker)"
		let position = PositionEntity()
		position.latitudeI = markerValue
		let waypoint = WaypointEntity()
		waypoint.id = 99
		waypoint.name = "Waypoint-\(marker)"
		let metadata = DeviceMetadataEntity()
		let telemetry = TelemetryEntity()
		let pax = PaxCounterEntity()
		let traceRoute = TraceRouteEntity()
		let traceHop = TraceRouteHopEntity()
		let tracePosition = TraceRouteNodePositionEntity()

		let hardware = DeviceHardwareEntity()
		hardware.key = "hardware-\(marker)"
		let hardwareImage = DeviceHardwareImageEntity()
		let hardwareTag = DeviceHardwareTagEntity()
		hardwareTag.tag = "tag-\(marker)"
		let deviceLink = DeviceLinkEntity()
		deviceLink.shortCode = "link-\(marker)"
		let firmwareRelease = FirmwareReleaseEntity()
		let eventFirmware = EventFirmwareEntity()
		eventFirmware.edition = "edition-\(marker)"

		let ambientLighting = AmbientLightingConfigEntity()
		let audio = AudioConfigEntity()
		let bluetooth = BluetoothConfigEntity()
		let cannedMessage = CannedMessageConfigEntity()
		let detectionSensor = DetectionSensorConfigEntity()
		let deviceConfig = DeviceConfigEntity()
		let display = DisplayConfigEntity()
		let externalNotification = ExternalNotificationConfigEntity()
		let loRa = LoRaConfigEntity()
		loRa.modemPreset = markerValue
		let meshBeacon = MeshBeaconConfigEntity()
		let broadcastTarget = BroadcastTargetEntity()
		let mqtt = MQTTConfigEntity()
		let neighborInfo = NeighborInfoConfigEntity()
		let network = NetworkConfigEntity()
		let paxCounterConfig = PaxCounterConfigEntity()
		let positionConfig = PositionConfigEntity()
		let power = PowerConfigEntity()
		let rangeTest = RangeTestConfigEntity()
		let rtttl = RTTTLConfigEntity()
		let security = SecurityConfigEntity()
		let serial = SerialConfigEntity()
		let statusMessage = StatusMessageConfigEntity()
		let storeForward = StoreForwardConfigEntity()
		let tak = TAKConfigEntity()
		let trafficManagement = TrafficManagementConfigEntity()
		let telemetryConfig = TelemetryConfigEntity()

		let discoverySession = DiscoverySessionEntity()
		discoverySession.homePreset = "Preset-\(marker)"
		let presetResult = DiscoveryPresetResultEntity()
		presetResult.presetName = "Preset-\(marker)"
		let discoveredNode = DiscoveredNodeEntity()
		discoveredNode.nodeNum = Self.collisionNodeNum
		let discoveredBeacon = DiscoveredBeaconEntity()
		discoveredBeacon.nodeNum = Self.collisionNodeNum

		context.insert(node)
		context.insert(user)
		context.insert(myInfo)
		context.insert(message)
		context.insert(channel)
		context.insert(position)
		context.insert(waypoint)
		context.insert(metadata)
		context.insert(telemetry)
		context.insert(pax)
		context.insert(traceRoute)
		context.insert(traceHop)
		context.insert(tracePosition)
		context.insert(hardware)
		context.insert(hardwareImage)
		context.insert(hardwareTag)
		context.insert(deviceLink)
		context.insert(firmwareRelease)
		context.insert(eventFirmware)
		context.insert(ambientLighting)
		context.insert(audio)
		context.insert(bluetooth)
		context.insert(cannedMessage)
		context.insert(detectionSensor)
		context.insert(deviceConfig)
		context.insert(display)
		context.insert(externalNotification)
		context.insert(loRa)
		context.insert(meshBeacon)
		context.insert(broadcastTarget)
		context.insert(mqtt)
		context.insert(neighborInfo)
		context.insert(network)
		context.insert(paxCounterConfig)
		context.insert(positionConfig)
		context.insert(power)
		context.insert(rangeTest)
		context.insert(rtttl)
		context.insert(security)
		context.insert(serial)
		context.insert(statusMessage)
		context.insert(storeForward)
		context.insert(tak)
		context.insert(trafficManagement)
		context.insert(telemetryConfig)
		context.insert(discoverySession)
		context.insert(presetResult)
		context.insert(discoveredNode)
		context.insert(discoveredBeacon)

		node.user = user
		node.myInfo = myInfo
		myInfo.channels.append(channel)
		node.positions.append(position)
		message.fromUser = user
		message.toUser = user
		node.metadata = metadata
		node.telemetries.append(telemetry)
		node.pax.append(pax)
		node.traceRoutes.append(traceRoute)
		traceRoute.hops.append(traceHop)
		traceRoute.nodePositions.append(tracePosition)
		hardware.images.append(hardwareImage)
		hardware.tags.append(hardwareTag)
		node.ambientLightingConfig = ambientLighting
		node.audioConfig = audio
		node.bluetoothConfig = bluetooth
		node.cannedMessageConfig = cannedMessage
		node.detectionSensorConfig = detectionSensor
		node.deviceConfig = deviceConfig
		node.displayConfig = display
		node.externalNotificationConfig = externalNotification
		node.loRaConfig = loRa
		node.meshBeaconConfig = meshBeacon
		meshBeacon.broadcastTargets.append(broadcastTarget)
		node.mqttConfig = mqtt
		node.neighborInfoConfig = neighborInfo
		node.networkConfig = network
		node.paxCounterConfig = paxCounterConfig
		node.positionConfig = positionConfig
		node.powerConfig = power
		node.rangeTestConfig = rangeTest
		node.rtttlConfig = rtttl
		node.securityConfig = security
		node.serialConfig = serial
		node.statusMessageConfig = statusMessage
		node.storeForwardConfig = storeForward
		node.takConfig = tak
		node.trafficManagementConfig = trafficManagement
		node.telemetryConfig = telemetryConfig
		discoverySession.presetResults.append(presetResult)
		discoverySession.discoveredNodes.append(discoveredNode)
		discoverySession.beacons.append(discoveredBeacon)
		presetResult.nodes.append(discoveredNode)
		presetResult.beacons.append(discoveredBeacon)

		try context.save()
	}
}
