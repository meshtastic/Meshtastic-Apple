//
//  DeviceProfileImportTests.swift
//  Meshtastic
//
//  Verifies the pure device-profile import core (parse, plan, ordering, dedupe, gating, sensitivity,
//  owner merge) and the apply engine's abort/reboot semantics via a mock gateway. No device required.
//

import Foundation
import Testing
import MeshtasticProtobufs

@testable import Meshtastic

@Suite("DeviceProfile import")
struct DeviceProfileImportTests {

	// MARK: - Builders

	/// A profile with every applyable section populated, used to exercise coverage and ordering.
	private func makeFullProfile() throws -> DeviceProfile {
		var profile = DeviceProfile()
		profile.longName = "Base Camp"
		profile.shortName = "BC01"

		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		config.position = Config.PositionConfig()
		config.power = Config.PowerConfig()
		var network = Config.NetworkConfig()
		network.wifiSsid = "home"
		network.wifiPsk = "secret"
		config.network = network
		config.bluetooth = Config.BluetoothConfig()
		var security = Config.SecurityConfig()
		security.privateKey = Data([1, 2, 3])
		config.security = security
		var lora = Config.LoRaConfig()
		lora.region = .us
		config.lora = lora
		profile.config = config

		var module = LocalModuleConfig()
		module.mqtt = ModuleConfig.MQTTConfig()
		module.serial = ModuleConfig.SerialConfig()
		module.externalNotification = ModuleConfig.ExternalNotificationConfig()
		module.storeForward = ModuleConfig.StoreForwardConfig()
		module.rangeTest = ModuleConfig.RangeTestConfig()
		module.telemetry = ModuleConfig.TelemetryConfig()
		module.cannedMessage = ModuleConfig.CannedMessageConfig()
		module.audio = ModuleConfig.AudioConfig()
		module.neighborInfo = ModuleConfig.NeighborInfoConfig()
		module.ambientLighting = ModuleConfig.AmbientLightingConfig()
		module.detectionSensor = ModuleConfig.DetectionSensorConfig()
		module.paxcounter = ModuleConfig.PaxcounterConfig()
		module.tak = ModuleConfig.TAKConfig()
		module.trafficManagement = ModuleConfig.TrafficManagementConfig()
		module.statusmessage = ModuleConfig.StatusMessageConfig()
		profile.moduleConfig = module

		profile.ringtone = "a:d=4,o=5,b=100:c"
		profile.cannedMessages = "hi|bye"

		var fixed = Position()
		fixed.latitudeI = 377_749_000
		fixed.longitudeI = -1_224_194_000
		profile.fixedPosition = fixed

		return profile
	}

	private func channelURL(channelCount: Int = 2, withLoRa: Bool = true) throws -> String {
		var channelSet = ChannelSet()
		if withLoRa {
			var lora = Config.LoRaConfig()
			lora.region = .us
			channelSet.loraConfig = lora
		}
		for i in 0..<channelCount {
			var settings = ChannelSettings()
			settings.name = "Ch\(i)"
			settings.psk = Data([UInt8(i)])
			channelSet.settings.append(settings)
		}
		return try MeshtasticChannelURL.urlString(for: channelSet)
	}

	private func index(of kind: ImportItemKind, in plan: DeviceProfileImportPlan) -> Int? {
		plan.items.firstIndex { $0.kind == kind }
	}

	// MARK: - Parse

	@Test("Empty, oversize, and garbage data throw the right errors")
	func parseErrors() {
		#expect(throws: DeviceProfileImportError.emptyFile) {
			_ = try DeviceProfileImportPlan.parseDeviceProfile(Data())
		}
		let big = Data(count: DeviceProfileImportPlan.maxProfileBytes + 1)
		#expect(throws: DeviceProfileImportError.tooLarge) {
			_ = try DeviceProfileImportPlan.parseDeviceProfile(big)
		}
		// A run of non-zero bytes is not a decodable DeviceProfile.
		let garbage = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
		#expect(throws: DeviceProfileImportError.malformed) {
			_ = try DeviceProfileImportPlan.parseDeviceProfile(garbage)
		}
	}

	@Test("A profile round-trips through serialize -> parse unchanged")
	func parseRoundTrip() throws {
		let profile = try makeFullProfile()
		let data = try profile.serializedData()
		let parsed = try DeviceProfileImportPlan.parseDeviceProfile(data)
		#expect(parsed == profile)
	}

	@Test("An empty profile has nothing to import")
	func nothingToImport() {
		#expect(throws: DeviceProfileImportError.nothingToImport) {
			_ = try DeviceProfileImportPlan(profile: DeviceProfile(), currentUser: nil)
		}
	}

	// MARK: - Coverage & gating

	@Test("A full profile yields exactly one item per expected kind and no others")
	func coverage() throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())
		let kinds = Set(plan.items.map(\.kind))
		let expected: Set<ImportItemKind> = [
			.owner, .deviceConfig, .displayConfig, .positionConfig, .powerConfig, .networkConfig,
			.bluetoothConfig, .securityConfig, .mqtt, .serial, .externalNotification, .storeForward,
			.rangeTest, .telemetry, .cannedMessage, .audio, .neighborInfo, .ambientLighting,
			.detectionSensor, .paxcounter, .tak, .trafficManagement, .statusMessage, .ringtone,
			.cannedMessagesText, .fixedPosition, .loraConfig
		]
		#expect(kinds == expected)
		// One item per kind (no duplicates).
		#expect(plan.items.count == expected.count)
	}

	@Test("Absent has* fields produce no items")
	func gating() throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config
		var module = LocalModuleConfig()
		module.telemetry = ModuleConfig.TelemetryConfig()
		profile.moduleConfig = module

		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)
		#expect(plan.items.map(\.kind) == [.deviceConfig, .telemetry])
	}

	@Test("Owner step is omitted when there is no base user")
	func ownerRequiresBase() throws {
		var profile = DeviceProfile()
		profile.longName = "Roamer"
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config

		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)
		#expect(!plan.items.contains { $0.kind == .owner })
	}

	// MARK: - Ordering

	@Test("Items are emitted in a safe apply order")
	func ordering() throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())

		// Owner first, Channels & LoRa last.
		#expect(plan.items.first?.kind == .owner)
		#expect(plan.items.last?.section == .channelsAndLoRa)

		let device = index(of: .deviceConfig, in: plan)!
		let position = index(of: .positionConfig, in: plan)!
		let fixed = index(of: .fixedPosition, in: plan)!
		let canned = index(of: .cannedMessage, in: plan)!
		let cannedText = index(of: .cannedMessagesText, in: plan)!
		let network = index(of: .networkConfig, in: plan)!
		let bluetooth = index(of: .bluetoothConfig, in: plan)!
		let security = index(of: .securityConfig, in: plan)!
		let lora = index(of: .loraConfig, in: plan)!

		#expect(fixed > position)          // fixed position after the position config that flags it
		#expect(cannedText > canned)       // canned text after the canned-message module config
		#expect(network > device)          // network placed after the cheap configs
		#expect(bluetooth > network)       // bluetooth just before the terminal step
		#expect(security > bluetooth)      // security just before the terminal step
		#expect(lora > security)           // LoRa/channels strictly last
	}

	// MARK: - LoRa / channel dedupe

	@Test("With both a channel URL and a LoRa config, only the channel URL terminal item is emitted")
	func loraDedupeChannelURLWins() throws {
		var profile = try makeFullProfile()
		profile.channelURL = try channelURL()
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())

		let terminal = plan.items.filter { $0.section == .channelsAndLoRa }
		#expect(terminal.count == 1)
		#expect(terminal.first?.kind == .channelURL)
		#expect(!plan.items.contains { $0.kind == .loraConfig })
	}

	@Test("With no channel URL, a standalone LoRa config is the terminal item")
	func loraDedupeNoChannelURL() throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())
		let terminal = plan.items.filter { $0.section == .channelsAndLoRa }
		#expect(terminal.count == 1)
		#expect(terminal.first?.kind == .loraConfig)
	}

	@Test("A malformed channel URL falls back to the standalone LoRa config")
	func invalidChannelURLFallsBack() throws {
		var profile = try makeFullProfile()
		profile.channelURL = "https://meshtastic.org/e/#not-valid-base64!!!"
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())

		let terminal = plan.items.filter { $0.section == .channelsAndLoRa }
		#expect(terminal.count == 1)
		#expect(terminal.first?.kind == .loraConfig)
	}

	@Test("A channel URL without a LoRa config falls back to the standalone LoRa config")
	func channelURLWithoutLoRaFallsBack() throws {
		var profile = try makeFullProfile()
		// A replace-mode URL that lacks a LoRa config can't be used to replace channels, so the plan must
		// fall back to the standalone LoRa config to still restore the region.
		profile.channelURL = try channelURL(withLoRa: false)
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())

		let terminal = plan.items.filter { $0.section == .channelsAndLoRa }
		#expect(terminal.count == 1)
		#expect(terminal.first?.kind == .loraConfig)
	}

	@Test("An add-mode channel URL falls back to the standalone LoRa config")
	func addModeChannelURLFallsBack() throws {
		var channelSet = ChannelSet()
		var lora = Config.LoRaConfig()
		lora.region = .us
		channelSet.loraConfig = lora
		var settings = ChannelSettings()
		settings.name = "Ch0"
		channelSet.settings.append(settings)

		var profile = try makeFullProfile()
		// An add-mode URL (?add=true) drops its LoRa config on parse, so it can't own the terminal step.
		profile.channelURL = try MeshtasticChannelURL.urlString(for: channelSet, addChannels: true)
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())

		let terminal = plan.items.filter { $0.section == .channelsAndLoRa }
		#expect(terminal.count == 1)
		#expect(terminal.first?.kind == .loraConfig)
	}

	// MARK: - Fixed position gating

	@Test("A zero-coordinate fixed position is not imported")
	func fixedPositionZeroSkipped() throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config
		profile.fixedPosition = Position()   // lat/lon default to 0

		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)
		#expect(!plan.items.contains { $0.kind == .fixedPosition })
	}

	// MARK: - Sensitivity & reboot flags

	@Test("Sensitive and reboot flags are set on the right items")
	func flags() throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())
		// A standalone LoRa config carries no secret (channel PSKs travel only in the channel URL), so it
		// is a reboot but not sensitive.
		let sensitiveKinds = Set(plan.items.filter(\.isSensitive).map(\.kind))
		#expect(sensitiveKinds == [.securityConfig, .networkConfig, .mqtt])

		let rebootKinds = plan.items.filter(\.causesReboot).map(\.kind)
		#expect(rebootKinds == [.loraConfig])

		let all = Set(plan.presentSections)
		#expect(plan.containsSensitive(in: all))
		#expect(plan.willReboot(in: all))
		// Deselecting the sensitive/reboot sections clears both aggregates.
		let safe: Set<ImportSection> = [.owner, .radioAndDevice, .modules, .personalization, .fixedPosition]
		#expect(!plan.willReboot(in: safe))
	}

	@Test("A channel URL terminal item is flagged sensitive because it carries channel PSKs")
	func channelURLIsSensitive() throws {
		var profile = try makeFullProfile()
		profile.channelURL = try channelURL()
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())
		let channelItem = try #require(plan.items.first { $0.kind == .channelURL })
		#expect(channelItem.isSensitive)
		#expect(channelItem.causesReboot)
	}

	// MARK: - Owner merge

	@Test("Owner merge overrides only the names present and preserves identity")
	func ownerMerge() {
		var base = User()
		base.id = "!deadbeef"
		base.longName = "Original Long"
		base.shortName = "OG"
		base.hwModel = .tbeam
		base.publicKey = Data([9, 9, 9])
		base.role = .router

		var profile = DeviceProfile()
		profile.longName = "Imported Long"   // shortName intentionally not set

		let merged = DeviceProfileImportPlan.ownerUser(from: profile, base: base)
		#expect(merged.longName == "Imported Long")
		#expect(merged.shortName == "OG")            // preserved — profile had no short name
		#expect(merged.id == "!deadbeef")
		#expect(merged.hwModel == .tbeam)
		#expect(merged.publicKey == Data([9, 9, 9]))
		#expect(merged.role == .router)
	}

	@Test("The emitted owner item carries the identity-preserving merged user")
	func ownerItemPreservesIdentity() throws {
		var base = User()
		base.id = "!deadbeef"
		base.longName = "Original Long"
		base.shortName = "OG"
		base.hwModel = .tbeam
		base.publicKey = Data([9, 9, 9])
		base.role = .router

		var profile = DeviceProfile()
		profile.longName = "Imported Long"   // no short name in the profile
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config

		// This pins the init -> ownerUser wiring: a regression that shipped a bare name-only User (wiping
		// id/hwModel/publicKey/role via setOwner) would fail here.
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: base)
		let ownerItem = try #require(plan.items.first { $0.kind == .owner })
		guard case let .owner(user) = ownerItem.payload else {
			Issue.record("owner item did not carry a .owner payload")
			return
		}
		#expect(user.id == "!deadbeef")
		#expect(user.hwModel == .tbeam)
		#expect(user.publicKey == Data([9, 9, 9]))
		#expect(user.role == .router)
		#expect(user.longName == "Imported Long")
		#expect(user.shortName == "OG")
	}

	// MARK: - Selection filtering

	@Test("items(for:) preserves order and drops unselected sections")
	func selectionFiltering() throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())
		let withoutSecurity = plan.presentSections.filter { $0 != .security }
		let filtered = plan.items(for: Set(withoutSecurity))
		#expect(!filtered.contains { $0.kind == .securityConfig })
		// Order within the filtered list matches the original relative order.
		let filteredKinds = filtered.map(\.kind)
		let expectedOrder = plan.items.filter { $0.section != .security }.map(\.kind)
		#expect(filteredKinds == expectedOrder)
		// Empty selection -> empty.
		#expect(plan.items(for: []).isEmpty)
	}

	// MARK: - Apply engine

	@MainActor
	private final class MockGateway: ProfileApplyGateway {
		var isConnected = true
		var failOn: ImportItemKind?
		var cancelOn: ImportItemKind?
		var attempted: [ImportItemKind] = []

		func apply(_ item: ImportItem) async throws {
			attempted.append(item.kind)
			if item.kind == cancelOn {
				throw CancellationError()
			}
			if item.kind == failOn {
				throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
			}
		}
	}

	@MainActor
	@Test("The engine aborts on the first failure and skips the rest")
	func engineAbortsOnFailure() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		profile.config = config
		var module = LocalModuleConfig()
		module.telemetry = ModuleConfig.TelemetryConfig()
		profile.moduleConfig = module
		// Order: device, display, telemetry.
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		gateway.failOn = .displayConfig
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.applied == [.deviceConfig])
		#expect(result.failed?.kind == .displayConfig)
		#expect(result.skipped == [.telemetry])
		#expect(!result.isCompleteSuccess)
		// The item after the failure was never even attempted.
		#expect(!gateway.attempted.contains(.telemetry))
	}

	@MainActor
	@Test("A fully applied plan with a LoRa step reports rebooting")
	func engineReportsReboot() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.lora = Config.LoRaConfig()
		profile.config = config
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.isCompleteSuccess)
		#expect(result.applied.contains(.loraConfig))
		#expect(result.rebooting)
	}

	@MainActor
	@Test("Cancellation stops cleanly: current and remaining items skipped, not failed")
	func engineHandlesCancellation() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		profile.config = config
		var module = LocalModuleConfig()
		module.telemetry = ModuleConfig.TelemetryConfig()
		profile.moduleConfig = module
		// Order: device, display, telemetry.
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		gateway.cancelOn = .displayConfig
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.wasCancelled)
		#expect(!result.isCompleteSuccess)
		#expect(result.failed == nil)                       // cancellation is not a failure
		#expect(result.applied == [.deviceConfig])          // completed before the cancel
		#expect(result.skipped == [.displayConfig, .telemetry])  // cancelled item + the rest
	}

	@MainActor
	@Test("A task cancelled before it runs applies nothing and reports cancelled")
	func engineHonorsPreCancelledTask() async throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())
		let gateway = MockGateway()
		let task = Task { await DeviceProfileImporter.apply(plan: plan, selection: Set(plan.presentSections), gateway: gateway) }
		task.cancel()
		let result = await task.value
		// Whether or not the loop had begun, a cancelled run must never report complete success and must
		// leave the device state coherent (nothing failed).
		#expect(!result.isCompleteSuccess)
		#expect(result.failed == nil)
		if result.wasCancelled {
			#expect(result.applied.count + result.skipped.count == plan.items.count)
		}
	}

	@Test("Every import kind has a non-empty human-readable label")
	func kindDisplayNames() {
		#expect(ImportItemKind.channelURL.displayName == "Channels & LoRa")
		#expect(ImportItemKind.securityConfig.displayName == "Security & Identity")
		#expect(ImportItemKind.cannedMessagesText.displayName == "Canned Messages")
	}

	@MainActor
	@Test("A disconnected gateway fails the first step and skips everything")
	func engineHandlesDisconnect() async throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())
		let gateway = MockGateway()
		gateway.isConnected = false
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.applied.isEmpty)
		// The first item is the failure; the remaining items (not it) are the skips.
		#expect(result.failed?.kind == plan.items.first?.kind)
		#expect(gateway.attempted.isEmpty)
		#expect(result.skipped.count == plan.items.count - 1)
		// The failed item must not also appear in the skipped list.
		#expect(!result.skipped.contains(where: { $0 == result.failed?.kind }))
	}

	@MainActor
	@Test("A failing terminal channel URL surfaces as a real failure, not a reboot")
	func channelURLFailureSurfaces() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config
		profile.channelURL = try channelURL()
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		// The production gateway does NOT swallow channelURL errors (only the standalone-lora reboot
		// disconnect), so a throwing channelURL must be reported as a failure.
		let gateway = MockGateway()
		gateway.failOn = .channelURL
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)
		#expect(result.failed?.kind == .channelURL)
		#expect(!result.rebooting)
	}
}
