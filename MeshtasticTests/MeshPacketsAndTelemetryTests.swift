// MeshPacketsAndTelemetryTests.swift
// MeshtasticTests

import Testing
import Foundation
import SwiftUI
import SwiftData
import MeshtasticProtobufs
@testable import Meshtastic

// MARK: - generateMessageMarkdown Tests

@Suite("generateMessageMarkdown")
struct GenerateMessageMarkdownTests {

	@Test func plainText_returnsUnchanged() {
		let result = generateMessageMarkdown(message: "Hello World")
		#expect(result == "Hello World")
	}

	@Test func emojiOnly_returnsUnchanged() {
		let result = generateMessageMarkdown(message: "😀🎉🔥")
		#expect(result == "😀🎉🔥")
	}

	@Test func urlDetected_createsMarkdownLink() {
		let result = generateMessageMarkdown(message: "Visit https://meshtastic.org for info")
		#expect(result.contains("[https://meshtastic.org](https://meshtastic.org)"))
	}

	@Test func phoneNumber_createsTelLink() {
		let result = generateMessageMarkdown(message: "Call me at (555) 123-4567")
		#expect(result.contains("tel:"))
		#expect(result.contains("555"))
	}

	@Test func address_createsMapsLink() {
		let result = generateMessageMarkdown(message: "Meet at 1600 Pennsylvania Avenue NW, Washington, DC 20500")
		#expect(result.contains("maps.apple.com"))
	}

	@Test func emptyString_returnsEmpty() {
		let result = generateMessageMarkdown(message: "")
		#expect(result == "")
	}

	@Test func noMatches_returnsOriginal() {
		let result = generateMessageMarkdown(message: "just a plain text message")
		#expect(result == "just a plain text message")
	}

	@Test func multipleURLs_allConverted() {
		let result = generateMessageMarkdown(message: "Check https://meshtastic.org and https://github.com")
		#expect(result.contains("[https://meshtastic.org]"))
		#expect(result.contains("[https://github.com]"))
	}

	@Test func duplicateURLs_eachWrappedOnce() {
		let result = generateMessageMarkdown(message: "Link https://meshtastic.org and again https://meshtastic.org")
		let occurrences = result.components(separatedBy: "[https://meshtastic.org](https://meshtastic.org)").count - 1
		#expect(occurrences == 2)
	}

	@Test func urlWithEmoji_correctRangeHandling() {
		let result = generateMessageMarkdown(message: "🔥 https://meshtastic.org 🎉")
		#expect(result.contains("[https://meshtastic.org](https://meshtastic.org)"))
		#expect(result.contains("🔥"))
		#expect(result.contains("🎉"))
	}
}

// MARK: - MyInfo ingestion

@Suite("MyInfo ingestion", .serialized)
@MainActor
struct MyInfoIngestionTests {
	@Test func sameNodeReflash_updatesPioEnvAndBandwidthCapability() async throws {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		let mesh = MeshPackets(modelContainer: container)
		let nodeNum: UInt32 = 0x1234_5678

		var beforeReflash = MyNodeInfo()
		beforeReflash.myNodeNum = nodeNum
		beforeReflash.pioEnv = "muzi-base"
		let originalID = await mesh.myInfoPacket(myInfo: beforeReflash, peripheralId: "test-peripheral")

		var afterReflash = MyNodeInfo()
		afterReflash.myNodeNum = nodeNum
		afterReflash.pioEnv = "my-esp32s3-diy-oled"
		let updatedID = await mesh.myInfoPacket(myInfo: afterReflash, peripheralId: "test-peripheral")

		let context = ModelContext(container)
		let persistedNodeNum = Int64(nodeNum)
		let rows = try context.fetch(
			FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		)
		let myInfo = try #require(rows.first)

		#expect(rows.count == 1)
		#expect(originalID == updatedID)
		#expect(myInfo.myNodeNum == persistedNodeNum)
		#expect(myInfo.pioEnv == "my-esp32s3-diy-oled")
		#expect(Bandwidths.selectable(region: .lora24, pioEnv: myInfo.pioEnv).contains(.sixteenHundred))
	}
}

// MARK: - Automatic channel refresh staging

@Suite("Automatic channel refresh staging", .serialized)
@MainActor
struct AutomaticChannelRefreshStagingTests {
	private func freshMesh() throws -> (MeshPackets, ModelContainer) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		return (MeshPackets(modelContainer: container), container)
	}

	private func seedMyInfo(_ mesh: MeshPackets, nodeNum: UInt32) async {
		var myInfo = MyNodeInfo()
		myInfo.myNodeNum = nodeNum
		_ = await mesh.myInfoPacket(myInfo: myInfo, peripheralId: "test-peripheral")
	}

	private func channel(index: Int32, name: String, role: Channel.Role = .secondary) -> Channel {
		var channel = Channel()
		channel.index = index
		channel.role = role
		channel.settings.name = name
		channel.settings.psk = Data([UInt8(truncatingIfNeeded: index), 0xCA, 0xFE])
		channel.settings.uplinkEnabled = true
		channel.settings.downlinkEnabled = false
		channel.settings.moduleSettings.positionPrecision = 11
		channel.settings.moduleSettings.isMuted = true
		return channel
	}

	private func persistedChannels(in container: ModelContainer, nodeNum: UInt32) throws -> [(index: Int32, name: String?, psk: Data?)] {
		let persistedNodeNum = Int64(nodeNum)
		let context = ModelContext(container)
		let myInfo = try #require(context.fetch(
			FetchDescriptor<MyInfoEntity>(predicate: #Predicate { $0.myNodeNum == persistedNodeNum })
		).first)
		return myInfo.channels
			.sorted { $0.index < $1.index }
			.map { ($0.index, $0.name, $0.psk) }
	}

	@Test func activeRefreshStagePreservesPersistedChannelsBeforeCompletion() async throws {
		let (mesh, container) = try freshMesh()
		let nodeNum: UInt32 = 0x0A0B_0C0D
		await seedMyInfo(mesh, nodeNum: nodeNum)
		await mesh.channelPacket(channel: channel(index: 0, name: "Existing", role: .primary), fromNum: Int64(nodeNum))

		await mesh.beginChannelRefreshStage(for: Int64(nodeNum))
		await mesh.channelPacket(channel: channel(index: 0, name: "Staged Replacement", role: .primary), fromNum: Int64(nodeNum))
		await mesh.channelPacket(channel: channel(index: 1, name: "Staged Secondary"), fromNum: Int64(nodeNum))

		let persisted = try persistedChannels(in: container, nodeNum: nodeNum)
		#expect(persisted.map(\.index) == [0])
		#expect(persisted.first?.name == "Existing")
		await mesh.discardChannelRefreshStage(for: Int64(nodeNum))
	}

	@Test func committingRefreshStageReplacesPersistedChannelsAtomically() async throws {
		let (mesh, container) = try freshMesh()
		let nodeNum: UInt32 = 0x0102_0304
		await seedMyInfo(mesh, nodeNum: nodeNum)
		await mesh.channelPacket(channel: channel(index: 0, name: "Old Primary", role: .primary), fromNum: Int64(nodeNum))
		await mesh.channelPacket(channel: channel(index: 2, name: "Old Secondary"), fromNum: Int64(nodeNum))

		await mesh.beginChannelRefreshStage(for: Int64(nodeNum))
		await mesh.channelPacket(channel: channel(index: 1, name: "New Secondary"), fromNum: Int64(nodeNum))
		await mesh.channelPacket(channel: channel(index: 0, name: "New Primary", role: .primary), fromNum: Int64(nodeNum))
		var disabled = Channel()
		disabled.index = 2
		disabled.role = .disabled
		await mesh.channelPacket(channel: disabled, fromNum: Int64(nodeNum))
		for index in Int32(3)...Int32(7) {
			var disabled = Channel()
			disabled.index = index
			disabled.role = .disabled
			await mesh.channelPacket(channel: disabled, fromNum: Int64(nodeNum))
		}
		await mesh.commitChannelRefreshStage(for: Int64(nodeNum))

		let persisted = try persistedChannels(in: container, nodeNum: nodeNum)
		#expect(persisted.map(\.index) == [0, 1])
		#expect(persisted.map(\.name) == ["New Primary", "New Secondary"])
		#expect(persisted.map(\.psk) == [Data([0, 0xCA, 0xFE]), Data([1, 0xCA, 0xFE])])
	}

	@Test func discardingRefreshStagePreservesPersistedChannels() async throws {
		let (mesh, container) = try freshMesh()
		let nodeNum: UInt32 = 0x0D15_CAFE
		await seedMyInfo(mesh, nodeNum: nodeNum)
		await mesh.channelPacket(channel: channel(index: 0, name: "Kept Primary", role: .primary), fromNum: Int64(nodeNum))

		await mesh.beginChannelRefreshStage(for: Int64(nodeNum))
		await mesh.channelPacket(channel: channel(index: 0, name: "Discarded Primary", role: .primary), fromNum: Int64(nodeNum))
		await mesh.discardChannelRefreshStage(for: Int64(nodeNum))

		let persisted = try persistedChannels(in: container, nodeNum: nodeNum)
		#expect(persisted.map(\.index) == [0])
		#expect(persisted.first?.name == "Kept Primary")
	}
}

// MARK: - Local Message Notification Cleanup

@Suite("Local message notification cleanup")
@MainActor
struct LocalMessageNotificationCleanupTests {
	@Test func readingMessages_removesTheirDeliveredNotifications() {
		var removedIdentifiers = [String]()
		let manager = LocalNotificationManager { identifiers in
			removedIdentifiers = identifiers
		}

		manager.cancelNotificationsForMessageIds([123, 456])

		#expect(removedIdentifiers == ["notification.id.123", "notification.id.456"])
	}
}

// MARK: - TelemetryEnums Aqi

@Suite("Local stats telemetry export")
struct LocalStatsTelemetryExportTests {

	@Test func csvPreservesZeroNoiseFloor() {
		let telemetry = TelemetryEntity()
		telemetry.metricsType = 4
		telemetry.noiseFloor = 0

		let csv = telemetryToCsvFile(telemetry: [telemetry], metricsType: 4)

		#expect(csv.split(separator: "\n").last?.split(separator: ",").first?.trimmingCharacters(in: .whitespaces) == "0")
	}
}

@Suite("Local stats request transport")
struct LocalStatsRequestTransportTests {

	@Test func directlyAttachedNode_skipsTransportChoice() {
		#expect(LocalStatsRequestTransport.shouldChooseMethod(from: 0x1234, to: 0x1234) == false)
	}

	@Test func remoteNode_requiresTransportChoice() {
		#expect(LocalStatsRequestTransport.shouldChooseMethod(from: 0x1234, to: 0x5678) == true)
	}

	@Test func remoteAdmin_requiresDestinationPublicKey() {
		#expect(LocalStatsRequestTransport.remoteAdminAvailable(for: nil) == false)
		#expect(LocalStatsRequestTransport.remoteAdminAvailable(for: Data()) == false)
		#expect(LocalStatsRequestTransport.remoteAdminAvailable(for: Data(repeating: 1, count: 32)) == true)
	}

	@Test func sharedChannel_doesNotEnablePKIOnThePacket() {
		var packet = MeshPacket()

		#expect(LocalStatsRequestTransport.configure(
			&packet,
			transport: .sharedChannel,
			destinationPublicKey: nil
		))
		#expect(packet.pkiEncrypted == false)
	}

	@Test func remoteAdmin_enablesPKIWithTheDestinationKey() {
		let publicKey = Data(repeating: 2, count: 32)
		var packet = MeshPacket()

		#expect(LocalStatsRequestTransport.configure(
			&packet,
			transport: .remoteAdmin,
			destinationPublicKey: publicKey
		))
		#expect(packet.pkiEncrypted == true)
		#expect(packet.publicKey == publicKey)
	}
}

// EPA PM2.5 → AQI breakpoints and NowCast — issue #2040 / design#54 (Stage 2)
@Suite("EPA air quality math")
struct EPAAirQualityTests {

	// MARK: AQI from PM2.5 concentration (current 2024 EPA breakpoints)

	@Test func aqiBreakpointBoundaries() {
		#expect(EPAAirQuality.aqi(fromPM25: 0.0) == 0)
		#expect(EPAAirQuality.aqi(fromPM25: 9.0) == 50)     // top of Good
		#expect(EPAAirQuality.aqi(fromPM25: 9.1) == 51)     // bottom of Moderate
		#expect(EPAAirQuality.aqi(fromPM25: 35.4) == 100)   // top of Moderate
		#expect(EPAAirQuality.aqi(fromPM25: 35.5) == 101)   // bottom of USG
		#expect(EPAAirQuality.aqi(fromPM25: 55.4) == 150)
		#expect(EPAAirQuality.aqi(fromPM25: 125.4) == 200)
		#expect(EPAAirQuality.aqi(fromPM25: 225.4) == 300)
		#expect(EPAAirQuality.aqi(fromPM25: 225.5) == 301)  // bottom of Hazardous
		#expect(EPAAirQuality.aqi(fromPM25: 325.4) == 500)  // top of the app's AQI scale
	}

	@Test func aqiClampsAndTruncates() {
		#expect(EPAAirQuality.aqi(fromPM25: 400.0) == 500)  // above the table → clamp to 500
		#expect(EPAAirQuality.aqi(fromPM25: 9.05) == 50)    // truncates to 9.0, not rounded up
		#expect(EPAAirQuality.aqi(fromPM25: -1.0) == nil)   // invalid
	}

	// MARK: NowCast

	@Test func nowCastConstantSeriesEqualsValue() {
		let hourly: [Double?] = Array(repeating: 10.0, count: 12)
		#expect(EPAAirQuality.nowCastPM25(hourly: hourly) == 10.0)
	}

	@Test func nowCastRequiresTwoOfThreeRecentHours() {
		// Only the most recent hour present → insufficient.
		let insufficient: [Double?] = [10.0, nil, nil, 10.0, 10.0, 10.0]
		#expect(EPAAirQuality.nowCastPM25(hourly: insufficient) == nil)
		// Two of the three most recent hours present → computes.
		let sufficient: [Double?] = [10.0, nil, 10.0]
		#expect(EPAAirQuality.nowCastPM25(hourly: sufficient) == 10.0)
	}

	@Test func nowCastWeightsRecentHoursMoreHeavily() {
		// cMin/cMax = 1/100 < 0.5, so the weight factor floors at 0.5.
		// NowCast = (0.5^0·1 + 0.5^1·100) / (1 + 0.5) = 51 / 1.5 = 34.
		let hourly: [Double?] = [1.0, 100.0]
		let nowCast = EPAAirQuality.nowCastPM25(hourly: hourly)
		#expect(nowCast != nil)
		#expect(abs((nowCast ?? 0) - 34.0) < 0.0001)
	}

	@Test func nowCastAQIFromTimestampedReadings() {
		let calendar = Calendar.current
		let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 12, minute: 30)) ?? Date()
		let readings: [(date: Date, pm25: Double)] = [
			(now, 10.0),
			(calendar.date(byAdding: .hour, value: -1, to: now) ?? now, 10.0),
			(calendar.date(byAdding: .hour, value: -2, to: now) ?? now, 10.0)
		]
		// NowCast of a constant 10 µg/m³ → 10.0 → AQI 53 (Moderate).
		#expect(EPAAirQuality.nowCastAQI(from: readings, now: now, calendar: calendar) == 53)
	}

	@Test func nowCastAQIReturnsNilWithoutEnoughHistory() {
		let calendar = Calendar.current
		let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 12, minute: 30)) ?? Date()
		// A single reading is not enough (needs 2 of the 3 most recent hours).
		#expect(EPAAirQuality.nowCastAQI(from: [(now, 42.0)], now: now, calendar: calendar) == nil)
	}

	@Test func nowCastAllZeroReadingsIsZero() {
		// All-zero series: max is 0, so the weight can't be derived — NowCast short-circuits to 0.
		let hourly: [Double?] = [0.0, 0.0, 0.0]
		#expect(EPAAirQuality.nowCastPM25(hourly: hourly) == 0.0)
		#expect(EPAAirQuality.aqi(fromPM25: 0.0) == 0)
	}

	@Test func nowCastAQIExcludesReadingsOutsideTwelveHourWindow() {
		let calendar = Calendar.current
		let now = calendar.date(from: DateComponents(year: 2025, month: 6, day: 1, hour: 12, minute: 30)) ?? Date()
		// Two recent hours plus one stale reading 20h ago that must be ignored.
		let readings: [(date: Date, pm25: Double)] = [
			(now, 10.0),
			(calendar.date(byAdding: .hour, value: -1, to: now) ?? now, 10.0),
			(calendar.date(byAdding: .hour, value: -20, to: now) ?? now, 999.0)
		]
		// The 999 reading is outside the 12h window; NowCast of the constant 10 → AQI 53.
		#expect(EPAAirQuality.nowCastAQI(from: readings, now: now, calendar: calendar) == 53)
	}
}

// Air Quality (particulate matter) telemetry — issue #2040
@Suite("Air quality telemetry export")
struct AirQualityTelemetryExportTests {

	@Test func csvExportsParticulateMatterValues() {
		let telemetry = TelemetryEntity()
		telemetry.metricsType = 3
		telemetry.pm10Standard = 1
		telemetry.pm25Standard = 2
		telemetry.pm100Standard = 3
		telemetry.pm10Environmental = 4
		telemetry.pm25Environmental = 5
		telemetry.pm100Environmental = 6

		let csv = telemetryToCsvFile(telemetry: [telemetry], metricsType: 3)
		let lines = csv.split(separator: "\n")

		// Header names the six PM columns
		#expect(lines.first?.contains("PM2.5 Std") == true)
		#expect(lines.first?.contains("PM10 Env") == true)

		// Values are written in field order (PM1.0, PM2.5, PM10 std; then env)
		let values = lines.last?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
		#expect(values.map { Array($0.prefix(6)) } == ["1", "2", "3", "4", "5", "6"])
	}

	@Test func csvLeavesMissingParticulateMatterFieldsBlank() {
		let telemetry = TelemetryEntity()
		telemetry.metricsType = 3
		telemetry.pm25Standard = 12
		// All other PM fields left nil

		let csv = telemetryToCsvFile(telemetry: [telemetry], metricsType: 3)
		let values = csv.split(separator: "\n").last?.split(separator: ",", omittingEmptySubsequences: false)
			.map { $0.trimmingCharacters(in: .whitespaces) }

		// Row = 6 PM columns + timestamp. pm25Standard is the 2nd field; every other PM column is blank.
		#expect(values?.count == 7)
		#expect(values?[1] == "12")
		#expect(values?[0] == "")
		#expect(values?[2] == "")
		#expect(values?[3] == "")
		#expect(values?[4] == "")
		#expect(values?[5] == "")
	}
}

@Suite("Aqi getAqi boundary values")
struct AqiGetAqiBoundaryTests {

	@Test func getAqi_good_low() {
		#expect(Aqi.getAqi(for: 0) == .good)
	}

	@Test func getAqi_good_high() {
		#expect(Aqi.getAqi(for: 50) == .good)
	}

	@Test func getAqi_moderate_low() {
		#expect(Aqi.getAqi(for: 51) == .moderate)
	}

	@Test func getAqi_moderate_high() {
		#expect(Aqi.getAqi(for: 100) == .moderate)
	}

	@Test func getAqi_sensitive_low() {
		#expect(Aqi.getAqi(for: 101) == .sensitive)
	}

	@Test func getAqi_sensitive_high() {
		#expect(Aqi.getAqi(for: 150) == .sensitive)
	}

	@Test func getAqi_unhealthy_low() {
		#expect(Aqi.getAqi(for: 151) == .unhealthy)
	}

	@Test func getAqi_unhealthy_high() {
		#expect(Aqi.getAqi(for: 200) == .unhealthy)
	}

	@Test func getAqi_veryUnhealthy_low() {
		#expect(Aqi.getAqi(for: 201) == .veryUnhealthy)
	}

	@Test func getAqi_veryUnhealthy_high() {
		#expect(Aqi.getAqi(for: 300) == .veryUnhealthy)
	}

	@Test func getAqi_hazardous_low() {
		#expect(Aqi.getAqi(for: 301) == .hazardous)
	}

	@Test func getAqi_hazardous_high() {
		#expect(Aqi.getAqi(for: 500) == .hazardous)
	}
}

@Suite("Aqi range property")
struct AqiRangePropertyTests {

	@Test func allCases_haveValidRanges() {
		for aqi in Aqi.allCases {
			let range = aqi.range
			#expect(!range.isEmpty)
		}
	}

	@Test func good_range() {
		#expect(Aqi.good.range.contains(25))
		#expect(!Aqi.good.range.contains(51))
	}

	@Test func hazardous_range() {
		#expect(Aqi.hazardous.range.contains(400))
		#expect(!Aqi.hazardous.range.contains(200))
	}
}

@Suite("Aqi color property")
struct AqiColorPropertyTests {

	@Test func allCases_haveColors() {
		for aqi in Aqi.allCases {
			_ = aqi.color // should not crash
		}
	}
}

// MARK: - TelemetryEnums Iaq

@Suite("Iaq getIaq boundary values")
struct IaqGetIaqBoundaryTests {

	@Test func getIaq_excellent_low() {
		#expect(Iaq.getIaq(for: 0) == .excellent)
	}

	@Test func getIaq_excellent_high() {
		#expect(Iaq.getIaq(for: 50) == .excellent)
	}

	@Test func getIaq_good_low() {
		#expect(Iaq.getIaq(for: 51) == .good)
	}

	@Test func getIaq_good_high() {
		#expect(Iaq.getIaq(for: 100) == .good)
	}

	@Test func getIaq_lightlyPolluted() {
		#expect(Iaq.getIaq(for: 125) == .lightlyPolluted)
	}

	@Test func getIaq_moderatelyPolluted() {
		#expect(Iaq.getIaq(for: 175) == .moderatelyPolluted)
	}

	@Test func getIaq_heavilyPolluted() {
		#expect(Iaq.getIaq(for: 225) == .heavilyPolluted)
	}

	@Test func getIaq_severelyPolluted() {
		#expect(Iaq.getIaq(for: 300) == .severelyPolluted)
	}

	@Test func getIaq_extremelyPolluted_low() {
		#expect(Iaq.getIaq(for: 351) == .extremelyPolluted)
	}

	@Test func getIaq_extremelyPolluted_high() {
		#expect(Iaq.getIaq(for: 999) == .extremelyPolluted)
	}
}

@Suite("Iaq range property")
struct IaqRangePropertyTests {

	@Test func allCases_haveValidRanges() {
		for iaq in Iaq.allCases {
			let range = iaq.range
			#expect(!range.isEmpty)
		}
	}

	@Test func excellent_range() {
		#expect(Iaq.excellent.range.contains(25))
		#expect(!Iaq.excellent.range.contains(51))
	}
}

@Suite("Iaq color property")
struct IaqColorPropertyTests {

	@Test func allCases_haveColors() {
		for iaq in Iaq.allCases {
			_ = iaq.color
		}
	}
}

@Suite("Iaq description property")
struct IaqDescriptionPropertyTests {

	@Test func allCases_haveDescriptions() {
		for iaq in Iaq.allCases {
			#expect(!iaq.description.isEmpty)
		}
	}

	@Test func specificDescriptions() {
		#expect(Iaq.excellent.description == "Excellent")
		#expect(Iaq.extremelyPolluted.description == "Extremely Polluted")
	}
}

// MARK: - MetricsTypes name

@Suite("MetricsTypes name property")
struct MetricsTypesNameExtendedTests {

	@Test func allCases_haveNames() {
		for mt in MetricsTypes.allCases {
			#expect(!mt.name.isEmpty)
		}
	}

	@Test func specificNames() {
		#expect(MetricsTypes.device.name == "Device Metrics")
		#expect(MetricsTypes.environment.name == "Environment Metrics")
		#expect(MetricsTypes.power.name == "Power Metrics")
		#expect(MetricsTypes.airQuality.name == "Air Quality Metrics")
		#expect(MetricsTypes.stats.name == "Stats")
	}
}

// MARK: - NymeaWifiNetwork signalBars

@Suite("NymeaWifiNetwork signalBars")
struct NymeaWifiNetworkSignalBarsTests {

	private func makeNetwork(signal: Int) throws -> NymeaWifiNetwork {
		let json = """
		{"e":"TestSSID","m":"AA:BB:CC:DD:EE:FF","s":\(signal),"p":1}
		"""
		return try JSONDecoder().decode(NymeaWifiNetwork.self, from: json.data(using: .utf8)!)
	}

	@Test func signalBars_highSignal() throws {
		let net = try makeNetwork(signal: 80)
		#expect(net.signalBars == 4)
	}

	@Test func signalBars_boundary76() throws {
		let net = try makeNetwork(signal: 76)
		#expect(net.signalBars == 4)
	}

	@Test func signalBars_boundary75() throws {
		let net = try makeNetwork(signal: 75)
		#expect(net.signalBars == 3)
	}

	@Test func signalBars_boundary51() throws {
		let net = try makeNetwork(signal: 51)
		#expect(net.signalBars == 3)
	}

	@Test func signalBars_boundary50() throws {
		let net = try makeNetwork(signal: 50)
		#expect(net.signalBars == 2)
	}

	@Test func signalBars_boundary26() throws {
		let net = try makeNetwork(signal: 26)
		#expect(net.signalBars == 2)
	}

	@Test func signalBars_boundary25() throws {
		let net = try makeNetwork(signal: 25)
		#expect(net.signalBars == 1)
	}

	@Test func signalBars_boundary1() throws {
		let net = try makeNetwork(signal: 1)
		#expect(net.signalBars == 1)
	}

	@Test func signalBars_zero() throws {
		let net = try makeNetwork(signal: 0)
		#expect(net.signalBars == 0)
	}

	@Test func signalBars_negative() throws {
		let net = try makeNetwork(signal: -10)
		#expect(net.signalBars == 0)
	}

	@Test func isProtected_fromInt() throws {
		let openJson = """
		{"e":"Open","m":"11:22:33:44:55:66","s":50,"p":0}
		"""
		let openNet = try JSONDecoder().decode(NymeaWifiNetwork.self, from: openJson.data(using: .utf8)!)
		#expect(openNet.isProtected == false)

		let protectedJson = """
		{"e":"Secured","m":"AA:BB:CC:DD:EE:FF","s":50,"p":1}
		"""
		let protectedNet = try JSONDecoder().decode(NymeaWifiNetwork.self, from: protectedJson.data(using: .utf8)!)
		#expect(protectedNet.isProtected == true)
	}

	@Test func hashable_sameNetwork() throws {
		let net1 = try makeNetwork(signal: 50)
		let net2 = try makeNetwork(signal: 50)
		#expect(net1 == net2)
	}
}

// MARK: - NymeaCommandPacket encoding

@Suite("NymeaCommandPacket encoding extended")
struct NymeaCommandPacketEncodingExtendedTests {

	@Test func encodeWithParams() throws {
		let packet = NymeaCommandPacket(command: .connect, params: NymeaConnectParams(e: "MySSID", p: "password"))
		let data = try JSONEncoder().encode(packet)
		let json = String(data: data, encoding: .utf8)!
		#expect(json.contains("\"c\":1"))
		#expect(json.contains("MySSID"))
	}

	@Test func encodeSimpleCommand() throws {
		let cmd = NymeaSimpleCommand(command: .getConnection)
		let data = try JSONEncoder().encode(cmd)
		let json = String(data: data, encoding: .utf8)!
		#expect(json.contains("\"c\":5"))
	}
}

// MARK: - NymeaResponsePacket decoding

@Suite("NymeaResponsePacket decoding extended")
struct NymeaResponsePacketDecodingExtendedTests {

	@Test func decodeResponse() throws {
		let json = """
		{"c":0,"r":0}
		"""
		let response = try JSONDecoder().decode(NymeaResponsePacket.self, from: json.data(using: .utf8)!)
		#expect(response.c == 0)
		#expect(response.r == 0)
	}
}

// MARK: - NymeaWirelessConnectionStatus

@Suite("NymeaWirelessConnectionStatus extended")
struct NymeaWirelessConnectionStatusExtendedTests {

	@Test func isConnecting_trueCases() {
		let connectingStatuses: [NymeaWirelessConnectionStatus] = [
			.prepare,
			.config,
			.needAuth,
			.ipConfig,
			.ipCheck,
			.secondaries
		]
		for status in connectingStatuses {
			#expect(status.isConnecting)
		}
	}

	@Test func isConnecting_falseCases() {
		let notConnectingStatuses: [NymeaWirelessConnectionStatus] = [
			.disconnected,
			.activated,
			.unknown,
			.failed
		]
		for status in notConnectingStatuses {
			#expect(!status.isConnecting)
		}
	}

	@Test func descriptions_nonEmpty() {
		let allStatuses: [NymeaWirelessConnectionStatus] = [
			.unknown, .unmanaged, .unavailable, .disconnected,
			.prepare, .config, .needAuth, .ipConfig, .ipCheck,
			.secondaries, .activated, .deactivating, .failed
		]
		for status in allStatuses {
			#expect(!status.description.isEmpty)
		}
	}
}

// MARK: - NymeaCommanderError

@Suite("NymeaCommanderError descriptions extended")
struct NymeaCommanderErrorDescriptionExtendedTests {

	@Test func errors_haveDescriptions() {
		let errors: [NymeaCommanderError] = [
			.invalidCommand, .invalidParameter,
			.networkManagerNotAvailable, .wirelessNotAvailable,
			.networkingDisabled, .wirelessDisabled, .unknown
		]
		for error in errors {
			#expect(error.errorDescription != nil)
			#expect(!error.errorDescription!.isEmpty)
		}
	}

	@Test func success_returnsNil() {
		#expect(NymeaCommanderError.success.errorDescription == nil)
	}
}

// MARK: - URL.TimeoutError

@Suite("URL TimeoutError extended")
struct URLTimeoutErrorExtendedTests {

	@Test func errorDescription_containsSeconds() {
		let error = URL.TimeoutError.timedOut(30.0)
		#expect(error.errorDescription?.contains("30.0") == true)
		#expect(error.errorDescription?.contains("timed out") == true)
	}

	@Test func errorDescription_smallTimeout() {
		let error = URL.TimeoutError.timedOut(0.5)
		#expect(error.errorDescription?.contains("0.5") == true)
	}
}

// MARK: - NymeaGetNetworksResponse

@Suite("NymeaGetNetworksResponse decoding extended")
struct NymeaGetNetworksResponseDecodingExtendedTests {

	@Test func decode_withNetworks() throws {
		let json = """
		{"c":0,"r":0,"p":[{"e":"TestSSID","m":"AA:BB:CC:DD:EE:FF","s":80,"p":1}]}
		"""
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: json.data(using: .utf8)!)
		#expect(response.p?.count == 1)
		#expect(response.p?.first?.essid == "TestSSID")
	}

	@Test func decode_withNilPayload() throws {
		let json = """
		{"c":0,"r":0}
		"""
		let response = try JSONDecoder().decode(NymeaGetNetworksResponse.self, from: json.data(using: .utf8)!)
		#expect(response.p == nil)
	}
}

// MARK: - EXICodec additional paths

@Suite("EXICodec error paths")
struct EXICodecErrorPathTests {

	@Test func decompress_invalidData_returnsNilOrFallback() {
		// Random bytes that are neither valid zlib nor valid UTF-8
		let randomData = Data([0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA])
		let result = EXICodec.shared.decompress(randomData)
		// May return nil or attempt raw UTF-8 fallback
		_ = result
	}

	@Test func decompress_validUTF8String_returnsFallback() {
		// Plain uncompressed UTF-8 text - should fall back to raw string
		let text = "<event uid=\"test\"/>"
		let data = text.data(using: .utf8)!
		let result = EXICodec.shared.decompress(data)
		// Should return the raw string as fallback when zlib decompression fails
		if let result {
			#expect(result.contains("event"))
		}
	}

	@Test func decompress_emptyData() {
		let result = EXICodec.shared.decompress(Data())
		_ = result // should not crash
	}

	@Test func compress_emptyString() {
		let result = EXICodec.shared.compress("")
		_ = result // should not crash
	}

	@Test func compress_longString() {
		let longXML = String(repeating: "<node id=\"test\"/>", count: 100)
		let result = EXICodec.shared.compress(longXML)
		#expect(result != nil)
		if let result {
			// Compressed should be smaller than original for repetitive data
			#expect(result.count < longXML.utf8.count)
		}
	}
}

// MARK: - telemetryPacket ingestion (regression for #2004)

@Suite("telemetryPacket ingestion")
@MainActor
struct TelemetryPacketIngestTests {

	/// A connected node num used only to mark packets as "received over the mesh"
	/// (connectedNode != packet.from); it is never created by `telemetryPacket`.
	private static let connectedNode: Int64 = 0x2004_FFFF

	/// Builds a decoded environment-telemetry `MeshPacket`, mirroring how firmware delivers a
	/// remote node's reading over the mesh.
	private func makeEnvironmentTelemetryPacket(
		from nodeNum: UInt32,
		temperature: Float,
		reportedTime: UInt32,
		rxTime: UInt32
	) throws -> MeshPacket {
		var environment = EnvironmentMetrics()
		environment.temperature = temperature

		var telemetry = Telemetry()
		telemetry.environmentMetrics = environment
		telemetry.time = reportedTime

		var dataMessage = DataMessage()
		dataMessage.payload = try telemetry.serializedData()
		dataMessage.portnum = .telemetryApp

		var packet = MeshPacket()
		packet.id = 0x2004
		packet.from = nodeNum
		packet.to = UInt32.max
		packet.rxTime = rxTime
		packet.rxSnr = 5.5
		packet.rxRssi = -90
		packet.decoded = dataMessage
		return packet
	}

	/// Latest environment (`metricsType == 1`) telemetry for `nodeNum`, read back through a fresh
	/// context so we observe what `telemetryPacket` actually persisted — the same predicate the
	/// node detail UI uses.
	private func fetchLatestEnvironmentTelemetry(forNode nodeNum: Int64) throws -> TelemetryEntity? {
		let context = ModelContext(sharedModelContainer)
		let environmentType: Int32 = 1
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> {
				$0.nodeTelemetry?.num == nodeNum && $0.metricsType == environmentType
			},
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first
	}

	/// Fix #2: telemetry from a node with no `NodeInfoEntity` yet must create the node and link the
	/// reading, instead of being saved as an orphan row (nodeTelemetry == nil) the UI can never query.
	@Test func environmentTelemetryFromUnknownNode_createsNodeAndLinksReading() async throws {
		let nodeNum: UInt32 = 0x2004_AA01
		let packet = try makeEnvironmentTelemetryPacket(
			from: nodeNum,
			temperature: 23.5,
			reportedTime: 1_700_000_500,
			rxTime: 1_700_000_000
		)

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.telemetryPacket(packet: packet, connectedNode: Self.connectedNode)
		await mesh.flushDebouncedSaves()

		let num = Int64(nodeNum)
		let context = ModelContext(sharedModelContainer)
		let nodes = try context.fetch(
			FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == num })
		)
		#expect(nodes.count == 1)
		// A node minted from telemetry must be stamped lastHeard here, since updateAnyPacketFrom
		// only updates nodes that already existed; otherwise it reads as never-heard.
		#expect(nodes.first?.lastHeard == Date(timeIntervalSince1970: 1_700_000_000))

		let latest = try fetchLatestEnvironmentTelemetry(forNode: num)
		#expect(latest != nil)
		#expect(latest?.temperature == 23.5)
		#expect(latest?.nodeTelemetry?.num == num)
	}

	/// Fix #1: a remote node that reports `time == 0` (no RTC/GPS) must fall back to the packet
	/// receive time, not 1970, otherwise the reading is hidden by the latest-sort / 7-day window.
	@Test func environmentTelemetryWithZeroTime_fallsBackToReceiveTime() async throws {
		let nodeNum: UInt32 = 0x2004_AA02
		let receiveTime: UInt32 = 1_700_000_000
		let packet = try makeEnvironmentTelemetryPacket(
			from: nodeNum,
			temperature: 19.0,
			reportedTime: 0,
			rxTime: receiveTime
		)

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.telemetryPacket(packet: packet, connectedNode: Self.connectedNode)
		await mesh.flushDebouncedSaves()

		let latest = try fetchLatestEnvironmentTelemetry(forNode: Int64(nodeNum))
		#expect(latest != nil)
		#expect(latest?.time == Date(timeIntervalSince1970: TimeInterval(receiveTime)))
	}

	/// Fix #1 (continued): with no usable time source at all (reported time and rxTime both 0),
	/// fall back to "now" rather than 1970 so the reading still surfaces in recent history.
	@Test func environmentTelemetryWithNoTimeSource_fallsBackToNow() async throws {
		let nodeNum: UInt32 = 0x2004_AA03
		let packet = try makeEnvironmentTelemetryPacket(
			from: nodeNum,
			temperature: 21.0,
			reportedTime: 0,
			rxTime: 0
		)

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.telemetryPacket(packet: packet, connectedNode: Self.connectedNode)
		await mesh.flushDebouncedSaves()

		let latest = try fetchLatestEnvironmentTelemetry(forNode: Int64(nodeNum))
		#expect(latest != nil)
		// Far newer than the 1970 epoch the old code would have stored.
		let year2020 = Date(timeIntervalSince1970: 1_577_836_800)
		#expect((latest?.time ?? .distantPast) > year2020)
	}

	/// Builds a decoded air-quality-telemetry `MeshPacket` carrying only the three *standard* PM
	/// concentrations, leaving the *environmental* variants unset so the test can also assert that
	/// the ingest path's `has`-gating persists absent fields as nil. Issue #2040.
	private func makeAirQualityTelemetryPacket(
		from nodeNum: UInt32,
		pm10Standard: UInt32,
		pm25Standard: UInt32,
		pm100Standard: UInt32,
		reportedTime: UInt32
	) throws -> MeshPacket {
		var airQuality = AirQualityMetrics()
		airQuality.pm10Standard = pm10Standard
		airQuality.pm25Standard = pm25Standard
		airQuality.pm100Standard = pm100Standard

		var telemetry = Telemetry()
		telemetry.airQualityMetrics = airQuality
		telemetry.time = reportedTime

		var dataMessage = DataMessage()
		dataMessage.payload = try telemetry.serializedData()
		dataMessage.portnum = .telemetryApp

		var packet = MeshPacket()
		packet.id = 0x2004
		packet.from = nodeNum
		packet.to = UInt32.max
		packet.rxTime = reportedTime
		packet.rxSnr = 5.5
		packet.rxRssi = -90
		packet.decoded = dataMessage
		return packet
	}

	/// Latest air-quality (`metricsType == 3`) telemetry for `nodeNum`, read back through a fresh
	/// context so we observe what `telemetryPacket` actually persisted.
	private func fetchLatestAirQualityTelemetry(forNode nodeNum: Int64) throws -> TelemetryEntity? {
		let context = ModelContext(sharedModelContainer)
		let airQualityType: Int32 = 3
		var descriptor = FetchDescriptor<TelemetryEntity>(
			predicate: #Predicate<TelemetryEntity> {
				$0.nodeTelemetry?.num == nodeNum && $0.metricsType == airQualityType
			},
			sortBy: [SortDescriptor(\TelemetryEntity.time, order: .reverse)]
		)
		descriptor.fetchLimit = 1
		return try context.fetch(descriptor).first
	}

	/// Issue #2040 (Stage 1): the `.airQualityMetrics` telemetry variant must be parsed and
	/// persisted as a `metricsType == 3` row with the PM fields populated, and `has`-gating must
	/// leave the unreported (environmental) fields as nil rather than storing a spurious 0.
	@Test func airQualityTelemetry_persistsPMFieldsAsType3() async throws {
		let nodeNum: UInt32 = 0x2004_AA04
		let packet = try makeAirQualityTelemetryPacket(
			from: nodeNum,
			pm10Standard: 1,
			pm25Standard: 2,
			pm100Standard: 3,
			reportedTime: 1_700_000_500
		)

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.telemetryPacket(packet: packet, connectedNode: Self.connectedNode)
		await mesh.flushDebouncedSaves()

		let latest = try fetchLatestAirQualityTelemetry(forNode: Int64(nodeNum))
		#expect(latest != nil)
		#expect(latest?.metricsType == 3)
		#expect(latest?.pm10Standard == 1)
		#expect(latest?.pm25Standard == 2)
		#expect(latest?.pm100Standard == 3)
		// Unreported environmental fields must stay nil (has-gating), not persist as 0.
		#expect(latest?.pm10Environmental == nil)
		#expect(latest?.pm25Environmental == nil)
		#expect(latest?.pm100Environmental == nil)
		#expect(latest?.nodeTelemetry?.num == Int64(nodeNum))
	}
}

// MARK: - PAX counter ingestion

// MARK: - Position ingestion — malformed-packet hardening (DEF CON)

@Suite("Position packet ingestion hardening", .serialized)
@MainActor
struct PositionPacketIngestHardeningTests {
	private func makePositionPacket(from nodeNum: UInt32, mutate: (inout Position) -> Void) throws -> MeshPacket {
		var position = Position()
		// Real coordinates so the packet passes hasValidCoordinates and reaches the conversions.
		position.latitudeI = Int32(47.6062 * 1e7)
		position.longitudeI = Int32(-122.3321 * 1e7)
		mutate(&position)

		var dataMessage = DataMessage()
		dataMessage.payload = try position.serializedData()
		dataMessage.portnum = .positionApp

		var packet = MeshPacket()
		packet.from = nodeNum
		packet.decoded = dataMessage
		return packet
	}

	/// A single unauthenticated POSITION_APP packet whose UInt32 fields exceed Int32.max must
	/// no longer SIGTRAP the app (the old `Int32(UInt32)` conversions trapped). The values must
	/// land truncated rather than crash the process.
	@Test func oversizedUInt32Fields_doNotCrashAndTruncate() async throws {
		let nodeNum: UInt32 = 0x20DE_FC10
		let persistedNodeNum = Int64(nodeNum)
		let packet = try makePositionPacket(from: nodeNum) { p in
			p.satsInView = 0xFFFF_FFFF   // > Int32.max — trapped before the fix
			p.seqNumber = 0xFFFF_FFFF
			p.groundSpeed = 0x8000_0000
			p.groundTrack = 0xFFFF_FFFF  // also exercises the pre-conversion range check
			p.precisionBits = 0xFFFF_FFFF
		}

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		// Reaching this line at all (no fatalError / SIGTRAP) is the core assertion — the old
		// code trapped here on the first oversized Int32(UInt32) conversion.
		await mesh.upsertPositionPacket(packet: packet)
		await mesh.flushDebouncedSaves()

		// Truncated, not crashed: 0xFFFFFFFF as Int32(truncatingIfNeeded:) == -1. upsertPositionPacket
		// links the position to the (find-or-created) node, so scope the query to THIS packet's node
		// instead of the bare sentinel — a pre-existing row could otherwise satisfy it.
		let context = ModelContext(sharedModelContainer)
		let truncated = try context.fetch(FetchDescriptor<PositionEntity>(
			predicate: #Predicate { $0.nodePosition?.num == persistedNodeNum && $0.satsInView == -1 }
		))
		#expect(!truncated.isEmpty, "position was persisted with the truncated value, proving no crash")
	}
}

// MARK: - Global entity caps (node / waypoint eviction)

@Suite("Entity cap eviction", .serialized)
@MainActor
struct EntityCapEvictionTests {
	private func freshMesh() throws -> (MeshPackets, ModelContainer) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		return (MeshPackets(modelContainer: container), container)
	}

	@Test func nodes_evictLeastRecentlyHeard_keepingFavorites() async throws {
		let (mesh, container) = try freshMesh()
		let context = ModelContext(container)
		let base = Date(timeIntervalSince1970: 1_700_000_000)
		func makeNode(_ num: Int64, heard: TimeInterval, favorite: Bool) -> NodeInfoEntity {
			let node = NodeInfoEntity()
			node.num = num
			node.id = num
			node.lastHeard = base.addingTimeInterval(heard)
			node.favorite = favorite
			return node
		}
		// Node 1 is the OLDEST but a favorite (must be protected); 2 and 3 are the oldest
		// non-favorites (must be evicted); 4 is newest (must survive).
		[makeNode(1, heard: 0, favorite: true),
		 makeNode(2, heard: 10, favorite: false),
		 makeNode(3, heard: 20, favorite: false),
		 makeNode(4, heard: 30, favorite: false)].forEach { context.insert($0) }
		try context.save()

		await mesh.evictNodesIfOverCap(2)
		await mesh.flushDebouncedSaves()

		let remaining = try ModelContext(container)
			.fetch(FetchDescriptor<NodeInfoEntity>()).map { $0.num }.sorted()
		// Favorite (1, despite being oldest) + newest (4) survive; oldest non-favorites (2,3) evicted.
		#expect(remaining == [1, 4])
	}

	@Test func waypoints_evictOldestLastUpdated() async throws {
		let (mesh, container) = try freshMesh()
		let context = ModelContext(container)
		let base = Date(timeIntervalSince1970: 1_700_000_000)
		func makeWaypoint(_ id: Int64, updated: TimeInterval) -> WaypointEntity {
			let waypoint = WaypointEntity()
			waypoint.id = id
			waypoint.lastUpdated = base.addingTimeInterval(updated)
			return waypoint
		}
		[makeWaypoint(1, updated: 0),   // oldest
		 makeWaypoint(2, updated: 10),
		 makeWaypoint(3, updated: 20)].forEach { context.insert($0) }  // newest
		try context.save()

		await mesh.evictWaypointsIfOverCap(1)
		await mesh.flushDebouncedSaves()

		let remaining = try ModelContext(container)
			.fetch(FetchDescriptor<WaypointEntity>()).map { $0.id }.sorted()
		#expect(remaining == [3])   // only the most-recently-updated survives
	}

	@Test func underCap_noEviction() async throws {
		let (mesh, container) = try freshMesh()
		let context = ModelContext(container)
		let node = NodeInfoEntity(); node.num = 7; node.id = 7; node.lastHeard = Date()
		context.insert(node)
		try context.save()

		await mesh.evictNodesIfOverCap(10_000)
		await mesh.flushDebouncedSaves()

		#expect(try ModelContext(container).fetchCount(FetchDescriptor<NodeInfoEntity>()) == 1)
	}

	/// Eviction runs inside `savePendingChanges` before the commit, so a node just created this
	/// transaction is still a pending insert with a nil `lastHeard` — which sorts stalest. It must
	/// NOT be evicted before it is saved; older persisted rows are freed to make room instead.
	@Test func newNodeInTransaction_survivesEviction() async throws {
		let (mesh, container) = try freshMesh()
		let context = ModelContext(container)
		let base = Date(timeIntervalSince1970: 1_700_000_000)
		func makeNode(_ num: Int64, heard: TimeInterval) -> NodeInfoEntity {
			let node = NodeInfoEntity()
			node.num = num
			node.id = num
			node.lastHeard = base.addingTimeInterval(heard)
			node.favorite = false
			return node
		}
		// Three persisted non-favorites, all older than "now". With cap = 2, creating one more node
		// pushes the count to 4, so eviction must delete 2 rows.
		[makeNode(1, heard: 0), makeNode(2, heard: 10), makeNode(3, heard: 20)].forEach { context.insert($0) }
		try context.save()

		// Creates pending node 99 (nil lastHeard), enforces cap 2, commits — all one transaction.
		await mesh.createNodeThenEvict(num: 99, cap: 2)

		let remaining = try ModelContext(container)
			.fetch(FetchDescriptor<NodeInfoEntity>()).map { $0.num }.sorted()
		// Total lands at cap (2). The brand-new node (99) is kept — it was excluded from the
		// deletion candidates — and the two stalest persisted rows (1, 2) are evicted instead.
		#expect(remaining == [3, 99])
	}
}

// MARK: - "Signed node" shield authenticity (forgeable-shield fix)

@Suite("Signed-node shield authenticity", .serialized)
@MainActor
struct SignedShieldAuthenticityTests {
	private func freshMesh() throws -> (MeshPackets, ModelContainer) {
		let container = try ModelContainer(
			for: Schema(MeshtasticSchema.allModels),
			configurations: ModelConfiguration(isStoredInMemoryOnly: true)
		)
		return (MeshPackets(modelContainer: container), container)
	}

	private func makeNodeInfoPacket(from num: UInt32, payloadClaimsSigned: Bool, transportVerified: Bool) throws -> MeshPacket {
		var nodeInfo = NodeInfo()
		nodeInfo.num = num
		nodeInfo.hasXeddsaSigned_p = payloadClaimsSigned
		var dataMessage = DataMessage()
		dataMessage.payload = try nodeInfo.serializedData()
		dataMessage.portnum = .nodeinfoApp
		var packet = MeshPacket()
		packet.from = num
		packet.decoded = dataMessage
		packet.xeddsaSigned = transportVerified
		return packet
	}

	private func fetchNode(_ num: UInt32, in container: ModelContainer) throws -> NodeInfoEntity? {
		let persisted = Int64(num)
		return try ModelContext(container)
			.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == persisted })).first
	}

	@Test func spoofedPayloadBit_doesNotForgeShield() async throws {
		let (mesh, container) = try freshMesh()
		let num: UInt32 = 0x20DE_FC50
		// Attacker claims signed IN THE PAYLOAD, but the radio did NOT verify a signature.
		let packet = try makeNodeInfoPacket(from: num, payloadClaimsSigned: true, transportVerified: false)
		await mesh.upsertNodeInfoPacket(packet: packet)
		await mesh.flushDebouncedSaves()

		let node = try fetchNode(num, in: container)
		#expect(node != nil)
		#expect(node?.hasXeddsaSigned == false)   // forge blocked — payload bit is not trusted
	}

	@Test func radioVerifiedBit_marksSigned() async throws {
		let (mesh, container) = try freshMesh()
		let num: UInt32 = 0x20DE_FC51
		// Payload omits the claim, but the radio VERIFIED the packet's signature — any node we hear
		// signing (not just the connected one) should legitimately show the shield.
		let packet = try makeNodeInfoPacket(from: num, payloadClaimsSigned: false, transportVerified: true)
		await mesh.upsertNodeInfoPacket(packet: packet)
		await mesh.flushDebouncedSaves()

		#expect(try fetchNode(num, in: container)?.hasXeddsaSigned == true)
	}

	@Test func latch_survivesLaterUnverifiedPacket() async throws {
		let (mesh, container) = try freshMesh()
		let num: UInt32 = 0x20DE_FC52
		// First a radio-verified signed packet marks the node, then a spoofed/unverified one must
		// neither downgrade it (latch) nor be able to forge it in the first place.
		await mesh.upsertNodeInfoPacket(packet: try makeNodeInfoPacket(from: num, payloadClaimsSigned: false, transportVerified: true))
		await mesh.flushDebouncedSaves()
		await mesh.upsertNodeInfoPacket(packet: try makeNodeInfoPacket(from: num, payloadClaimsSigned: false, transportVerified: false))
		await mesh.flushDebouncedSaves()

		#expect(try fetchNode(num, in: container)?.hasXeddsaSigned == true)   // latched, not downgraded
	}
}

@Suite("PAX counter ingestion", .serialized)
@MainActor
struct PaxCounterPacketIngestTests {
	private func makePaxPacket(from nodeNum: UInt32) throws -> MeshPacket {
		var paxCounter = Paxcount()
		paxCounter.wifi = 4
		paxCounter.ble = 7
		paxCounter.uptime = 60

		var dataMessage = DataMessage()
		dataMessage.payload = try paxCounter.serializedData()
		dataMessage.portnum = .paxcounterApp

		var packet = MeshPacket()
		packet.from = nodeNum
		packet.decoded = dataMessage
		return packet
	}

	@Test func unknownSender_createsNodeAndLinksReading() async throws {
		let nodeNum: UInt32 = 0x20DE_FC03
		let persistedNodeNum = Int64(nodeNum)
		let context = ModelContext(sharedModelContainer)
		let orphansBefore = try context.fetchCount(FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate { $0.paxNode == nil }
		))

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.paxCounterPacket(packet: try makePaxPacket(from: nodeNum))
		await mesh.flushDebouncedSaves()

		// Hearing the packet created the sender, and the reading is linked to it.
		#expect(try context.fetchCount(FetchDescriptor<NodeInfoEntity>(
			predicate: #Predicate { $0.num == persistedNodeNum }
		)) == 1)
		let readings = try context.fetch(FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate { $0.paxNode?.num == persistedNodeNum }
		))
		#expect(readings.count == 1)
		#expect(readings.first?.wifi == 4)
		#expect(readings.first?.ble == 7)
		// The original bug: an unlinked row swept in by the next debounced save.
		#expect(try context.fetchCount(FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate { $0.paxNode == nil }
		)) == orphansBefore)
	}

	@Test func knownSender_persistsLinkedReading() async throws {
		let nodeNum: UInt32 = 0x20DE_FC02
		let persistedNodeNum = Int64(nodeNum)
		let context = ModelContext(sharedModelContainer)
		let node = NodeInfoEntity()
		node.num = persistedNodeNum
		context.insert(node)
		try context.save()

		let mesh = MeshPackets(modelContainer: sharedModelContainer)
		await mesh.paxCounterPacket(packet: try makePaxPacket(from: nodeNum))
		await mesh.flushDebouncedSaves()

		let readings = try context.fetch(FetchDescriptor<PaxCounterEntity>(
			predicate: #Predicate { $0.paxNode?.num == persistedNodeNum }
		))
		#expect(readings.count == 1)
		#expect(readings.first?.wifi == 4)
		#expect(readings.first?.ble == 7)
	}
}

@Suite("device metadata ingestion")
@MainActor
struct DeviceMetadataIngestTests {
	private func makeMetadata(version: String) -> DeviceMetadata {
		var metadata = DeviceMetadata()
		metadata.firmwareVersion = version
		metadata.deviceStateVersion = 1
		return metadata
	}

	@Test func repeatedMetadataForNode_reusesExistingEntity() async throws {
		let nodeNum: Int64 = 0x2004_AA05
		let mesh = MeshPackets(modelContainer: sharedModelContainer)

		await mesh.deviceMetadataPacket(metadata: makeMetadata(version: "2.7.17.abcdef"), fromNum: nodeNum)
		let context = ModelContext(sharedModelContainer)
		let node = try #require(
			context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })).first
		)
		let firstMetadataID = try #require(node.metadata).persistentModelID

		await mesh.deviceMetadataPacket(metadata: makeMetadata(version: "2.7.18.abcdef"), fromNum: nodeNum)

		let refreshedNode = try #require(
			context.fetch(FetchDescriptor<NodeInfoEntity>(predicate: #Predicate { $0.num == nodeNum })).first
		)
		#expect(refreshedNode.metadata?.persistentModelID == firstMetadataID)
		#expect(refreshedNode.metadata?.firmwareVersion == "2.7.18")
	}
}
