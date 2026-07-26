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
			.detectionSensor, .paxcounter, .trafficManagement, .statusMessage, .ringtone,
			.cannedMessagesText, .fixedPosition, .loraConfig
		]
		#expect(kinds == expected)
		// One item per kind (no duplicates).
		#expect(plan.items.count == expected.count)
		// .tak is deliberately absent from the send list: no firmware version implements
		// set_module_config(tak), so sending it would reboot the radio (untransacted) or no-op silently
		// while still being acked as success. It is reported instead.
		#expect(!kinds.contains(.tak))
		#expect(plan.unsupported.map(\.item.kind) == [.tak])
	}

	@Test("Firmware gating drops items the connected radio cannot apply")
	func firmwareGating() throws {
		// statusmessage first shipped in v2.7.20.6658ec2; traffic_management is develop-only.
		let old = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User(),
											  firmwareVersion: "2.7.19.abc1234")
		let oldKinds = Set(old.items.map(\.kind))
		#expect(!oldKinds.contains(.statusMessage))
		#expect(!oldKinds.contains(.trafficManagement))
		#expect(!oldKinds.contains(.tak))
		#expect(Set(old.unsupported.map(\.item.kind)) == [.statusMessage, .trafficManagement, .tak])
		// Supported items are untouched by the gate.
		#expect(oldKinds.contains(.mqtt))
		#expect(oldKinds.contains(.loraConfig))

		// 2.7.20 gains statusmessage but still not traffic_management.
		let mid = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User(),
											  firmwareVersion: "2.7.20.6658ec2")
		#expect(Set(mid.items.map(\.kind)).contains(.statusMessage))
		#expect(Set(mid.unsupported.map(\.item.kind)) == [.trafficManagement, .tak])

		// 2.8.0 gains traffic_management; only the never-implemented tak remains.
		let new = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User(),
											  firmwareVersion: "2.8.0.3a0c08b")
		#expect(Set(new.items.map(\.kind)).contains(.trafficManagement))
		#expect(new.unsupported.map(\.item.kind) == [.tak])
	}

	@Test("Unknown firmware is permissive, matching the app's other capability checks")
	func firmwareGatingIsPermissiveWhenUnknown() throws {
		for version in [nil, "", "0.0.0"] as [String?] {
			#expect(DeviceProfileImportPlan.isSupported(.fromVersion("2.8.0"), firmwareVersion: version))
		}
		// .unimplemented is never permissive: no firmware supports it, known version or not.
		#expect(!DeviceProfileImportPlan.isSupported(.unimplemented, firmwareVersion: nil))
		#expect(!DeviceProfileImportPlan.isSupported(.unimplemented, firmwareVersion: "2.8.0"))
		#expect(DeviceProfileImportPlan.isSupported(.always, firmwareVersion: "2.0.0"))
		// Numeric comparison, not lexicographic: 2.7.9 must read as older than 2.7.20.
		#expect(!DeviceProfileImportPlan.isSupported(.fromVersion("2.7.20"), firmwareVersion: "2.7.9"))
		#expect(DeviceProfileImportPlan.isSupported(.fromVersion("2.7.20"), firmwareVersion: "2.7.26"))
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
		// is not sensitive. It also does not reboot — see the reboot table below.
		let sensitiveKinds = Set(plan.items.filter(\.isSensitive).map(\.kind))
		#expect(sensitiveKinds == [.securityConfig, .networkConfig, .mqtt])

		// Reboot truth, derived from firmware 2.8 (firmware/src/modules/AdminModule.cpp), NOT from what
		// is convenient for the UI. Outside an open edit transaction:
		//   - handleSetConfig defaults `requiresReboot = true` (:840). position/network/bluetooth never
		//     override it; security forces it true (:1153); device/display/power clear it ONLY when every
		//     relevant field is unchanged (:857/:943/:922), which an import restoring a different profile
		//     does not satisfy, so treat them as rebooting.
		//   - LoRa clears it unconditionally on 2.8 (:1060), so set_config(lora) does not reboot there.
		//     BUT that change (firmware #9962) is develop-only and is in no released tag: on the shipped
		//     2.7.x line LoRa skips the reboot only when every radio field is unchanged, which restoring a
		//     profile does not satisfy. The flag is conservative, so .loraConfig is expected to reboot.
		//   - handleSetModuleConfig defaults `shouldReboot = true` (:1175); only statusmessage (:1275)
		//     and mesh_beacon (:1360) clear it. Note `tak` has no case at all, so it reboots and silently
		//     applies nothing.
		//   - set_owner saves with the default shouldReboot = true (:793), so it reboots.
		//   - set_channel (:1398) and set_fixed_position (:585) pass shouldReboot = false.
		//   - ringtone / canned-message text bypass AdminModule and write their proto directly
		//     (ExternalNotificationModule.handleSetRingtone, CannedMessageModule
		//      .handleSetCannedMessageModuleMessages), so neither reboots.
		// `mayReboot` is a conservative "may reboot" flag: the app cannot evaluate the firmware's
		// field-by-field diff for device/display/power, so it must assume the rebooting case.
		let expectedReboot: Set<ImportItemKind> = [
			.owner,
			.deviceConfig, .displayConfig, .positionConfig, .powerConfig,
			.networkConfig, .bluetoothConfig, .securityConfig,
			.mqtt, .serial, .externalNotification, .storeForward, .rangeTest, .telemetry,
			.cannedMessage, .audio, .neighborInfo, .ambientLighting, .detectionSensor,
			.paxcounter, .tak, .trafficManagement,
			.loraConfig
		]
		// Explicitly NOT rebooting on any firmware line: .statusMessage, .ringtone, .cannedMessagesText,
		// .fixedPosition, .channelURL. Note .channelURL was one of only two items the branch originally
		// flagged reboot-causing, and it is in fact the one item in the terminal step that never reboots.
		let presentKinds = Set(plan.items.map(\.kind))
		let rebootKinds = Set(plan.items.filter(\.mayReboot).map(\.kind))
		#expect(rebootKinds == expectedReboot.intersection(presentKinds))
		#expect(!rebootKinds.contains(.statusMessage))
		#expect(!rebootKinds.contains(.fixedPosition))

		let all = Set(plan.presentSections)
		#expect(plan.containsSensitive(in: all))
		#expect(plan.willReboot(in: all))
		// A selection with no security/network/MQTT/channel items is not sensitive.
		// (Modules is excluded because the MQTT module config carries a password.)
		let nonSensitive: Set<ImportSection> = [.owner, .radioAndDevice, .personalization, .fixedPosition]
		#expect(!plan.containsSensitive(in: nonSensitive))
		// It IS however a reboot: owner and every radioAndDevice config reboot on firmware 2.8. The user
		// must be warned even when importing only "safe-looking" sections.
		#expect(plan.willReboot(in: nonSensitive))
	}

	@Test("A channel URL terminal item is flagged sensitive because it carries channel PSKs")
	func channelURLIsSensitive() throws {
		var profile = try makeFullProfile()
		profile.channelURL = try channelURL()
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())
		let channelItem = try #require(plan.items.first { $0.kind == .channelURL })
		#expect(channelItem.isSensitive)
		// set_channel saves with shouldReboot = false (AdminModule.cpp:1398), so a channel URL does not
		// reboot the radio. The engine currently flags it as its terminal reboot step, which is wrong.
		#expect(!channelItem.mayReboot)
	}

	// MARK: - Owner merge

	@Test("Owner merge takes is_unmessagable from the profile when present, else keeps the node's")
	func ownerMergeAppliesUnmessagable() {
		var base = User()
		base.longName = "Old Name"
		base.shortName = "OLD"
		base.isUnmessagable = false

		// Present in the profile: the profile wins.
		var carries = DeviceProfile()
		carries.longName = "Base Camp"
		carries.isUnmessagable = true
		#expect(DeviceProfileImportPlan.ownerUser(from: carries, base: base).isUnmessagable)

		// Absent from the profile: the node's existing value is preserved.
		var silent = DeviceProfile()
		silent.longName = "Base Camp"
		var messagableBase = base
		messagableBase.isUnmessagable = true
		#expect(DeviceProfileImportPlan.ownerUser(from: silent, base: messagableBase).isUnmessagable)
		#expect(!DeviceProfileImportPlan.ownerUser(from: silent, base: base).isUnmessagable)
	}

	@Test("A profile carrying only is_unmessagable still yields an owner item")
	func unmessagableAloneYieldsOwnerItem() throws {
		var profile = DeviceProfile()
		profile.isUnmessagable = true
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: User())
		#expect(plan.items.map(\.kind) == [.owner])
	}

	@Test("Owner merge never takes is_licensed from the profile")
	func ownerMergeDoesNotLeakLicensedFlag() {
		var profile = DeviceProfile()
		profile.longName = "Base Camp"
		profile.shortName = "BC01"
		profile.isLicensed = true

		var base = User()
		base.longName = "Old Name"
		base.shortName = "OLD"
		base.isLicensed = false

		let merged = DeviceProfileImportPlan.ownerUser(from: profile, base: base)

		#expect(merged.longName == "Base Camp")
		#expect(merged.shortName == "BC01")
		// Enabling ham mode is a dedicated onboarding flow: set_ham_mode rewrites the owner, disables
		// encryption, and applies tx power/frequency. A plain set_owner would bypass all of that and leave
		// the node flagged licensed without the required side effects, so an imported profile must never
		// turn it on. Mirrors Android's InstallProfileUseCaseTest "never auto-installs is_licensed"
		// (InstallProfileUseCaseTest.kt:113) and the deliberate omission in its InstallProfileUseCase.
		#expect(!merged.isLicensed)
	}

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

	// MARK: - Security merge (partial import — the "keys" half)

	private func baseSecurity() -> Config.SecurityConfig {
		var base = Config.SecurityConfig()
		base.privateKey = Data([0xAA, 0xBB])
		base.publicKey = Data([0xCC, 0xDD])
		base.adminKey = [Data([0x01]), Data([0x02])]
		return base
	}

	@Test("A profile with no keypair keeps the node's identity keys but takes its flags")
	func securityMergePreservesKeysWhenAbsent() {
		var profile = Config.SecurityConfig()   // no keys — an event/"official" config
		profile.isManaged = true
		profile.adminChannelEnabled = true

		let merged = DeviceProfileImportPlan.securityConfig(from: profile, base: baseSecurity())
		#expect(merged.privateKey == Data([0xAA, 0xBB]))   // preserved
		#expect(merged.publicKey == Data([0xCC, 0xDD]))    // preserved
		#expect(merged.adminKey == [Data([0x01]), Data([0x02])])  // preserved
		#expect(merged.isManaged)                           // taken from the profile
		#expect(merged.adminChannelEnabled)                // taken from the profile
	}

	@Test("A profile that carries a keypair replaces the node's keys (full restore)")
	func securityMergeReplacesKeysWhenPresent() {
		var profile = Config.SecurityConfig()
		profile.privateKey = Data([0x11])
		profile.publicKey = Data([0x22])
		profile.adminKey = [Data([0x33])]

		let merged = DeviceProfileImportPlan.securityConfig(from: profile, base: baseSecurity())
		#expect(merged.privateKey == Data([0x11]))
		#expect(merged.publicKey == Data([0x22]))
		#expect(merged.adminKey == [Data([0x33])])
	}

	@Test("Each key field is preserved independently")
	func securityMergeIsPerField() {
		var profile = Config.SecurityConfig()
		profile.publicKey = Data([0x22])   // public present, private + admin absent

		let merged = DeviceProfileImportPlan.securityConfig(from: profile, base: baseSecurity())
		#expect(merged.publicKey == Data([0x22]))          // taken from profile
		#expect(merged.privateKey == Data([0xAA, 0xBB]))   // preserved
		#expect(merged.adminKey == [Data([0x01]), Data([0x02])])  // preserved
	}

	@Test("With no base config the profile's security is applied as-is")
	func securityMergeNoBaseAppliesAsIs() {
		var profile = Config.SecurityConfig()
		profile.isManaged = true
		let merged = DeviceProfileImportPlan.securityConfig(from: profile, base: nil)
		#expect(merged.privateKey.isEmpty)
		#expect(merged.publicKey.isEmpty)
		#expect(merged.isManaged)
	}

	@Test("The emitted security item carries the key-preserving payload and summary")
	func securityItemPreservesIdentity() throws {
		var security = Config.SecurityConfig()
		security.isManaged = true            // keypair intentionally left empty
		var config = LocalConfig()
		config.security = security
		var profile = DeviceProfile()
		profile.config = config

		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil, currentSecurity: baseSecurity())
		let item = try #require(plan.items.first { $0.kind == .securityConfig })
		guard case let .securityConfig(applied) = item.payload else {
			Issue.record("security item did not carry a .securityConfig payload")
			return
		}
		#expect(applied.privateKey == Data([0xAA, 0xBB]))   // node identity preserved
		#expect(applied.publicKey == Data([0xCC, 0xDD]))
		#expect(applied.isManaged)                           // flag from the profile applied
		#expect(item.summary == "Admin access & flags (keeps this node's keys)")
	}

	@Test("A profile that carries keys keeps the identity-rewrite summary")
	func securityItemRewriteSummaryWhenKeysPresent() throws {
		var security = Config.SecurityConfig()
		security.privateKey = Data([0x11])
		security.publicKey = Data([0x22])
		var config = LocalConfig()
		config.security = security
		var profile = DeviceProfile()
		profile.config = config

		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil, currentSecurity: baseSecurity())
		let item = try #require(plan.items.first { $0.kind == .securityConfig })
		#expect(item.summary == "Node identity, keys & admin access")
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
		var failOnBegin = false
		var failOnCommit = false
		/// Fired as the commit is sent, so a test can simulate the link dropping with it.
		var onCommit: (() -> Void)?
		/// Drops the connection right after this item is applied, simulating a mid-run teardown.
		var dropConnectionOn: ImportItemKind?
		/// Every gateway call in order, with the two transaction controls interleaved among the item
		/// kinds, so tests can assert the begin -> items -> commit -> deferred-items shape.
		var calls: [String] = []

		func beginEditSettings() async throws {
			calls.append("begin")
			if failOnBegin {
				throw NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "no transaction"])
			}
		}

		func commitEditSettings() async throws {
			calls.append("commit")
			onCommit?()
			if failOnCommit {
				throw NSError(domain: "test", code: 3, userInfo: [NSLocalizedDescriptionKey: "commit failed"])
			}
		}

		func apply(_ item: ImportItem) async throws {
			attempted.append(item.kind)
			calls.append(item.kind.rawValue)
			if item.kind == dropConnectionOn { isConnected = false }
			if item.kind == cancelOn {
				throw CancellationError()
			}
			if item.kind == failOn {
				throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"])
			}
		}
	}

	// MARK: - Edit transaction

	@MainActor
	@Test("The whole import is bracketed by begin/commit edit settings")
	func importIsWrappedInATransaction() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		profile.config = config
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.isCompleteSuccess)
		#expect(result.usedTransaction)
		#expect(result.transactionCommitted)
		#expect(gateway.calls.first == "begin")
		#expect(gateway.calls.last == "commit")
		#expect(gateway.calls == ["begin", "deviceConfig", "displayConfig", "commit"])
	}

	@MainActor
	@Test("MQTT and Serial are applied after the commit, outside the transaction")
	func mqttAndSerialRunAfterCommit() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config
		var module = LocalModuleConfig()
		module.mqtt = ModuleConfig.MQTTConfig()
		module.serial = ModuleConfig.SerialConfig()
		module.telemetry = ModuleConfig.TelemetryConfig()
		profile.moduleConfig = module
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		// Firmware disables Bluetooth for MQTT and Serial even inside a transaction
		// (AdminModule.cpp:1191, :1207), so they run last, after everything else is safely committed.
		#expect(result.isCompleteSuccess)
		#expect(gateway.calls == ["begin", "deviceConfig", "telemetry", "commit", "mqtt", "serial"])
		let commitIndex = try #require(gateway.calls.firstIndex(of: "commit"))
		let mqttIndex = try #require(gateway.calls.firstIndex(of: "mqtt"))
		let serialIndex = try #require(gateway.calls.firstIndex(of: "serial"))
		#expect(mqttIndex > commitIndex)
		#expect(serialIndex > commitIndex)
	}

	@MainActor
	@Test("A failure mid-transaction still commits so the radio is not stranded")
	func failureStillCommits() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		profile.config = config
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		gateway.failOn = .displayConfig
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		// The firmware has no abort message, so an uncommitted transaction would leave it deferring every
		// later write from any client. Commit must still be sent on the failure path.
		#expect(result.failed?.kind == .displayConfig)
		#expect(gateway.calls.contains("commit"))
		#expect(result.transactionCommitted)
	}

	@MainActor
	@Test("A radio that refuses the transaction fails the run without sending any item")
	func beginFailureAbortsRun() async throws {
		let plan = try DeviceProfileImportPlan(profile: makeFullProfile(), currentUser: User())

		let gateway = MockGateway()
		gateway.failOnBegin = true
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(!result.usedTransaction)
		#expect(result.failed != nil)
		#expect(gateway.attempted.isEmpty)
		#expect(result.applied.isEmpty)
	}

	@MainActor
	@Test("A commit that drops with the link counts as committed, not failed")
	func commitDropDuringRebootIsNotAFailure() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		gateway.failOnCommit = true
		gateway.isConnected = true
		// The commit disables Bluetooth and reboots, so the ack is lost as the link drops.
		gateway.onCommit = { gateway.isConnected = false }
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.applied == [.deviceConfig])
		#expect(result.transactionCommitted)
		#expect(result.failed == nil)
	}

	@MainActor
	@Test("When the commit tears down the link, MQTT and Serial need a reconnect rather than failing")
	func deferredItemsNeedReconnectAfterTeardown() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		profile.config = config
		var module = LocalModuleConfig()
		module.mqtt = ModuleConfig.MQTTConfig()
		module.serial = ModuleConfig.SerialConfig()
		profile.moduleConfig = module
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		// Mirrors BLE: commit_edit_settings calls disableBluetooth(), a hard synchronous teardown
		// (AdminModule.cpp:2324), so the transport is gone before the post-commit items can be sent.
		gateway.onCommit = { gateway.isConnected = false }
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.transactionCommitted)
		#expect(result.applied == [.deviceConfig])
		// Not failures: everything else is already committed, these just need a second pass.
		#expect(result.failed == nil)
		#expect(result.requiresReconnect == [.mqtt, .serial])
		#expect(!gateway.attempted.contains(.mqtt))
		#expect(!gateway.attempted.contains(.serial))
	}

	@MainActor
	@Test("A commit sent into an already-dead link is unconfirmed, not committed")
	func commitIntoDeadLinkIsUnconfirmed() async throws {
		var profile = DeviceProfile()
		var config = LocalConfig()
		config.device = Config.DeviceConfig()
		config.display = Config.DisplayConfig()
		profile.config = config
		let plan = try DeviceProfileImportPlan(profile: profile, currentUser: nil)

		let gateway = MockGateway()
		// The link dies mid-run, so the commit never reaches the radio and it keeps an open transaction.
		gateway.dropConnectionOn = .deviceConfig
		gateway.failOnCommit = true
		let result = await DeviceProfileImporter.apply(
			plan: plan,
			selection: Set(plan.presentSections),
			gateway: gateway
		)

		#expect(result.applied == [.deviceConfig])
		#expect(result.failed?.kind == .displayConfig)
		// The radio may still be holding the transaction open, so we must not claim it committed.
		#expect(!result.transactionCommitted)
		#expect(result.commitUnconfirmed)
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
	@Test("Reboot reporting follows the firmware contract, not the plan's terminal step")
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
		// Both the device config (AdminModule.cpp:840) and, on shipped 2.7.x firmware, the LoRa config
		// reboot, so this plan reports rebooting. Before the flags were corrected this passed because
		// LoRa was the ONLY item flagged, which happened to give the same answer for the wrong reason.
		#expect(result.rebooting)

		// The per-item flag is still per-item at the PLAN level, but a RUN now always ends in a reboot:
		// commit_edit_settings saves every segment and reboots (AdminModule.cpp:473-478). So a
		// personalization-only plan carries no reboot-causing item, yet still reboots once at the commit.
		var ringtoneOnly = DeviceProfile()
		ringtoneOnly.ringtone = "a:d=4,o=5,b=100:c"
		let ringtonePlan = try DeviceProfileImportPlan(profile: ringtoneOnly, currentUser: nil)
		let ringtoneResult = await DeviceProfileImporter.apply(
			plan: ringtonePlan,
			selection: Set(ringtonePlan.presentSections),
			gateway: MockGateway()
		)
		#expect(ringtoneResult.isCompleteSuccess)
		#expect(ringtoneResult.applied == [.ringtone])
		// No individual item in this plan reboots...
		#expect(!ringtonePlan.willReboot(in: Set(ringtonePlan.presentSections)))
		// ...but the transaction commit does, so the run reports rebooting anyway.
		#expect(ringtoneResult.rebooting)
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
		// The cancel may or may not land before the loop starts, but either way the run must stay coherent:
		// nothing is reported as failed, and every item is accounted for as applied or skipped.
		#expect(result.failed == nil)
		#expect(result.applied.count + result.skipped.count == plan.items.count)
		// A cancelled run is never reported as a complete success.
		if result.wasCancelled {
			#expect(!result.isCompleteSuccess)
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
		// The channel URL never applied, so it contributed no reboot of its own. Assert that directly
		// rather than via `rebooting`: that flag is true here because the device config applied before it
		// does reboot on firmware 2.8 (AdminModule.cpp:840), which is precisely why `rebooting` cannot be
		// used as a proxy for "the terminal step succeeded".
		#expect(result.applied == [.deviceConfig])
		#expect(!result.applied.contains(.channelURL))
	}
}
