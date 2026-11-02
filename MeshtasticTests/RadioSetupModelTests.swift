//
//  RadioSetupModelTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
import Foundation
import Testing
import MeshtasticProtobufs
@testable import Meshtastic

@Suite("RadioSetupModel")
@MainActor
struct RadioSetupModelTests {

	private func model(
		region: RegionCodes = .unset,
		preset: ModemPresets = .longFast,
		supports2_8: Bool = true,
		appliesWithoutReboot: Bool = true,
		isLicensed: Bool = false,
		longName: String = "Meshtastic 1234",
		shortName: String = "1234"
	) -> RadioSetupModel {
		var lora = Config.LoRaConfig()
		lora.usePreset = true
		lora.region = region.protoEnumValue()
		lora.modemPreset = preset.protoEnumValue()
		return RadioSetupModel(
			nodeNum: 0x1234, deviceName: "Meshtastic 1234", hardwareName: "T-Beam", hardwareModelId: 4,
			firmwareVersion: "2.8.0", supports2_8: supports2_8, appliesWithoutReboot: appliesWithoutReboot,
			isLicensed: isLicensed, longNameLimit: 24, loRaConfig: lora, longName: longName, shortName: shortName)
	}

	// MARK: Steps

	@Test func pagesRunRegionPresetNameDone() {
		#expect(RadioSetupModel.nextStep(after: .intro, isLicensed: false) == .region)
		#expect(RadioSetupModel.nextStep(after: .region, isLicensed: false) == .preset)
		#expect(RadioSetupModel.nextStep(after: .preset, isLicensed: false) == .name)
		#expect(RadioSetupModel.nextStep(after: .name, isLicensed: false) == .done)
		#expect(RadioSetupModel.nextStep(after: .done, isLicensed: false) == nil)
	}

	@Test func licensedOperatorsSkipTheNamePage() {
		#expect(RadioSetupModel.nextStep(after: .preset, isLicensed: true) == .done)
	}

	@Test func advancePushesTheNextPage() {
		let model = model()
		model.advance(from: .intro)
		model.advance(from: .region)
		#expect(model.path == [.region, .preset])
		model.advance(from: .done)
		#expect(model.path == [.region, .preset])
	}

	@Test func everyStepHasItsOwnScreenName() {
		#expect(Set(RadioSetupStep.allCases.map(\.screenName)).count == RadioSetupStep.allCases.count)
	}

	// MARK: Region and preset

	@Test func nothingChangesUntilTheUserDoes() {
		let model = model(region: .us, preset: .longTurbo)
		#expect(!model.hasLoRaChanges)
		#expect(!model.hasNameChanges)
		#expect(model.hasChosenRegion)
		#expect(!model.restartsOnLoRaSave)
	}

	@Test func anUnsetRegionCannotContinue() {
		#expect(!model().hasChosenRegion)
		#expect(model().isRegionSupported, "unset is a region this app knows, just not one to keep")
	}

	@Test func aRegionFromNewerFirmwareIsNotSupported() {
		var lora = Config.LoRaConfig()
		lora.usePreset = true
		lora.region = .UNRECOGNIZED(999)
		let model = RadioSetupModel(
			nodeNum: 1, deviceName: "Radio", hardwareName: nil, hardwareModelId: nil, firmwareVersion: nil,
			supports2_8: true, appliesWithoutReboot: true, isLicensed: false, longNameLimit: 24,
			loRaConfig: lora, longName: "", shortName: "")
		#expect(!model.isRegionSupported)
		#expect(!model.hasChosenRegion)
		#expect(model.region == nil)
	}

	@Test func thePhonesRegionStartsTheDraftWhenTheRadioHasNone() {
		let fresh = model()
		fresh.applySuggestedRegion(.us, regionInfo: nil)
		#expect(fresh.suggestedRegion == .us)
		#expect(fresh.region == .us)
		#expect(fresh.preset == .longTurbo, "the fresh-US rule applies to the suggestion too")
		#expect(fresh.hasLoRaChanges)
		#expect(fresh.hasChosenRegion)
	}

	@Test func aRadioWithARegionKeepsIt() {
		let configured = model(region: .eu868)
		configured.applySuggestedRegion(.us, regionInfo: nil)
		#expect(configured.suggestedRegion == nil)
		#expect(configured.region == .eu868)
		#expect(!configured.hasLoRaChanges)
		let fresh = model()
		fresh.applySuggestedRegion(nil, regionInfo: nil)
		#expect(fresh.suggestedRegion == nil)
		#expect(!fresh.hasChosenRegion)
	}

	@Test func theSuggestionComesFromTheLocalesRegion() {
		#expect(RegionCodes.suggested(for: Locale(identifier: "en_US")) == .us)
		#expect(RegionCodes.suggested(for: Locale(identifier: "de_DE")) == .eu868)
		#expect(RegionCodes.suggested(for: Locale(identifier: "en_AU")) == .anz)
		#expect(RegionCodes.suggested(for: Locale(identifier: "en")) == nil)
		#expect(RegionCodes.suggested(forCountryCode: "ca") == .us)
		#expect(RegionCodes.suggested(forCountryCode: "BR") == .br902)
		#expect(RegionCodes.suggested(forCountryCode: "ZA") == .eu868)
		#expect(RegionCodes.suggested(forCountryCode: "AQ") == nil)
	}

	@Test func aFreshUSRadioMovesToLongTurbo() {
		let model = model()
		model.selectRegion(.us, regionInfo: nil)
		#expect(model.region == .us)
		#expect(model.preset == .longTurbo)
		#expect(model.draft.usePreset)
		#expect(model.hasLoRaChanges)
	}

	@Test func aPresetTheRegionForbidsFallsBackToItsDefault() {
		let model = model(region: .us, preset: .longTurbo)
		let narrow = RegionPresetInfo(presets: [.narrowFast, .narrowSlow], defaultPreset: .narrowFast, licensedOnly: false)
		model.selectRegion(.euN868, regionInfo: narrow)
		#expect(model.preset == .narrowFast)
	}

	@Test func aLegalPresetIsKeptWhenTheRegionChanges() {
		let model = model(region: .us, preset: .shortFast)
		model.selectRegion(.anz, regionInfo: nil)
		#expect(model.preset == .shortFast)
		let anz = RegionPresetInfo(presets: [.longFast, .shortFast], defaultPreset: .longFast, licensedOnly: false)
		model.selectRegion(.anz, regionInfo: anz)
		#expect(model.preset == .shortFast)
	}

	@Test func oldFirmwareNeverChangesThePreset() {
		let model = model(supports2_8: false)
		model.selectRegion(.us, regionInfo: nil)
		#expect(model.preset == .longFast)
	}

	@Test func theRestartWarningFollowsTheFirmwareGate() {
		let restarting = model(appliesWithoutReboot: false)
		restarting.selectRegion(.us, regionInfo: nil)
		#expect(restarting.restartsOnLoRaSave)
		let live = model(appliesWithoutReboot: true)
		live.selectRegion(.us, regionInfo: nil)
		#expect(!live.restartsOnLoRaSave)
	}

	@Test func availablePresetsFollowTheSharedRule() {
		let model = model(region: .eu868, preset: .longTurbo)
		let presets = model.availablePresets(regionInfo: nil)
		#expect(presets == ModemPresets.available(forRegion: .eu868, current: .longTurbo, supports2_8: true, regionInfo: nil))
		#expect(presets.last == .longTurbo, "what the radio is on stays visible")
	}

	@Test func theUSWarningOnlyNamesNonTurboPresets() {
		#expect(model(region: .us, preset: .longFast).usBandwidthWarning != nil)
		#expect(model(region: .us, preset: .longTurbo).usBandwidthWarning == nil)
	}

	// MARK: Names

	@Test func namesAreTrimmedToTheRadiosLimits() {
		let model = model()
		model.setLongName(String(repeating: "a", count: 30))
		#expect(model.longName.utf8.count == 24)
		model.setShortName("ABCDE")
		#expect(model.shortName == "ABCD")
		model.setShortName("🙂🙂")
		#expect(model.shortName == "🙂")
		#expect(model.hasNameChanges)
	}

	@Test func theNameSaveNeedsBothNamesAndAConnectedRadio() {
		let model = model()
		#expect(model.canSaveName)
		model.setShortName("")
		#expect(!model.canSaveName)
		model.setShortName("AB")
		model.isAwaitingReconnect = true
		#expect(!model.canSaveName)
	}

	@Test func summariesReadBackWhatWasChosen() {
		let chosen = model(region: .us, preset: .longTurbo)
		#expect(chosen.presetSummary == ModemPresets.longTurbo.description)
		#expect(chosen.nameSummary == "Meshtastic 1234 (1234)")
		#expect(chosen.radioSummary == "T-Beam · Firmware 2.8.0")
		let unnamed = model(longName: "", shortName: "")
		#expect(unnamed.nameSummary == "Not set")
	}
}
