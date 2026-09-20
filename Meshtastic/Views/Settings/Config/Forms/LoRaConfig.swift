//
//  LoRaConfig.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 9/19/26.
//
import SwiftUI
import OSLog
import MeshtasticProtobufs

/// A region this app knows how to write back. A radio reporting one from newer firmware
/// has no entry here, and saving would turn it into something else.
enum LoRaRegionValidation {
	static func supportedRegion(rawValue: Int) -> RegionCodes? {
		RegionCodes(rawValue: rawValue)
	}
}

extension Config.LoRaConfig: ConfigFormMessage {
	static let entityKeyPath: KeyPath<NodeInfoEntity, LoRaConfigEntity?> = \NodeInfoEntity.loRaConfig

	init(entity: LoRaConfigEntity) {
		self.init()
		usePreset = entity.usePreset
		modemPreset = ModemPreset(rawValue: Int(entity.modemPreset)) ?? .longFast
		bandwidth = UInt32(truncatingIfNeeded: entity.bandwidth)
		spreadFactor = UInt32(truncatingIfNeeded: entity.spreadFactor)
		codingRate = UInt32(truncatingIfNeeded: entity.codingRate)
		region = RegionCode(rawValue: Int(entity.regionCode)) ?? .unset
		hopLimit = UInt32(truncatingIfNeeded: entity.hopLimit)
		txEnabled = entity.txEnabled
		txPower = entity.txPower
		channelNum = UInt32(truncatingIfNeeded: entity.channelNum)
		overrideDutyCycle = entity.overrideDutyCycle
		paFanDisabled = entity.paFanDisabled
		sx126XRxBoostedGain = entity.sx126xRxBoostedGain
		overrideFrequency = entity.overrideFrequency
		ignoreMqtt = entity.ignoreMqtt
		configOkToMqtt = entity.okToMqtt
		frequencyOffset = entity.frequencyOffset
	}
}

struct LoRaConfig: View {
	@Environment(\.modelContext) private var context
	@EnvironmentObject private var accessoryManager: AccessoryManager
	let node: NodeInfoEntity?
	/// Connect.swift follows a successful save to re-read the channel it just moved to.
	let onSuccessfulSave: (_ nodeNum: Int64, _ region: RegionCodes) -> Void

	init(
		node: NodeInfoEntity?,
		onSuccessfulSave: @escaping (_ nodeNum: Int64, _ region: RegionCodes) -> Void = { _, _ in }
	) {
		self.node = node
		self.onSuccessfulSave = onSuccessfulSave
	}

	private typealias F = Config.LoRaConfig.Fields

	/// Repeated, so the generator emits no typed descriptor. The erased one carries the
	/// identity settings search needs to know this screen deliberately does not show it.
	private static var ignoreIncomingField: AnyConfigField<Config.LoRaConfig> {
		Config.LoRaConfig.allFields.first { $0.tag == 103 }!
	}

	/// A region this app does not know cannot be written back: it would be saved as
	/// something else. Save stays disabled until a supported one is chosen.
	static func supportedRegion(_ config: Config.LoRaConfig) -> RegionCodes? {
		LoRaRegionValidation.supportedRegion(rawValue: config.region.rawValue)
	}

	static func canSave(_ config: Config.LoRaConfig, node: NodeInfoEntity?) -> Bool {
		guard supportedRegion(config) != nil else { return false }
		guard !config.usePreset else { return true }
		return Bandwidths.validationIssue(
			for: Int(config.bandwidth),
			region: RegionCodes(rawValue: config.region.rawValue),
			pioEnv: node?.myInfo?.pioEnv) == nil
	}

	/// The boards whose firmware drives a PA fan from a GPIO: the four variants that
	/// define `RF95_FAN_EN`. Nothing in the device catalog records a fan, and the radio
	/// does not report one, so the list is the only way to ask. Anywhere else the toggle
	/// would write a field no firmware reads.
	static let paFanHardware: Set<Int32> = [
		Int32(HardwareModel.betafpv2400Tx.rawValue),
		Int32(HardwareModel.radiomaster900BanditNano.rawValue),
		Int32(HardwareModel.radiomaster900Bandit.rawValue),
		Int32(HardwareModel.tbeam1Watt.rawValue)
	]

	static func overlay(node: NodeInfoEntity? = nil) -> ConfigFormOverlay<Config.LoRaConfig> {
		let custom = ConfigFormCondition<Config.LoRaConfig>.isFalse(F.usePreset)
		// Hidden on hardware the app has not identified, the same as the other rows that
		// turn on something the schema cannot see.
		let hasPAFan = ConfigFormCondition<Config.LoRaConfig>.environment { env in
			guard let hwModel = env.node?.user?.hwModelId else { return false }
			return paFanHardware.contains(hwModel)
		}
		return .init(sections: [
			.init(title: String(localized: "Options", comment: "Settings section"), fields: [
				// Custom for the notices that sit with them: a region this app cannot save,
				// and a band restricted to licensed operators. Both are about the choice
				// being made, so they belong beside the picker rather than at the foot of
				// the screen.
				.init(F.region, control: .custom { config in AnyView(RegionRow(config: config, node: node)) }),
				.init(F.usePreset, symbol: "list.bullet.rectangle"),
				.init(F.modemPreset, shownWhen: .isTrue(F.usePreset),
					  control: .custom { config in AnyView(ModemPresetRow(config: config, node: node)) })
			]),
			.init(title: String(localized: "Advanced", comment: "Settings section"), fields: [
				.init(F.ignoreMqtt, symbol: "server.rack"),
				.init(F.configOkToMqtt, symbol: "network"),
				.init(F.txEnabled, symbol: "waveform.path"),
				// Only when a preset is not doing the work.
				.init(F.bandwidth, shownWhen: custom,
					  control: .custom { config in AnyView(BandwidthRow(config: config, node: node)) }),
				.init(F.spreadFactor, shownWhen: custom,
					  control: .options((7..<13).map { ConfigFormOption(value: $0 == 12 ? 0 : $0, title: "\($0)") })),
				// Follow the preset, or override it, with the range the preset allows.
				.init(F.codingRate, control: .custom { config in AnyView(CodingRateRows(config: config)) }),
				.init(F.hopLimit, control: .options((1..<8).map { ConfigFormOption(value: $0, title: "\($0)") })),
				// A frequency override replaces the slot, so the slot stops applying.
				.init(F.channelNum, enabledWhen: .equals(F.overrideFrequency, 0)),
				.init(F.sx126XRxBoostedGain, symbol: "waveform.badge.plus"),
				// Transmitting past the region's duty cycle is the operator's responsibility,
				// so the radio wants it asked for explicitly rather than assumed.
				.init(F.overrideDutyCycle, symbol: "clock.arrow.2.circlepath"),
				.init(F.paFanDisabled, symbol: "fan", shownWhen: hasPAFan),
				.init(F.overrideFrequency, symbol: "waveform.path.ecg", control: .preciseDecimal)
			])
		], omitted: [
			.init(F.txPower, "set by the radio for the region and preset; not offered by this client"),
			// A repeated list of node numbers to ignore, with no editor on any client.
			.init(Self.ignoreIncomingField, "a repeated node list; not offered by this client"),
			.init(F.frequencyOffset, "not offered by this client; unlabelled upstream"),
			.init(F.femLnaMode, "not offered by this client; unlabelled upstream"),
			.init(F.serialHalOnly, "not offered by this client; unlabelled upstream")
		])
	}

	var body: some View {
		MetadataConfigForm(
			node: node, title: "LoRa", overlay: Self.overlay(node: node),
			canSave: { Self.canSave($0, node: node) },
			confirmationMessage: String(localized: "Your device may reboot after saving.",
										comment: "LoRa save confirmation"),
			request: accessoryManager.requestLoRaConfig,
			save: { config, from, to in
				guard let region = Self.supportedRegion(config) else { return }
				// Read the stored settings before the save: the radio reboots on a LoRa
				// write and echoes the new config back, so afterwards there is nothing
				// left to compare against.
				let previous = node?.loRaConfig.map {
					LoRaChannelSettings(
						regionCode: $0.regionCode, modemPreset: $0.modemPreset, usePreset: $0.usePreset,
						channelNum: $0.channelNum, overrideFrequency: $0.overrideFrequency,
						bandwidth: $0.bandwidth, spreadFactor: $0.spreadFactor, codingRate: $0.codingRate)
				}
				let updated = LoRaChannelSettings(
					regionCode: Int32(config.region.rawValue), modemPreset: Int32(config.modemPreset.rawValue),
					usePreset: config.usePreset, channelNum: Int32(config.channelNum),
					overrideFrequency: config.overrideFrequency, bandwidth: Int32(config.bandwidth),
					spreadFactor: Int32(config.spreadFactor), codingRate: Int32(config.codingRate))

				if let deviceNum = accessoryManager.activeDeviceNum,
				   let connectedNode = getNodeInfo(id: deviceNum, context: context),
				   connectedNode.num == node?.user?.num ?? 0 {
					UserDefaults.modemPreset = config.modemPreset.rawValue
				}

				_ = try await accessoryManager.saveLoRaConfig(config: config, fromUser: from, toUser: to)

				// Only when the radio actually moved channel, and only for a change made
				// here. The beacon join flow writes the same config to follow a mesh it has
				// just found, where every node is expected to be on the old channel.
				if let previous, updated.movesOffChannel(from: previous), let targetNum = node?.user?.num {
					LoRaConfigChange.recordChange(forNode: targetNum)
					Logger.mesh.info("📡 LoRa settings moved node \(targetNum.toHex(), privacy: .public) to a different channel; flagging nodes not heard since")
				}
				onSuccessfulSave(to.num, region)
			})
		.navigationTitle("LoRa Config")
	}
}

/// The region picker, with the two notices that belong beside it: a region this app
/// cannot save, and a band restricted to licensed operators.
private struct RegionRow: View {
	@Binding var config: Config.LoRaConfig
	let node: NodeInfoEntity?
	@EnvironmentObject private var accessoryManager: AccessoryManager

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.LoRaConfig", tag: 7)

	/// The 2.8 rework added ham and narrow-band regions. Older firmware has no band table
	/// for them, so they are not offered there.
	private var supports2_8: Bool { accessoryManager.checkIsVersionSupported(forVersion: "2.8.0") }

	private var selection: Binding<Int> {
		Binding(get: { config.region.rawValue },
				set: { if let region = Config.LoRaConfig.RegionCode(rawValue: $0) { config.region = region } })
	}

	private var presetInfo: RegionPresetInfo? {
		guard supports2_8, let code = RegionCodes(rawValue: config.region.rawValue)?.protoEnumValue() else { return nil }
		return accessoryManager.loRaRegionPresets[code]
	}

	var body: some View {
		VStack(alignment: .leading) {
			Picker(Self.metadata?.label ?? "Region", selection: selection) {
				ForEach(RegionCodes.selectable(supports2_8: supports2_8)) { region in
					Text(region.description).tag(region.rawValue)
				}
			}
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundColor(.gray)
					.font(.callout)
			}
			if LoRaRegionValidation.supportedRegion(rawValue: config.region.rawValue) == nil {
				Label("This radio uses a newer region that this app does not support. Choose a supported region before saving.",
					  systemImage: "exclamationmark.triangle.fill")
					.foregroundStyle(.orange)
					.font(.callout)
			}
		}
		if let info = presetInfo, info.licensedOnly {
			LicensedBandNotice(isLicensed: node?.user?.isLicensed ?? false)
		}
	}
}

/// Shown for a band only licensed amateur operators may transmit on.
private struct LicensedBandNotice: View {
	let isLicensed: Bool

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: isLicensed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
				.foregroundColor(isLicensed ? .green : .orange)
				// Decorative: the title and text below say the same thing.
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 2) {
				Text("Licensed band").font(.callout).bold()
				// Each branch localized separately: a ternary of two literals is a String,
				// and Text would then render it verbatim, skipping the catalog.
				Text(isLicensed
					 ? String(localized: "This region is restricted to licensed amateur radio operators. Your operator profile is marked as licensed.",
							  comment: "Licensed band notice, operator is licensed")
					 : String(localized: "This region is restricted to licensed amateur radio operators. Enable \u{201C}Licensed Operator\u{201D} and set your call sign in User Config before transmitting.",
							  comment: "Licensed band notice, operator is not licensed"))
					.foregroundColor(.gray)
					.font(.caption)
			}
		}
	}
}

/// The modem preset, constrained to what the region allows. The legal set depends on
/// the region chosen in this same message and on a map the radio advertises, neither of
/// which the schema can state.
private struct ModemPresetRow: View {
	@Binding var config: Config.LoRaConfig
	let node: NodeInfoEntity?
	@EnvironmentObject private var accessoryManager: AccessoryManager

	private static let metadata = FieldMetadataRegistry.get("meshtastic.Config.LoRaConfig", tag: 2)

	private var supports2_8: Bool { accessoryManager.checkIsVersionSupported(forVersion: "2.8.0") }

	private var selection: Binding<Int> {
		Binding(get: { config.modemPreset.rawValue },
				set: { if let preset = Config.LoRaConfig.ModemPreset(rawValue: $0) { config.modemPreset = preset } })
	}

	private var available: [ModemPresets] {
		var base = ModemPresets.selectable(supports2_8: supports2_8)
		// The EU band plans cap bandwidth below what Turbo uses, so those are not offered
		// at all there rather than offered with a warning.
		if RegionCodes(rawValue: config.region.rawValue)?.prohibitsTurboPresets == true {
			base = base.filter { !$0.isTurbo }
		}
		var presets = base
		if supports2_8,
		   let code = RegionCodes(rawValue: config.region.rawValue)?.protoEnumValue(),
		   let info = accessoryManager.loRaRegionPresets[code], !info.presets.isEmpty {
			let constrained = base.filter { info.presets.contains($0.protoEnumValue()) }
			if !constrained.isEmpty { presets = constrained }
		}
		// Whatever the radio is actually set to stays visible, whether it was filtered out
		// for being deprecated or for being Turbo in a region that forbids it. Otherwise
		// the picker renders blank and the user cannot see what their radio is on, let
		// alone that it is the thing they are being steered away from.
		if let current = ModemPresets(rawValue: config.modemPreset.rawValue), !presets.contains(current) {
			presets.append(current)
		}
		return presets
	}

	var body: some View {
		VStack(alignment: .leading) {
			Picker(Self.metadata?.label ?? "Presets", selection: selection) {
				ForEach(available) { preset in
					Text(preset.description).tag(preset.rawValue)
				}
			}
			.fixedSize()
			if let description = Self.metadata?.description {
				Text(description)
					.foregroundColor(.gray)
					.font(.callout)
			}
			// Every non-Turbo preset stays selectable in the US, but none of their
			// bandwidths is US-compliant on 2.8 - warn rather than block.
			if supports2_8,
			   config.region.rawValue == RegionCodes.us.rawValue,
			   let preset = ModemPresets(rawValue: config.modemPreset.rawValue), !preset.isTurbo {
				Label {
					Text("\(preset.description)'s bandwidth is not compliant in the US. The Turbo presets are recommended.")
						.foregroundColor(.gray)
						.font(.caption)
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
				}
			}
		}
	}
}

/// Bandwidth, when a preset is not setting it. The legal set depends on the region and
/// on the board's build environment.
private struct BandwidthRow: View {
	@Binding var config: Config.LoRaConfig
	let node: NodeInfoEntity?

	private var region: RegionCodes? { RegionCodes(rawValue: config.region.rawValue) }

	private var selection: Binding<Int> {
		Binding(
			get: { Bandwidths.pickerValue(forStoredValue: Int(config.bandwidth), region: region) },
			set: { config.bandwidth = UInt32(truncatingIfNeeded: $0) })
	}

	var body: some View {
		CustomBandwidthPicker(
			selection: selection,
			options: Bandwidths.selectable(region: region, pioEnv: node?.myInfo?.pioEnv),
			region: region,
			validationIssue: Bandwidths.validationIssue(
				for: Int(config.bandwidth), region: region, pioEnv: node?.myInfo?.pioEnv))
	}
}

/// Coding rate: follow the preset, or override it within the range the preset leaves.
/// A preset already at the highest redundancy has nothing to override.
private struct CodingRateRows: View {
	@Binding var config: Config.LoRaConfig

	private var preset: ModemPresets { ModemPresets(rawValue: config.modemPreset.rawValue) ?? .longFast }
	private var normalized: Int {
		CodingRates.normalized(Int(config.codingRate), usePreset: config.usePreset, modemPreset: preset)
	}
	private var presetDefault: Int { preset.defaultCodingRate }
	private var canOverride: Bool { presetDefault < CodingRates.validRange.upperBound }

	private var followsPreset: Binding<Bool> {
		Binding(
			get: { normalized == 0 },
			set: { useDefault in
				config.codingRate = useDefault || !canOverride ? 0 : UInt32(presetDefault + 1)
			})
	}

	private var value: Binding<Double> {
		Binding(get: { Double(normalized == 0 ? presetDefault : normalized) },
				set: { config.codingRate = UInt32($0) })
	}

	var body: some View {
		VStack(alignment: .leading) {
			Text("Coding Rate")
			Text(CodingRates.description(for: normalized, modemPreset: preset))
				.foregroundColor(.gray)
				.font(.callout)
			if config.usePreset {
				Toggle("Follow Preset Coding Rate", isOn: followsPreset)
					.disabled(!canOverride)
				if !canOverride {
					Text("This preset already uses 4/\(presetDefault), the highest redundancy available.")
						.foregroundColor(.gray)
						.font(.caption)
				} else if normalized == 0 {
					Text("Uses \(preset.description)'s 4/\(presetDefault) coding rate. Turn this off to raise it.")
						.foregroundColor(.gray)
						.font(.caption)
				} else {
					Slider(value: value,
						   in: Double(presetDefault + 1)...Double(CodingRates.validRange.upperBound), step: 1) {
						Text("Coding Rate")
					} minimumValueLabel: {
						Text("4/\(presetDefault + 1)")
					} maximumValueLabel: {
						Text("4/\(CodingRates.validRange.upperBound)")
					}
					Text("Uses 4/\(normalized) while keeping the \(preset.description) bandwidth and spread factor.")
						.foregroundColor(.gray)
						.font(.caption)
				}
			} else {
				Slider(value: value,
					   in: Double(CodingRates.validRange.lowerBound)...Double(CodingRates.validRange.upperBound), step: 1) {
					Text("Coding Rate")
				} minimumValueLabel: {
					Text("4/\(CodingRates.validRange.lowerBound)")
				} maximumValueLabel: {
					Text("4/\(CodingRates.validRange.upperBound)")
				}
				Text("Coding rate controls error-correction redundancy. Higher values can help noisy links, but reduce throughput.")
					.foregroundColor(.gray)
					.font(.caption)
			}
		}
	}
}

private struct CustomBandwidthPicker: View {
	@Binding var selection: Int
	let options: [Bandwidths]
	let region: RegionCodes?
	let validationIssue: Bandwidths.ValidationIssue?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Picker("Bandwidth", selection: $selection) {
				if validationIssue == .unsupported {
					Text("Unsupported (\(Bandwidths.description(forPickerValue: selection, region: region)))")
						.tag(selection)
				}
				if region == .lora24 {
					Text(Bandwidths.description(forPickerValue: 0, region: region).localized)
						.tag(0)
				}
				ForEach(options) { bandwidth in
					Text(bandwidth.description)
						.tag(bandwidth.pickerValue)
				}
			}
			if let validationIssue {
				Label {
					if validationIssue == .unsupported {
						Text("This bandwidth is not supported by the connected radio in the selected region. Choose a supported value before saving.".localized)
					}
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill")
				}
				.foregroundStyle(.orange)
				.font(.callout)
			}
		}
	}
}
