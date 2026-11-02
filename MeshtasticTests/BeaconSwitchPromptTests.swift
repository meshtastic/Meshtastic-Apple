//
//  BeaconSwitchPromptTests.swift
//  MeshtasticTests
//
//  Copyright(c) Garth Vander Houwen 11/2/26.
//
import Testing
@testable import Meshtastic

/// The Switch confirmation names everything the join changes and says whether the radio
/// reboots for it.
@Suite("Beacon switch prompt")
struct BeaconSwitchPromptTests {

	@Test func namesEverythingTheJoinChanges() {
		let prompt = AccessoryManager.beaconSwitchPrompt(
			channelName: "MyMesh", preset: .longFast, region: .us, frequencySlot: 20, appliesWithoutReboot: false)
		#expect(prompt.hasPrefix("This sets your radio's primary channel to \"MyMesh\","))
		#expect(prompt.contains("the \(ModemPresets.longFast.description) preset"))
		#expect(prompt.contains("region \(RegionCodes.us.description)"))
		#expect(prompt.contains("frequency slot 20."))
	}

	@Test func aBeaconWithoutRegionOrSlotNamesOnlyTheChannelAndPreset() {
		let prompt = AccessoryManager.beaconSwitchPrompt(
			channelName: "MyMesh", preset: .longFast, region: nil, frequencySlot: nil, appliesWithoutReboot: false)
		#expect(prompt.hasPrefix("This sets your radio's primary channel to \"MyMesh\" and the \(ModemPresets.longFast.description) preset."))
		#expect(!prompt.contains("region"))
		#expect(!prompt.contains("slot"))
	}

	@Test func saysRebootOnlyBeforeFirmware28() {
		let old = AccessoryManager.beaconSwitchPrompt(
			channelName: "MyMesh", preset: .longFast, region: nil, frequencySlot: nil, appliesWithoutReboot: false)
		#expect(old.contains("will reboot and reconnect"))
		let live = AccessoryManager.beaconSwitchPrompt(
			channelName: "MyMesh", preset: .longFast, region: nil, frequencySlot: nil, appliesWithoutReboot: true)
		#expect(live.contains("without a reboot"))
		#expect(!live.contains("reboot and reconnect"))
		#expect(live.hasSuffix("Your previous channel settings will be replaced."))
	}
}
