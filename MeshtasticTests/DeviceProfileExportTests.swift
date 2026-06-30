//
//  DeviceProfileExportTests.swift
//  Meshtastic
//
//  Verifies the entity -> DeviceProfile converters used by the "Export Configuration" feature.
//

import Foundation
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

@Suite("DeviceProfile export converters")
struct DeviceProfileExportTests {

	// MARK: Device configs

	@Test("DeviceConfig maps fields and inverts the negated flags")
	func deviceConfig() {
		let entity = DeviceConfigEntity()
		entity.role = Int32(Config.DeviceConfig.Role.router.rawValue)
		entity.buttonGpio = 12
		entity.nodeInfoBroadcastSecs = 3600
		entity.tripleClickAsAdHocPing = false   // -> disableTripleClick == true
		entity.ledHeartbeatEnabled = false       // -> ledHeartbeatDisabled == true
		entity.isManaged = true
		entity.tzdef = "PST8PDT"

		let proto = entity.protoConfig
		#expect(proto.role == .router)
		#expect(proto.buttonGpio == 12)
		#expect(proto.nodeInfoBroadcastSecs == 3600)
		#expect(proto.disableTripleClick == true)
		#expect(proto.ledHeartbeatDisabled == true)
		#expect(proto.isManaged == true)
		#expect(proto.tzdef == "PST8PDT")
	}

	@Test("LoRaConfig maps enums and the renamed okToMqtt field")
	func loraConfig() {
		let entity = LoRaConfigEntity()
		entity.regionCode = Int32(Config.LoRaConfig.RegionCode.us.rawValue)
		entity.modemPreset = Int32(Config.LoRaConfig.ModemPreset.longFast.rawValue)
		entity.usePreset = true
		entity.hopLimit = 5
		entity.txPower = 30
		entity.channelNum = 20
		entity.okToMqtt = true   // -> configOkToMqtt

		let proto = entity.protoConfig
		#expect(proto.region == .us)
		#expect(proto.modemPreset == .longFast)
		#expect(proto.usePreset == true)
		#expect(proto.hopLimit == 5)
		#expect(proto.txPower == 30)
		#expect(proto.channelNum == 20)
		#expect(proto.configOkToMqtt == true)
	}

	@Test("SecurityConfig preserves admin-key slots and trims trailing empties")
	func securityConfig() {
		let entity = SecurityConfigEntity()
		entity.publicKey = Data([1, 2, 3])
		entity.privateKey = Data([4, 5, 6])
		entity.adminKey = Data([7])
		entity.adminKey2 = Data()       // empty middle slot must be preserved for index alignment
		entity.adminKey3 = Data([8, 9])
		entity.isManaged = true

		let proto = entity.protoConfig
		#expect(proto.publicKey == Data([1, 2, 3]))
		#expect(proto.privateKey == Data([4, 5, 6]))
		#expect(proto.adminKey == [Data([7]), Data(), Data([8, 9])])
		#expect(proto.isManaged == true)
	}

	@Test("SecurityConfig keeps a populated second slot aligned when the first is empty")
	func securityConfigLeadingEmptyAdminKey() {
		let entity = SecurityConfigEntity()
		entity.adminKey = Data()          // empty first slot
		entity.adminKey2 = Data([0xAB])   // must remain at index 1, not collapse to index 0

		let proto = entity.protoConfig
		#expect(proto.adminKey == [Data(), Data([0xAB])])
	}

	@Test("SecurityConfig trims trailing empty admin-key slots")
	func securityConfigTrailingEmptyAdminKeys() {
		let entity = SecurityConfigEntity()
		entity.adminKey = Data([0x01])
		// adminKey2 / adminKey3 left nil -> no trailing entries emitted

		let proto = entity.protoConfig
		#expect(proto.adminKey == [Data([0x01])])
	}

	@Test("NetworkConfig restores the packed IPv4 values via bit pattern")
	func networkConfig() {
		let entity = NetworkConfigEntity()
		entity.wifiEnabled = true
		entity.wifiSsid = "mesh"
		entity.ip = Int32(bitPattern: 0xC0A8_0101) // 192.168.1.1

		let proto = entity.protoConfig
		#expect(proto.wifiEnabled == true)
		#expect(proto.wifiSsid == "mesh")
		#expect(proto.ipv4Config.ip == 0xC0A8_0101)
	}

	// MARK: Module configs

	@Test("TelemetryConfig round-trips its intervals and toggles")
	func telemetryConfig() {
		let entity = TelemetryConfigEntity()
		entity.deviceUpdateInterval = 900
		entity.deviceTelemetryEnabled = true
		entity.environmentMeasurementEnabled = true
		entity.environmentUpdateInterval = 1800

		let proto = entity.protoConfig
		#expect(proto.deviceUpdateInterval == 900)
		#expect(proto.deviceTelemetryEnabled == true)
		#expect(proto.environmentMeasurementEnabled == true)
		#expect(proto.environmentUpdateInterval == 1800)
	}

	@Test("MQTTConfig maps the nested map report settings")
	func mqttConfig() {
		let entity = MQTTConfigEntity()
		entity.enabled = true
		entity.address = "mqtt.example.com"
		entity.mapReportingEnabled = true
		entity.mapReportingShouldReportLocation = true
		entity.mapPositionPrecision = 14
		entity.mapPublishIntervalSecs = 60

		let proto = entity.protoConfig
		#expect(proto.enabled == true)
		#expect(proto.address == "mqtt.example.com")
		#expect(proto.mapReportingEnabled == true)
		#expect(proto.mapReportSettings.shouldReportLocation == true)
		#expect(proto.mapReportSettings.positionPrecision == 14)
		#expect(proto.mapReportSettings.publishIntervalSecs == 60)
	}

	@Test("StoreForwardConfig exports the server role via isServer")
	func storeForwardConfig() {
		let entity = StoreForwardConfigEntity()
		entity.enabled = true
		entity.isRouter = true   // -> isServer
		entity.records = 100

		let proto = entity.protoConfig
		#expect(proto.enabled == true)
		#expect(proto.isServer == true)
		#expect(proto.records == 100)
	}

	@Test("TAKConfig maps the role and team enums")
	func takConfig() {
		let entity = TAKConfigEntity()
		entity.role = Int32(MemberRole.teamMember.rawValue)
		entity.team = Int32(Team.cyan.rawValue)

		let proto = entity.protoConfig
		#expect(proto.role == .teamMember)
		#expect(proto.team == .cyan)
	}

	@Test("TrafficManagementConfig exports its uint32 limits")
	func trafficManagementConfig() {
		let entity = TrafficManagementConfigEntity()
		entity.positionMinIntervalSecs = 30
		entity.nodeinfoDirectResponseMaxHops = 2
		entity.rateLimitWindowSecs = 60
		entity.rateLimitMaxPackets = 42
		entity.unknownPacketThreshold = 5

		let proto = entity.protoConfig
		#expect(proto.positionMinIntervalSecs == 30)
		#expect(proto.nodeinfoDirectResponseMaxHops == 2)
		#expect(proto.rateLimitWindowSecs == 60)
		#expect(proto.rateLimitMaxPackets == 42)
		#expect(proto.unknownPacketThreshold == 5)
	}

	@Test("StatusMessageConfig maps the node status text")
	func statusMessageConfig() {
		let entity = StatusMessageConfigEntity()
		entity.nodeStatus = "Camping until Sunday"

		let proto = entity.protoConfig
		#expect(proto.nodeStatus == "Camping until Sunday")
	}

	// MARK: Assembly

	@Test("exportDeviceProfile includes set configs, names, and omits missing ones")
	func assemblyIncludesSetConfigsOnly() throws {
		let node = NodeInfoEntity()
		node.num = 123456789

		let user = UserEntity()
		user.longName = "Test Node"
		user.shortName = "TN"
		node.user = user

		let lora = LoRaConfigEntity()
		lora.regionCode = Int32(Config.LoRaConfig.RegionCode.us.rawValue)
		node.loRaConfig = lora

		let telemetry = TelemetryConfigEntity()
		telemetry.deviceTelemetryEnabled = true
		node.telemetryConfig = telemetry

		let profile = node.exportDeviceProfile()
		#expect(profile.longName == "Test Node")
		#expect(profile.shortName == "TN")
		#expect(profile.config.lora.region == .us)
		#expect(profile.moduleConfig.telemetry.deviceTelemetryEnabled == true)

		// A profile with configs set must round-trip through binary serialization.
		let data = try profile.serializedData()
		#expect(!data.isEmpty)
		let decoded = try DeviceProfile(serializedBytes: data)
		#expect(decoded.longName == "Test Node")
		#expect(decoded.config.lora.region == .us)
	}

	@Test("exportDeviceProfile includes the TAK, traffic, and status module configs")
	func assemblyIncludesPreviouslyMissedModules() {
		let node = NodeInfoEntity()
		node.num = 1

		let tak = TAKConfigEntity()
		tak.role = Int32(MemberRole.teamMember.rawValue)
		node.takConfig = tak

		let traffic = TrafficManagementConfigEntity()
		traffic.rateLimitMaxPackets = 7
		node.trafficManagementConfig = traffic

		let status = StatusMessageConfigEntity()
		status.nodeStatus = "QRT"
		node.statusMessageConfig = status

		let profile = node.exportDeviceProfile()
		#expect(profile.moduleConfig.tak.role == .teamMember)
		#expect(profile.moduleConfig.trafficManagement.rateLimitMaxPackets == 7)
		#expect(profile.moduleConfig.statusmessage.nodeStatus == "QRT")
	}

	@Test("exportDeviceProfile carries ringtone and canned messages")
	func assemblyRingtoneAndCannedMessages() {
		let node = NodeInfoEntity()
		node.num = 1

		let rtttl = RTTTLConfigEntity()
		rtttl.ringtone = "Beep:d=4,o=5,b=120:c"
		node.rtttlConfig = rtttl

		let canned = CannedMessageConfigEntity()
		canned.messages = "Yes|No|On my way"
		node.cannedMessageConfig = canned

		let profile = node.exportDeviceProfile()
		#expect(profile.ringtone == "Beep:d=4,o=5,b=120:c")
		#expect(profile.cannedMessages == "Yes|No|On my way")
	}

	@Test("exportChannelURL is embedded when channels exist")
	func assemblyChannelURL() {
		let node = NodeInfoEntity()
		node.num = 1

		let lora = LoRaConfigEntity()
		lora.regionCode = Int32(Config.LoRaConfig.RegionCode.us.rawValue)
		node.loRaConfig = lora

		let myInfo = MyInfoEntity()
		let channel = ChannelEntity()
		channel.index = 0
		channel.role = 1 // primary
		channel.name = "Primary"
		channel.psk = Data([0x01])
		myInfo.channels = [channel]
		node.myInfo = myInfo

		let profile = node.exportDeviceProfile()
		#expect(profile.channelURL.hasPrefix("https://meshtastic.org/e/#"))
	}
}
