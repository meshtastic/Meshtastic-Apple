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
	let config: LoRaConfigEntity?

	private var region: RegionInfo? {
		RegionInfo(regionCode: Int(config?.regionCode ?? 0))
	}

	var regionName: String {
		guard let regionCode = RegionCodes(rawValue: Int(config?.regionCode ?? 0)) else {
			return "Unknown region"
		}
		return regionCode.description
	}

	/// The radio's current operating slot. Respects a non-zero `channelNum` override
	/// (the firmware pins the slot when set); otherwise derives it from the primary
	/// channel name.
	func effectiveChannelSlot(primaryName: String) -> Int {
		if let channelNum = config?.channelNum, channelNum != 0 {
			return Int(channelNum)
		}
		let numChannels = numChannels()
		guard numChannels > 0 else { return 0 }
		return Int(djb2Hash(primaryName) % UInt32(numChannels)) + 1
	}

	/// The slot a channel with `name` would operate on, **always** derived from the
	/// name (ignoring any `channelNum` override). This is the slot a beacon's offered
	/// channel resolves to on its own mesh, used to decide whether the connected radio
	/// (whose slot comes from `effectiveChannelSlot`) can already hear it.
	func slotForChannelName(_ name: String) -> Int {
		let numChannels = numChannels()
		return numChannels > 0 ? Int(djb2Hash(name) % UInt32(numChannels)) + 1 : 0
	}

	func radioFrequencyMHz(slot: Int) -> Double {
		guard let config else { return 0 }
		if config.overrideFrequency != 0 {
			return Double(config.overrideFrequency)
		}
		guard let region else { return 0 }
		let bandwidth = bandwidthMHz(region: region)
		guard bandwidth > 0, slot > 0 else { return 0 }
		return region.freqStart + bandwidth / 2 + Double(slot - 1) * bandwidth
	}

	private func numChannels() -> Int {
		guard let region else { return 0 }
		let bandwidth = bandwidthMHz(region: region)
		guard bandwidth > 0 else { return 1 }
		return max(Int(floor((region.freqEnd - region.freqStart) / bandwidth)), 1)
	}

	private func bandwidthMHz(region: RegionInfo) -> Double {
		guard let config else { return 0 }
		if config.usePreset {
			let presetBandwidth = ModemPresets(rawValue: Int(config.modemPreset))?.bandwidthMHz ?? 0
			return presetBandwidth * (region.wideLoRa ? 3.25 : 1)
		}
		switch config.bandwidth {
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
			return Double(config.bandwidth) / 1000
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
		case .itu12M, .itu22M:
			self.init(freqStart: 144.0, freqEnd: 148.0)
		case .eu866:
			self.init(freqStart: 866.0, freqEnd: 866.5)
		case .eu874:
			self.init(freqStart: 873.0, freqEnd: 876.0)
		case .eu917:
			self.init(freqStart: 917.0, freqEnd: 921.0)
		case .euN868:
			self.init(freqStart: 869.4, freqEnd: 869.65)
		case .itu32M:
			// ITU Region 3 Amateur Radio 2m band.
			self.init(freqStart: 144.0, freqEnd: 148.0)
		case .itu170Cm:
			// ITU Region 1 Amateur Radio 70cm band.
			self.init(freqStart: 430.0, freqEnd: 440.0)
		case .itu270Cm:
			// ITU Region 2 Amateur Radio 70cm band.
			self.init(freqStart: 420.0, freqEnd: 450.0)
		case .itu370Cm:
			// ITU Region 3 Amateur Radio 70cm band.
			self.init(freqStart: 430.0, freqEnd: 450.0)
		case .itu2125Cm:
			// ITU Region 2 Amateur Radio 1.25m (125cm) band.
			self.init(freqStart: 220.0, freqEnd: 225.0)
		}
	}

	private init(freqStart: Double, freqEnd: Double, wideLoRa: Bool = false) {
		self.freqStart = freqStart
		self.freqEnd = freqEnd
		self.wideLoRa = wideLoRa
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
		case .longTurbo, .shortTurbo:
			return 0.5
		case .longFast, .medFast, .medSlow, .shortFast, .shortSlow:
			return 0.25
		case .longModerate, .longSlow, .liteFast, .liteSlow:
			return 0.125
		case .narrowFast, .narrowSlow:
			return 0.0625
		case .tinyFast, .tinySlow:
			return 0.020
		}
	}
}
