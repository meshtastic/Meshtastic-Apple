//
//  LoRaChannelCalculator.swift
//  Meshtastic
//
//  Firmware-accurate LoRa frequency-slot derivation, shared between the Channels
//  editor (frequency summary) and the Mesh Beacons join enhancement (Add-vs-Switch).
//
//  The slot math mirrors the firmware's `channel_num` name-hash: region + preset
//  bandwidth determine the number of channels, then the primary channel name is
//  hashed (djb2) into a 1-based slot when `channel_num == 0`.
//

import Foundation

/// Derives a radio's operating frequency slot and frequency the way the firmware does.
/// Moved out of `Channels.swift` (was `private struct`) so the Mesh Beacons join
/// enhancement can reuse the exact same math instead of hand-rolling a second hash.
struct LoRaChannelCalculator {
	private let regionCode: Int
	private let usePreset: Bool
	private let modemPreset: Int
	private let channelNum: Int
	private let bandwidth: Int
	private let overrideFrequency: Double
	private let frequencyOffset: Double

	init(config: LoRaConfigEntity?) {
		regionCode = Int(config?.regionCode ?? 0)
		usePreset = config?.usePreset ?? false
		modemPreset = Int(config?.modemPreset ?? 0)
		channelNum = Int(config?.channelNum ?? 0)
		bandwidth = Int(config?.bandwidth ?? 0)
		overrideFrequency = Double(config?.overrideFrequency ?? 0)
		frequencyOffset = Double(config?.frequencyOffset ?? 0)
	}

	init(
		regionCode: Int,
		usePreset: Bool,
		modemPreset: Int,
		channelNum: Int,
		bandwidth: Int,
		overrideFrequency: Double,
		frequencyOffset: Double = 0
	) {
		self.regionCode = regionCode
		self.usePreset = usePreset
		self.modemPreset = modemPreset
		self.channelNum = channelNum
		self.bandwidth = bandwidth
		self.overrideFrequency = overrideFrequency
		self.frequencyOffset = frequencyOffset
	}

	private var region: RegionInfo? {
		RegionInfo(regionCode: regionCode)
	}

	var regionName: String {
		guard let regionCode = RegionCodes(rawValue: regionCode) else {
			return "Unknown region"
		}
		return regionCode.description
	}

	/// The radio's current operating slot. Respects a non-zero `channelNum` override
	/// (the firmware pins the slot when set); otherwise derives it from the primary
	/// channel name.
	func effectiveChannelSlot(primaryName: String) -> Int {
		if channelNum != 0 {
			return channelNum
		}
		if let defaultSlot = region?.defaultSlot, defaultSlot > 0 {
			return defaultSlot
		}
		let numChannels = numChannels()
		guard numChannels > 0 else { return 0 }
		return Int(djb2Hash(primaryName) % UInt32(numChannels)) + 1
	}

	/// The slot a channel with `name` would operate on. Regions with a firmware default
	/// slot use that default when a beacon does not carry an explicit channel number;
	/// other regions derive the slot from the name. This is the slot a beacon's offered
	/// channel resolves to on its own mesh, used to decide whether the connected radio
	/// (whose slot comes from `effectiveChannelSlot`) can already hear it.
	func slotForChannelName(_ name: String) -> Int {
		if let defaultSlot = region?.defaultSlot, defaultSlot > 0 {
			return defaultSlot
		}
		let numChannels = numChannels()
		return numChannels > 0 ? Int(djb2Hash(name) % UInt32(numChannels)) + 1 : 0
	}

	func radioFrequencyMHz(slot: Int) -> Double {
		if overrideFrequency != 0 {
			return overrideFrequency + frequencyOffset
		}
		guard let region else { return 0 }
		let bandwidthMHz = bandwidthMHz(region: region)
		guard bandwidthMHz > 0, slot > 0 else { return 0 }
		let slotWidth = region.spacing + 2 * region.padding + bandwidthMHz
		return region.freqStart + bandwidthMHz / 2 + region.padding + Double(slot - 1) * slotWidth + frequencyOffset
	}

	private func numChannels() -> Int {
		guard let region else { return 0 }
		let bandwidthMHz = bandwidthMHz(region: region)
		guard bandwidthMHz > 0 else { return 1 }
		let slotWidth = region.spacing + 2 * region.padding + bandwidthMHz
		return max(Int(((region.freqEnd - region.freqStart + region.spacing) / slotWidth).rounded()), 1)
	}

	private func bandwidthMHz(region: RegionInfo) -> Double {
		if usePreset {
			let presetBandwidth = ModemPresets(rawValue: modemPreset)?.bandwidthMHz ?? 0
			return presetBandwidth * (region.wideLoRa ? 3.25 : 1)
		}
		switch bandwidth {
		case 31:
			return 0.03125
		case 62:
			return 0.0625
		case 200:
			return 0.203125
		case 400:
			return 0.40625
		case 800:
			return 0.8125
		case 1600:
			return 1.625
		default:
			return Double(bandwidth) / 1000
		}
	}

	private func djb2Hash(_ name: String) -> UInt32 {
		var hash: UInt32 = 5381
		for scalar in name.unicodeScalars {
			hash = hash &+ (hash << 5) &+ UInt32(scalar.value)
		}
		return hash
	}
}

// MARK: - Beacon Add-vs-Switch decision (FR-016/FR-017)

/// Which join action a beacon-advertised channel supports on the connected radio.
enum BeaconJoinOption {
	/// The offered mesh already runs on the radio's current preset, region, and frequency
	/// slot — it can be added to a free secondary slot with no retune and no reboot.
	case add
	/// A retune (different slot / preset / region) is required — only Switch (reboot) applies.
	case switchOnly
	/// The beacon advertised no channel, or no radio is connected — no join action.
	case none
}

extension LoRaChannelCalculator {
	/// Pure Add-vs-Switch decision (contract C6, FR-016/FR-017). Extracted so it can be unit
	/// tested independently of SwiftUI / the accessory manager.
	///
	/// - Returns `.none` when the beacon offered no channel or no radio is connected.
	/// - Returns `.add` only when the offered preset + region match the radio **and** the
	///   offered channel resolves to the radio's current operating frequency slot.
	/// - Returns `.switchOnly` for any mismatch (or when the LoRa config isn't available to verify).
	static func beaconJoinOption(
		hasOfferChannel: Bool,
		offerChannelName: String,
		offeredPreset: ModemPresets?,
		offerRegion: Int,
		isConnected: Bool,
		loRaConfig: LoRaConfigEntity?,
		primaryChannelName: String
	) -> BeaconJoinOption {
		// No channel to join, or nothing to join it with.
		guard hasOfferChannel, !offerChannelName.isEmpty, isConnected else { return .none }
		// Connected but the LoRa config hasn't synced — Switch is still valid, but we can't
		// verify the slot for Add, so never offer Add.
		guard let config = loRaConfig else { return .switchOnly }

		let presetOK = offeredPreset != nil && offeredPreset == ModemPresets(rawValue: Int(config.modemPreset))
		// offerRegion == 0 means the beacon didn't advertise a region, so it can't be a mismatch.
		let regionOK = offerRegion == 0 || offerRegion == Int(config.regionCode)

		let calculator = LoRaChannelCalculator(config: config)
		let radioSlot = calculator.effectiveChannelSlot(primaryName: primaryChannelName)
		let beaconSlot = calculator.slotForChannelName(offerChannelName)

		if presetOK && regionOK && radioSlot == beaconSlot {
			return .add
		}
		return .switchOnly
	}
}

// MARK: - Channel frequency summary (used by the Channels editor)

/// A compact region / frequency / slot summary for the connected radio's primary channel.
/// Moved here alongside the calculator it depends on.
struct ChannelFrequencySummary {
	let frequencyText: String
	let slotText: String
	let regionName: String

	init?(loRaConfig: LoRaConfigEntity?, primaryChannelName: String) {
		guard let loRaConfig else {
			return nil
		}
		let calculator = LoRaChannelCalculator(config: loRaConfig)
		let slot = calculator.effectiveChannelSlot(primaryName: primaryChannelName)
		let frequency = calculator.radioFrequencyMHz(slot: slot)
		if frequency > 0 {
			frequencyText = String(format: "%.3f MHz", frequency)
		} else {
			frequencyText = "Unknown"
		}
		slotText = slot > 0 ? String(slot) : "Auto"
		regionName = calculator.regionName
	}
}

// MARK: - Region frequency bounds

/// Region frequency band + wide-LoRa flag used to compute bandwidth and slot count.
struct RegionInfo {
	let freqStart: Double
	let freqEnd: Double
	let wideLoRa: Bool
	let spacing: Double
	let padding: Double
	let defaultSlot: Int

	init?(regionCode: Int) {
		guard let region = RegionCodes(rawValue: regionCode) else { return nil }
		switch region {
		case .us, .unset:
			self.init(freqStart: 902.0, freqEnd: 928.0)
		case .eu433:
			self.init(freqStart: 433.0, freqEnd: 434.0)
		case .eu868:
			self.init(freqStart: 869.4, freqEnd: 869.65)
		case .cn:
			self.init(freqStart: 470.0, freqEnd: 510.0)
		case .jp:
			self.init(freqStart: 920.5, freqEnd: 923.5)
		case .anz:
			self.init(freqStart: 915.0, freqEnd: 928.0)
		case .kr:
			self.init(freqStart: 920.0, freqEnd: 923.0)
		case .tw:
			self.init(freqStart: 920.0, freqEnd: 925.0)
		case .ru:
			self.init(freqStart: 868.7, freqEnd: 869.2)
		case .in:
			self.init(freqStart: 865.0, freqEnd: 867.0)
		case .nz865:
			self.init(freqStart: 864.0, freqEnd: 868.0)
		case .th:
			self.init(freqStart: 920.0, freqEnd: 925.0)
		case .ua433:
			self.init(freqStart: 433.0, freqEnd: 434.7)
		case .ua868:
			self.init(freqStart: 868.0, freqEnd: 868.6)
		case .my433:
			self.init(freqStart: 433.0, freqEnd: 435.0)
		case .my919:
			self.init(freqStart: 919.0, freqEnd: 924.0)
		case .sg923:
			self.init(freqStart: 917.0, freqEnd: 925.0)
		case .ph433:
			self.init(freqStart: 433.0, freqEnd: 434.7)
		case .ph868:
			self.init(freqStart: 868.0, freqEnd: 869.4)
		case .ph915:
			self.init(freqStart: 915.0, freqEnd: 918.0)
		case .lora24:
			self.init(freqStart: 2400.0, freqEnd: 2483.5, wideLoRa: true)
		case .anz433:
			self.init(freqStart: 433.05, freqEnd: 434.79)
		case .kz433:
			self.init(freqStart: 433.075, freqEnd: 434.775)
		case .kz863:
			self.init(freqStart: 863.0, freqEnd: 868.0, wideLoRa: true)
		case .np865:
			self.init(freqStart: 865.0, freqEnd: 868.0)
		case .br902:
			self.init(freqStart: 902.0, freqEnd: 907.5)
		case .itu12M:
			self.init(freqStart: 144.0, freqEnd: 146.0, padding: 0.0022, defaultSlot: 26)
		case .itu22M:
			self.init(freqStart: 144.0, freqEnd: 148.0, padding: 0.0022, defaultSlot: 51)
		case .eu866:
			self.init(freqStart: 865.6, freqEnd: 867.6, spacing: 0.4, padding: 0.0375)
		case .eu874:
			self.init(freqStart: 873.0, freqEnd: 876.0)
		case .eu917:
			self.init(freqStart: 917.0, freqEnd: 921.0)
		case .euN868:
			self.init(freqStart: 869.4, freqEnd: 869.65, padding: 0.0104, defaultSlot: 1)
		case .itu32M:
			self.init(freqStart: 144.0, freqEnd: 148.0, padding: 0.0022, defaultSlot: 33)
		case .itu170Cm:
			self.init(freqStart: 430.0, freqEnd: 440.0, padding: 0.01875, defaultSlot: 37)
		case .itu270Cm:
			self.init(freqStart: 420.0, freqEnd: 450.0, padding: 0.01875, defaultSlot: 137)
		case .itu370Cm:
			self.init(freqStart: 430.0, freqEnd: 450.0, padding: 0.01875, defaultSlot: 37)
		case .itu2125Cm:
			self.init(freqStart: 220.0, freqEnd: 225.0, padding: 0.01875, defaultSlot: 37)
		}
	}

	private init(
		freqStart: Double,
		freqEnd: Double,
		wideLoRa: Bool = false,
		spacing: Double = 0,
		padding: Double = 0,
		defaultSlot: Int = 0
	) {
		self.freqStart = freqStart
		self.freqEnd = freqEnd
		self.wideLoRa = wideLoRa
		self.spacing = spacing
		self.padding = padding
		self.defaultSlot = defaultSlot
	}
}

// MARK: - ModemPresets bandwidth / default channel name

extension ModemPresets {
	var androidChannelName: String {
		switch self {
		case .longModerate:
			return "LongMod"
		default:
			return name
		}
	}

	var bandwidthMHz: Double {
		switch self {
		case .longTurbo, .shortTurbo, .mediumTurbo:
			return 0.5
		case .longFast, .medFast, .medSlow, .shortFast, .shortSlow:
			return 0.25
		case .longModerate, .longSlow, .liteFast, .liteSlow:
			return 0.125
		case .narrowFast, .narrowSlow:
			return 0.0625
		case .tinyFast, .tinySlow:
			return 0.0156
		}
	}
}
