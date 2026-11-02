//
//  RadioSetupModel.swift
//  Meshtastic
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
//  The state of the radio setup flow: plain values copied from the connected node, the
//  draft LoRa config and names, and the saves. Nothing here holds a SwiftData object, so a
//  restart or reconnect in the middle of the flow leaves it standing.
//

import Foundation
import MeshtasticProtobufs
import SwiftData

enum RadioSetupStep: Hashable, CaseIterable {
	case intro, region, preset, name, done

	var screenName: ScreenName {
		switch self {
		case .intro: .radioSetupIntro
		case .region: .radioSetupRegion
		case .preset: .radioSetupPreset
		case .name: .radioSetupName
		case .done: .radioSetupDone
		}
	}
}

@MainActor @Observable
final class RadioSetupModel {
	static let shortNameBytes = 4

	let nodeNum: Int64
	let deviceName: String
	let hardwareName: String?
	let hardwareModelId: Int32?
	let firmwareVersion: String?
	let supports2_8: Bool
	/// The strict gate: a LoRa change restarts the radio unless the live firmware says otherwise.
	let appliesWithoutReboot: Bool
	/// A licensed operator's long name is made from the call sign, so the name page is skipped.
	let isLicensed: Bool
	let longNameLimit: Int
	let isUnmessagable: Bool

	/// What the radio reported, and the draft the pages edit.
	private(set) var loaded: Config.LoRaConfig
	var draft: Config.LoRaConfig
	private(set) var loadedLongName: String
	private(set) var loadedShortName: String
	private(set) var longName: String
	private(set) var shortName: String

	/// The region taken from the phone's region setting when the radio had none, so the
	/// region page can say where it came from. Nil when the radio already had one or the
	/// setting gave no answer.
	private(set) var suggestedRegion: RegionCodes?

	var path: [RadioSetupStep] = []
	var isSaving = false
	var saveError: String?
	/// Set after a LoRa save on firmware that restarts for it, until the radio is back.
	var isAwaitingReconnect = false

	init(
		nodeNum: Int64,
		deviceName: String,
		hardwareName: String?,
		hardwareModelId: Int32?,
		firmwareVersion: String?,
		supports2_8: Bool,
		appliesWithoutReboot: Bool,
		isLicensed: Bool,
		longNameLimit: Int,
		loRaConfig: Config.LoRaConfig,
		longName: String,
		shortName: String,
		isUnmessagable: Bool = false
	) {
		self.nodeNum = nodeNum
		self.deviceName = deviceName
		self.hardwareName = hardwareName
		self.hardwareModelId = hardwareModelId
		self.firmwareVersion = firmwareVersion
		self.supports2_8 = supports2_8
		self.appliesWithoutReboot = appliesWithoutReboot
		self.isLicensed = isLicensed
		self.longNameLimit = longNameLimit
		self.isUnmessagable = isUnmessagable
		self.loaded = loRaConfig
		self.draft = loRaConfig
		self.loadedLongName = longName
		self.loadedShortName = shortName
		self.longName = longName
		self.shortName = shortName
	}

	/// Copies what the flow needs from the node in the store. Nil when the node is not there.
	convenience init?(nodeNum: Int64, context: ModelContext, accessoryManager: AccessoryManager) {
		guard let node = getNodeInfo(id: nodeNum, context: context) else { return nil }
		let supports2_8 = accessoryManager.checkIsVersionSupported(forVersion: "2.8.0")
		var lora = node.loRaConfig.map { Config.LoRaConfig(entity: $0) } ?? Config.LoRaConfig()
		if node.loRaConfig == nil {
			// A radio that has not sent its config yet runs on a preset, like the firmware default.
			lora.usePreset = true
		}
		let hardwareModelId = node.user?.hwModelId ?? 0
		self.init(
			nodeNum: nodeNum,
			deviceName: node.user?.longName ?? String(localized: "Connected radio", comment: "Radio setup; name shown when the radio has none"),
			hardwareName: node.user?.hwDisplayName ?? node.user?.hwModel,
			hardwareModelId: hardwareModelId > 0 ? hardwareModelId : nil,
			firmwareVersion: node.metadata?.firmwareVersion ?? accessoryManager.connectedVersion,
			supports2_8: supports2_8,
			appliesWithoutReboot: accessoryManager.appliesLoRaConfigWithoutReboot,
			isLicensed: node.user?.isLicensed ?? false,
			longNameLimit: NodeNameLimits.longNameBytes(storesCompactNames: supports2_8),
			loRaConfig: lora,
			longName: node.user?.longName ?? "",
			shortName: node.user?.shortName ?? "",
			isUnmessagable: node.user?.unmessagable ?? false
		)
		let suggested = RegionCodes.suggested(for: .current)
		applySuggestedRegion(suggested, regionInfo: suggested.flatMap { accessoryManager.loRaRegionPresets[$0.protoEnumValue()] })
	}

	// MARK: - What the pages show

	var region: RegionCodes? { RegionCodes(rawValue: draft.region.rawValue) }
	var preset: ModemPresets? { ModemPresets(rawValue: draft.modemPreset.rawValue) }

	/// A region this app can write back. The radio may report one from newer firmware.
	var isRegionSupported: Bool {
		LoRaRegionValidation.supportedRegion(rawValue: draft.region.rawValue) != nil
	}

	var hasChosenRegion: Bool { isRegionSupported && draft.region != .unset }

	var hasLoRaChanges: Bool {
		draft.region != loaded.region || draft.modemPreset != loaded.modemPreset || draft.usePreset != loaded.usePreset
	}

	var restartsOnLoRaSave: Bool { hasLoRaChanges && !appliesWithoutReboot }

	var hasNameChanges: Bool { longName != loadedLongName || shortName != loadedShortName }

	var canSaveName: Bool {
		!longName.trimmingCharacters(in: .whitespaces).isEmpty && !shortName.isEmpty && !isAwaitingReconnect
	}

	/// The hardware and firmware the radio reported, for the intro page.
	var radioSummary: String? {
		var parts: [String] = []
		if let hardwareName { parts.append(hardwareName) }
		if let firmwareVersion {
			parts.append(String.localizedStringWithFormat(
				String(localized: "Firmware %@", comment: "Radio setup intro; the argument is the version"), firmwareVersion))
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}

	var presetSummary: String {
		guard draft.usePreset else {
			return String(localized: "Custom", comment: "LoRa preset shown when the radio uses its own modem settings")
		}
		return preset?.description ?? ModemPresets.longFast.description
	}

	var nameSummary: String {
		guard !longName.isEmpty else { return String(localized: "Not set", comment: "Radio setup summary") }
		return shortName.isEmpty ? longName : "\(longName) (\(shortName))"
	}

	var usBandwidthWarning: String? {
		ModemPresets.usBandwidthWarning(region: region, preset: preset, supports2_8: supports2_8)
	}

	func availablePresets(regionInfo: RegionPresetInfo?) -> [ModemPresets] {
		ModemPresets.available(forRegion: region, current: preset, supports2_8: supports2_8, regionInfo: regionInfo)
	}

	// MARK: - Choices

	/// Picks a region and, on 2.8, the preset that goes with it: Long Turbo for a fresh US
	/// radio, or the region's default when the current preset is not legal there. A fresh
	/// radio runs on a preset; a configured one keeps its mode, so custom modem settings
	/// survive a region change until a preset is chosen on the next page.
	func selectRegion(_ region: RegionCodes, regionInfo: RegionPresetInfo?) {
		let factoryFresh = loaded.region == .unset
		draft.region = region.protoEnumValue()
		if factoryFresh {
			draft.usePreset = true
		}
		if let next = ModemPresets.presetToSelect(
			forRegion: draft.region,
			factoryFresh: factoryFresh,
			supports2_8: supports2_8,
			usePreset: draft.usePreset,
			regionInfo: regionInfo,
			currentPreset: preset) {
			draft.modemPreset = next.protoEnumValue()
		}
	}

	/// Starts the draft on `region` when the radio has none, and remembers it so the region
	/// page asks for a confirmation rather than a choice. A radio that already has a region
	/// keeps it.
	func applySuggestedRegion(_ region: RegionCodes?, regionInfo: RegionPresetInfo?) {
		guard let region, loaded.region == .unset,
			  RegionCodes.selectable(supports2_8: supports2_8).contains(region) else { return }
		suggestedRegion = region
		selectRegion(region, regionInfo: regionInfo)
	}

	func selectPreset(_ preset: ModemPresets) {
		draft.modemPreset = preset.protoEnumValue()
		draft.usePreset = true
	}

	func setLongName(_ typed: String) {
		longName = NodeNameLimits.trimmed(typed.withoutVariationSelectors, toBytes: longNameLimit)
	}

	func setShortName(_ typed: String) {
		shortName = NodeNameLimits.trimmed(typed.withoutVariationSelectors, toBytes: Self.shortNameBytes)
	}

	// MARK: - Steps

	/// The page after `step`. Licensed operators skip the name page: their long name is made
	/// from the call sign in User Config.
	static func nextStep(after step: RadioSetupStep, isLicensed: Bool) -> RadioSetupStep? {
		switch step {
		case .intro: .region
		case .region: .preset
		case .preset: isLicensed ? .done : .name
		case .name: .done
		case .done: nil
		}
	}

	func advance(from step: RadioSetupStep) {
		guard let next = Self.nextStep(after: step, isLicensed: isLicensed) else { return }
		path.append(next)
	}

	// MARK: - Saves

	private static var notConnectedMessage: String {
		String(localized: "Your radio is not connected. Reconnect and try again.", comment: "Radio setup save error")
	}

	/// The connected radio's user record, fetched at save time so a reconnect in the middle
	/// of the flow never leaves a stale object in hand.
	private func connectedUser(_ accessoryManager: AccessoryManager, _ context: ModelContext) -> UserEntity? {
		guard accessoryManager.isConnected, accessoryManager.activeDeviceNum == nodeNum,
			  let node = getNodeInfo(id: nodeNum, context: context) else { return nil }
		return node.user
	}

	/// Writes the region and preset when they changed. Returns whether the flow may move on.
	@discardableResult
	func saveLoRa(using accessoryManager: AccessoryManager, context: ModelContext) async -> Bool {
		guard hasLoRaChanges else { return true }
		guard let user = connectedUser(accessoryManager, context) else {
			saveError = Self.notConnectedMessage
			return false
		}
		isSaving = true
		saveError = nil
		defer { isSaving = false }
		do {
			UserDefaults.modemPreset = draft.modemPreset.rawValue
			_ = try await accessoryManager.saveLoRaConfig(config: draft, fromUser: user, toUser: user)
			// On 2.8 the change applies live, so ask for the node database to pick up the
			// radio's answers for the new settings.
			accessoryManager.refreshNodeDatabaseAfterLoRaChange()
			isAwaitingReconnect = !appliesWithoutReboot
			loaded = draft
			return true
		} catch {
			saveError = error.localizedDescription
			return false
		}
	}

	/// Writes the names when they changed. Returns whether the flow may move on.
	@discardableResult
	func saveName(using accessoryManager: AccessoryManager, context: ModelContext) async -> Bool {
		guard hasNameChanges else { return true }
		guard let user = connectedUser(accessoryManager, context) else {
			saveError = Self.notConnectedMessage
			return false
		}
		isSaving = true
		saveError = nil
		defer { isSaving = false }
		var owner = User()
		owner.longName = longName
		owner.shortName = shortName
		owner.isUnmessagable = isUnmessagable
		do {
			_ = try await accessoryManager.saveUser(config: owner, fromUser: user, toUser: user)
			loadedLongName = longName
			loadedShortName = shortName
			return true
		} catch {
			saveError = error.localizedDescription
			return false
		}
	}
}
